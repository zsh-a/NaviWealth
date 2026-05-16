//! Anthropic SSE event mapping.

use std::collections::BTreeMap;

use serde_json::{json, Value};

use crate::ai::runtime::{AgentEvent, StopReason};
use crate::error::AppError;

#[derive(Debug, Clone, Default, PartialEq)]
pub struct StreamState {
    blocks: BTreeMap<usize, BlockState>,
}

#[derive(Debug, Clone, Default, PartialEq)]
struct BlockState {
    ty: String,
    id: Option<String>,
    name: Option<String>,
    input_json: String,
    input: Option<Value>,
}

pub fn map_sse_text(sse: &str) -> Result<Vec<AgentEvent>, AppError> {
    let mut state = StreamState::default();
    let mut events = Vec::new();

    for data in sse_data_frames(sse) {
        let (next_state, mut mapped) = map_sse_frame(&state, &data)?;
        state = next_state;
        events.append(&mut mapped);
    }

    Ok(events)
}

pub fn map_sse_frame(
    state: &StreamState,
    frame_data: &str,
) -> Result<(StreamState, Vec<AgentEvent>), AppError> {
    if frame_data.trim().is_empty() || frame_data.trim() == "[DONE]" {
        return Ok((state.clone(), Vec::new()));
    }

    let event: Value = serde_json::from_str(frame_data)
        .map_err(|e| AppError::Internal(format!("llm stream json: {e}")))?;
    let event_type = event
        .get("type")
        .and_then(Value::as_str)
        .unwrap_or_default();

    let mut next_state = state.clone();
    let events = match event_type {
        "message_start" => usage_event(event.pointer("/message/usage"))
            .into_iter()
            .collect(),
        "content_block_start" => map_content_block_start(&mut next_state, &event),
        "content_block_delta" => map_content_block_delta(&mut next_state, &event),
        "content_block_stop" => map_content_block_stop(&mut next_state, &event),
        "message_delta" => map_message_delta(&event),
        "error" => vec![map_error(&event)],
        "message_stop" | "ping" => Vec::new(),
        _ => Vec::new(),
    };

    Ok((next_state, events))
}

fn map_content_block_start(state: &mut StreamState, event: &Value) -> Vec<AgentEvent> {
    let index = event_index(event);
    let content_block = event.get("content_block").unwrap_or(&Value::Null);
    let ty = content_block
        .get("type")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string();
    let id = content_block
        .get("id")
        .and_then(Value::as_str)
        .map(ToOwned::to_owned);
    let name = content_block
        .get("name")
        .and_then(Value::as_str)
        .map(ToOwned::to_owned);

    state.blocks.insert(
        index,
        BlockState {
            ty: ty.clone(),
            id: id.clone(),
            name: name.clone(),
            input: content_block.get("input").cloned(),
            ..Default::default()
        },
    );

    match ty.as_str() {
        "text" => content_block
            .get("text")
            .and_then(Value::as_str)
            .filter(|text| !text.is_empty())
            .map(|text| {
                vec![AgentEvent::TextDelta {
                    text: text.to_string(),
                }]
            })
            .unwrap_or_default(),
        "thinking" => content_block
            .get("thinking")
            .and_then(Value::as_str)
            .filter(|text| !text.is_empty())
            .map(|text| {
                vec![AgentEvent::ThinkingDelta {
                    text: text.to_string(),
                }]
            })
            .unwrap_or_default(),
        "tool_use" => vec![AgentEvent::ToolCallStart {
            id: id.unwrap_or_default(),
            name: name.unwrap_or_default(),
        }],
        _ => Vec::new(),
    }
}

fn map_content_block_delta(state: &mut StreamState, event: &Value) -> Vec<AgentEvent> {
    let index = event_index(event);
    let delta = event.get("delta").unwrap_or(&Value::Null);

    match delta.get("type").and_then(Value::as_str) {
        Some("text_delta") => delta
            .get("text")
            .and_then(Value::as_str)
            .map(|text| {
                vec![AgentEvent::TextDelta {
                    text: text.to_string(),
                }]
            })
            .unwrap_or_default(),
        Some("thinking_delta") => delta
            .get("thinking")
            .and_then(Value::as_str)
            .map(|text| {
                vec![AgentEvent::ThinkingDelta {
                    text: text.to_string(),
                }]
            })
            .unwrap_or_default(),
        Some("input_json_delta") => {
            let partial = delta
                .get("partial_json")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_string();
            let block = state.blocks.entry(index).or_default();
            block.input_json.push_str(&partial);
            vec![AgentEvent::ToolCallDelta {
                id: block.id.clone().unwrap_or_default(),
                partial_input_json: partial,
            }]
        }
        _ => Vec::new(),
    }
}

fn map_content_block_stop(state: &mut StreamState, event: &Value) -> Vec<AgentEvent> {
    let index = event_index(event);
    let Some(block) = state.blocks.remove(&index) else {
        return Vec::new();
    };

    if block.ty != "tool_use" {
        return Vec::new();
    }

    vec![AgentEvent::ToolCallEnd {
        id: block.id.unwrap_or_default(),
        input: tool_input(block.input, &block.input_json),
    }]
}

fn map_message_delta(event: &Value) -> Vec<AgentEvent> {
    let mut events = Vec::new();
    if let Some(usage) = usage_event(event.get("usage")) {
        events.push(usage);
    }
    if let Some(reason) = event
        .pointer("/delta/stop_reason")
        .and_then(Value::as_str)
        .and_then(stop_reason)
    {
        events.push(AgentEvent::Stop { reason, rounds: 0 });
    }
    events
}

