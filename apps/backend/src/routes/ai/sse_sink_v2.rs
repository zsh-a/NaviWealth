//! v2 SSE sink for provider-neutral agent events.

use futures_channel::mpsc;
use serde_json::{json, Value};

use crate::ai::runtime::{AgentEvent, EventSink, StopReason};
use crate::ai::sse::encode_event;
use crate::error::AppError;

pub struct SseEventSinkV2 {
    tx: mpsc::UnboundedSender<Result<Vec<u8>, worker::Error>>,
}

impl SseEventSinkV2 {
    pub fn new(tx: mpsc::UnboundedSender<Result<Vec<u8>, worker::Error>>) -> Self {
        Self { tx }
    }

    fn send(&self, name: &str, payload: &Value) {
        let body = serde_json::to_string(payload).unwrap_or_else(|_| "{}".into());
        let _ = self.tx.unbounded_send(Ok(encode_event(name, &body)));
    }
}

impl EventSink for SseEventSinkV2 {
    fn emit(&mut self, event: AgentEvent) -> Result<(), AppError> {
        match event {
            AgentEvent::TextDelta { text } => {
                self.send("text_delta", &json!({ "text": text }));
            }
            AgentEvent::ThinkingDelta { text } => {
                self.send("thinking_delta", &json!({ "text": text }));
            }
            AgentEvent::ToolCallStart { id, name } => {
                self.send("tool_call_start", &json!({ "id": id, "name": name }));
            }
            AgentEvent::ToolCallDelta {
                id,
                partial_input_json,
            } => {
                self.send(
                    "tool_call_delta",
                    &json!({ "id": id, "partial_input_json": partial_input_json }),
                );
            }
            AgentEvent::ToolCallEnd { id, input } => {
                self.send("tool_call_end", &json!({ "id": id, "input": input }));
            }
            AgentEvent::ToolResult { id, name, output } => {
                self.send(
                    "tool_result",
                    &json!({ "id": id, "name": name, "output": output }),
                );
            }
            AgentEvent::Usage {
                input_tokens,
                output_tokens,
                cache_read_tokens,
                cache_write_tokens,
            } => {
                self.send(
                    "usage",
                    &json!({
                        "input": input_tokens,
                        "output": output_tokens,
                        "cache_read": cache_read_tokens,
                        "cache_write": cache_write_tokens,
                    }),
                );
            }
            AgentEvent::Stop { reason, rounds } => {
                self.send(
                    "stop",
                    &json!({ "reason": stop_reason_wire(reason), "rounds": rounds }),
                );
            }
            AgentEvent::Error { code, message } => {
                self.send("error", &json!({ "code": code, "message": message }));
            }
        }
        Ok(())
    }
}

fn stop_reason_wire(reason: StopReason) -> &'static str {
    match reason {
        StopReason::EndTurn => "end_turn",
        StopReason::MaxTokens => "max_tokens",
        StopReason::ToolUse => "tool_use",
        StopReason::Refusal => "refusal",
        StopReason::Error => "error",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use futures_util::StreamExt;
    use serde_json::Value;

    async fn collect_frames(events: impl IntoIterator<Item = AgentEvent>) -> Vec<(String, Value)> {
        let (tx, mut rx) = mpsc::unbounded();
        {
            let mut sink = SseEventSinkV2::new(tx);
            for event in events {
                sink.emit(event).unwrap();
            }
        }

        let mut frames = Vec::new();
        while let Some(Ok(bytes)) = rx.next().await {
            let frame = String::from_utf8(bytes).unwrap();
            let event = frame
                .lines()
                .find_map(|line| line.strip_prefix("event: "))
                .unwrap()
                .to_string();
            let data = frame
                .lines()
                .find_map(|line| line.strip_prefix("data: "))
                .unwrap();
            frames.push((event, serde_json::from_str(data).unwrap()));
        }
        frames
    }

    #[test]
    fn maps_each_agent_event_to_v2_sse_frame() {
        let frames = futures_executor::block_on(collect_frames([
            AgentEvent::TextDelta {
                text: "hello".into(),
            },
            AgentEvent::ThinkingDelta {
                text: "checking context".into(),
            },
            AgentEvent::ToolCallStart {
                id: "toolu_1".into(),
                name: "net_worth_snapshot".into(),
            },
            AgentEvent::ToolCallDelta {
                id: "toolu_1".into(),
                partial_input_json: "{\"range\"".into(),
            },
            AgentEvent::ToolCallEnd {
                id: "toolu_1".into(),
                input: json!({ "range": "month" }),
            },
            AgentEvent::ToolResult {
                id: "toolu_1".into(),
                name: "net_worth_snapshot".into(),
                output: json!({ "total": 42 }),
            },
            AgentEvent::Usage {
                input_tokens: 10,
                output_tokens: 20,
                cache_read_tokens: 3,
                cache_write_tokens: 4,
            },
            AgentEvent::Stop {
                reason: StopReason::EndTurn,
                rounds: 2,
            },
            AgentEvent::Error {
                code: "provider_error".into(),
                message: "upstream failed".into(),
            },
        ]));

        assert_eq!(
            frames,
            vec![
                ("text_delta".into(), json!({ "text": "hello" })),
                (
                    "thinking_delta".into(),
                    json!({ "text": "checking context" })
                ),
                (
                    "tool_call_start".into(),
                    json!({ "id": "toolu_1", "name": "net_worth_snapshot" })
                ),
                (
                    "tool_call_delta".into(),
                    json!({ "id": "toolu_1", "partial_input_json": "{\"range\"" })
                ),
                (
                    "tool_call_end".into(),
                    json!({ "id": "toolu_1", "input": { "range": "month" } })
                ),
                (
                    "tool_result".into(),
                    json!({
                        "id": "toolu_1",
                        "name": "net_worth_snapshot",
                        "output": { "total": 42 }
                    })
                ),
                (
                    "usage".into(),
                    json!({
                        "input": 10,
                        "output": 20,
                        "cache_read": 3,
                        "cache_write": 4
                    })
                ),
                ("stop".into(), json!({ "reason": "end_turn", "rounds": 2 })),
                (
                    "error".into(),
                    json!({ "code": "provider_error", "message": "upstream failed" })
                ),
            ]
        );
    }
}
