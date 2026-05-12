//! v1-compatible SSE sink for provider-neutral agent events.

use std::collections::BTreeMap;

use futures_channel::mpsc;
use serde_json::{json, Value};

use crate::ai::runtime::{AgentEvent, EventSink, StopReason};
use crate::ai::sse::encode_event;
use crate::error::AppError;

pub struct SseEventSink {
    tx: mpsc::UnboundedSender<Result<Vec<u8>, worker::Error>>,
    text: String,
    tool_names: BTreeMap<String, String>,
}

impl SseEventSink {
    pub fn new(tx: mpsc::UnboundedSender<Result<Vec<u8>, worker::Error>>) -> Self {
        Self {
            tx,
            text: String::new(),
            tool_names: BTreeMap::new(),
        }
    }

    fn flush_text(&mut self) {
        if self.text.is_empty() {
            return;
        }
        let text = std::mem::take(&mut self.text);
        self.send("text", &json!({ "text": text }));
    }

    fn send(&self, name: &str, payload: &Value) {
        let body = serde_json::to_string(payload).unwrap_or_else(|_| "{}".into());
        let _ = self.tx.unbounded_send(Ok(encode_event(name, &body)));
    }
}

impl EventSink for SseEventSink {
    fn emit(&mut self, event: AgentEvent) -> Result<(), AppError> {
        match event {
            AgentEvent::TextDelta { text } => self.text.push_str(&text),
            AgentEvent::ThinkingDelta { .. }
            | AgentEvent::ToolCallDelta { .. }
            | AgentEvent::Usage { .. } => {}
            AgentEvent::ToolCallStart { id, name } => {
                self.tool_names.insert(id, name);
            }
            AgentEvent::ToolCallEnd { id, input } => {
                self.flush_text();
                let name = self.tool_names.remove(&id).unwrap_or_default();
                self.send(
                    "tool_call",
                    &json!({ "id": id, "name": name, "input": input }),
                );
            }
            AgentEvent::ToolResult { id, name, output } => {
                self.flush_text();
                self.send(
                    "tool_result",
                    &json!({ "id": id, "name": name, "output": output }),
                );
            }
            AgentEvent::Error { code, message } => {
                self.flush_text();
                self.send("error", &json!({ "message": message, "code": code }));
            }
            AgentEvent::Stop { reason, rounds } => {
                self.flush_text();
                self.send(
                    "done",
                    &json!({ "stop_reason": stop_reason_wire(reason), "rounds": rounds }),
                );
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
            let mut sink = SseEventSink::new(tx);
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
    fn accumulates_text_delta_into_single_v1_text_event() {
        let frames = futures_executor::block_on(collect_frames([
            AgentEvent::TextDelta { text: "你".into() },
            AgentEvent::TextDelta { text: "好".into() },
            AgentEvent::Stop {
                reason: StopReason::EndTurn,
                rounds: 1,
            },
        ]));

        assert_eq!(frames[0], ("text".into(), json!({ "text": "你好" })));
        assert_eq!(
            frames[1],
            (
                "done".into(),
                json!({ "stop_reason": "end_turn", "rounds": 1 })
            )
        );
    }

    #[test]
    fn maps_tool_events_to_legacy_payloads() {
        let frames = futures_executor::block_on(collect_frames([
            AgentEvent::ToolCallStart {
                id: "toolu_1".into(),
                name: "get_risk_alerts".into(),
            },
            AgentEvent::ToolCallEnd {
                id: "toolu_1".into(),
                input: json!({ "as_of": "2026-05-07" }),
            },
            AgentEvent::ToolResult {
                id: "toolu_1".into(),
                name: "get_risk_alerts".into(),
                output: json!({ "alerts": [] }),
            },
            AgentEvent::Stop {
                reason: StopReason::ToolUse,
                rounds: 3,
            },
        ]));

        assert_eq!(
            frames,
            vec![
                (
                    "tool_call".into(),
                    json!({
                        "id": "toolu_1",
                        "name": "get_risk_alerts",
                        "input": { "as_of": "2026-05-07" }
                    })
                ),
                (
                    "tool_result".into(),
                    json!({
                        "id": "toolu_1",
                        "name": "get_risk_alerts",
                        "output": { "alerts": [] }
                    })
                ),
                (
                    "done".into(),
                    json!({ "stop_reason": "tool_use", "rounds": 3 })
                ),
            ]
        );
    }
}
