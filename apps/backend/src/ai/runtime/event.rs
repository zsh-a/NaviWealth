//! Provider-neutral event stream emitted by agent runtimes.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum AgentEvent {
    TextDelta {
        text: String,
    },
    ThinkingDelta {
        text: String,
    },
    ToolCallStart {
        id: String,
        name: String,
    },
    ToolCallDelta {
        id: String,
        partial_input_json: String,
    },
    ToolCallEnd {
        id: String,
        input: serde_json::Value,
    },
    ToolResult {
        id: String,
        name: String,
        output: serde_json::Value,
    },
    Usage {
        input_tokens: u32,
        output_tokens: u32,
        cache_read_tokens: u32,
        cache_write_tokens: u32,
    },
    Stop {
        reason: StopReason,
    },
    Error {
        code: String,
        message: String,
    },
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum StopReason {
    EndTurn,
    MaxTokens,
    ToolUse,
    Refusal,
    Error,
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn agent_event_round_trips_through_json() {
        let events = vec![
            AgentEvent::TextDelta {
                text: "hello".into(),
            },
            AgentEvent::ThinkingDelta {
                text: "checking context".into(),
            },
            AgentEvent::ToolCallStart {
                id: "tool-1".into(),
                name: "net_worth_snapshot".into(),
            },
            AgentEvent::ToolCallDelta {
                id: "tool-1".into(),
                partial_input_json: "{\"range\"".into(),
            },
            AgentEvent::ToolCallEnd {
                id: "tool-1".into(),
                input: json!({ "range": "month" }),
            },
            AgentEvent::ToolResult {
                id: "tool-1".into(),
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
            },
            AgentEvent::Error {
                code: "provider_error".into(),
                message: "upstream failed".into(),
            },
        ];

        for event in events {
            let encoded = serde_json::to_string(&event).expect("serialize agent event");
            let decoded: AgentEvent =
                serde_json::from_str(&encoded).expect("deserialize agent event");
            assert_eq!(decoded, event);
        }
    }

    #[test]
    fn agent_event_uses_snake_case_type_tag() {
        let encoded = serde_json::to_value(AgentEvent::Stop {
            reason: StopReason::MaxTokens,
        })
        .expect("serialize stop event");

        assert_eq!(
            encoded,
            json!({
                "type": "stop",
                "reason": "max_tokens"
            })
        );
    }
}