fn map_error(event: &Value) -> AgentEvent {
    let error = event.get("error").unwrap_or(&Value::Null);
    AgentEvent::Error {
        code: error
            .get("type")
            .and_then(Value::as_str)
            .unwrap_or("provider_error")
            .to_string(),
        message: error
            .get("message")
            .and_then(Value::as_str)
            .unwrap_or("provider stream error")
            .to_string(),
    }
}

fn usage_event(usage: Option<&Value>) -> Option<AgentEvent> {
    let usage = usage?;
    Some(AgentEvent::Usage {
        input_tokens: usage_u32(usage, "input_tokens"),
        output_tokens: usage_u32(usage, "output_tokens"),
        cache_read_tokens: usage_u32(usage, "cache_read_input_tokens"),
        cache_write_tokens: usage_u32(usage, "cache_creation_input_tokens"),
    })
}

fn usage_u32(usage: &Value, key: &str) -> u32 {
    usage.get(key).and_then(Value::as_u64).unwrap_or(0) as u32
}

fn stop_reason(reason: &str) -> Option<StopReason> {
    match reason {
        "end_turn" => Some(StopReason::EndTurn),
        "max_tokens" => Some(StopReason::MaxTokens),
        "tool_use" => Some(StopReason::ToolUse),
        "refusal" => Some(StopReason::Refusal),
        _ => None,
    }
}

fn tool_input(initial: Option<Value>, partial_json: &str) -> Value {
    if partial_json.trim().is_empty() {
        initial.unwrap_or_else(|| json!({}))
    } else {
        serde_json::from_str(partial_json).unwrap_or(Value::Null)
    }
}

fn event_index(event: &Value) -> usize {
    event.get("index").and_then(Value::as_u64).unwrap_or(0) as usize
}

fn sse_data_frames(sse: &str) -> Vec<String> {
    sse.split("\n\n")
        .filter_map(|frame| {
            let data = frame
                .lines()
                .filter_map(|line| line.strip_prefix("data: "))
                .collect::<Vec<_>>()
                .join("\n");
            if data.trim().is_empty() {
                None
            } else {
                Some(data)
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn maps_text_delta() {
        let events = map_sse_text(concat!(
            "event: content_block_start\n",
            "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\n\n",
            "event: content_block_delta\n",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"hello\"}}\n\n",
        ))
        .unwrap();

        assert_eq!(
            events,
            vec![AgentEvent::TextDelta {
                text: "hello".into()
            }]
        );
    }

    #[test]
    fn maps_tool_use_start_delta_and_stop() {
        let events = map_sse_text(concat!(
            "event: content_block_start\n",
            "data: {\"type\":\"content_block_start\",\"index\":1,\"content_block\":{\"type\":\"tool_use\",\"id\":\"toolu_1\",\"name\":\"get_risk_alerts\",\"input\":{}}}\n\n",
            "event: content_block_delta\n",
            "data: {\"type\":\"content_block_delta\",\"index\":1,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"{\\\"as_of\\\":\"}}\n\n",
            "event: content_block_delta\n",
            "data: {\"type\":\"content_block_delta\",\"index\":1,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"\\\"2026-05-07\\\"}\"}}\n\n",
            "event: content_block_stop\n",
            "data: {\"type\":\"content_block_stop\",\"index\":1}\n\n",
        ))
        .unwrap();

        assert_eq!(
            events,
            vec![
                AgentEvent::ToolCallStart {
                    id: "toolu_1".into(),
                    name: "get_risk_alerts".into(),
                },
                AgentEvent::ToolCallDelta {
                    id: "toolu_1".into(),
                    partial_input_json: "{\"as_of\":".into(),
                },
                AgentEvent::ToolCallDelta {
                    id: "toolu_1".into(),
                    partial_input_json: "\"2026-05-07\"}".into(),
                },
                AgentEvent::ToolCallEnd {
                    id: "toolu_1".into(),
                    input: json!({"as_of": "2026-05-07"}),
                },
            ]
        );
    }

    #[test]
    fn maps_usage_from_message_start_and_delta() {
        let events = map_sse_text(concat!(
            "event: message_start\n",
            "data: {\"type\":\"message_start\",\"message\":{\"usage\":{\"input_tokens\":11,\"output_tokens\":1,\"cache_read_input_tokens\":2,\"cache_creation_input_tokens\":3}}}\n\n",
            "event: message_delta\n",
            "data: {\"type\":\"message_delta\",\"usage\":{\"output_tokens\":7}}\n\n",
        ))
        .unwrap();

        assert_eq!(
            events,
            vec![
                AgentEvent::Usage {
                    input_tokens: 11,
                    output_tokens: 1,
                    cache_read_tokens: 2,
                    cache_write_tokens: 3,
                },
                AgentEvent::Usage {
                    input_tokens: 0,
                    output_tokens: 7,
                    cache_read_tokens: 0,
                    cache_write_tokens: 0,
                },
            ]
        );
    }

    #[test]
    fn maps_message_delta_stop_reason() {
        let events = map_sse_text(concat!(
            "event: message_delta\n",
            "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"tool_use\"}}\n\n",
        ))
        .unwrap();

        assert_eq!(
            events,
            vec![AgentEvent::Stop {
                reason: StopReason::ToolUse,
                rounds: 0,
            }]
        );
    }
}
