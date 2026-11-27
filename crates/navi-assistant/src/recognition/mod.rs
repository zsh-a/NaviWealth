//! One owner-initiated recognition turn through the pinned pi-rust providers.
//! No agent loop or tool execution. Structured results use pi's constrained
//! tools; the host validates them and keeps the ordinary confirmation boundary.
mod bridge;
mod types;
use crate::{CancellationToken, Config};
use rpi_ai::provider::SimpleStreamOptions;
use rpi_ai::types::StopReason;
use rpi_ai::{AssistantMessage, AssistantMessageEvent, Content, InputModality};
use serde_json::{Value, json};
pub use types::*;

pub const RESULT_TOOL: &str = "emit_result";
const MAX_RESPONSE_BYTES: usize = 100_000;
const MAX_REQUEST_BYTES: usize = 32_000_000;

/// Schema validation is always local, including when a compatible server
/// returns bare JSON instead of the requested result tool.
pub fn structured_output_from_content(
    format: &Option<LlmResponseFormat>,
    text: &str,
) -> Result<Option<Value>, LlmError> {
    if text.len() > MAX_RESPONSE_BYTES {
        return Err(LlmError::new("recognition_output_limit"));
    }
    let Some(format) = format else {
        return Ok(None);
    };
    let object: Value =
        serde_json::from_str(text).map_err(|_| LlmError::new("recognition_invalid_json"))?;
    if !object.is_object() {
        return Err(LlmError::new("recognition_invalid_json"));
    }
    if let LlmResponseFormat::JsonSchema { schema, .. } = format {
        let validator = jsonschema::JSONSchema::compile(schema)
            .map_err(|_| LlmError::new("recognition_invalid_schema"))?;
        if !validator.is_valid(&object) {
            return Err(LlmError::new("recognition_schema_mismatch"));
        }
    }
    Ok(Some(object))
}

struct CancelOnDrop(CancellationToken);
impl Drop for CancelOnDrop {
    fn drop(&mut self) {
        self.0.cancel();
    }
}

/// Requires a Tokio runtime. Dropping this future cancels the provider's
/// internally spawned network task. There are no retries or follow-up calls.
pub async fn complete(
    config: &Config,
    request: LlmRequest,
    cancel: CancellationToken,
    mut on_text: impl FnMut(String),
) -> Result<LlmResponse, LlmError> {
    if cancel.is_cancelled() {
        return Err(LlmError::new("recognition_cancelled"));
    }
    if request.model != config.model
        || serde_json::to_vec(&request)
            .map_err(|_| LlmError::new("recognition_invalid_request"))?
            .len()
            > MAX_REQUEST_BYTES
    {
        return Err(LlmError::new("recognition_invalid_request"));
    }
    let (mut model, provider) =
        crate::provider::build(config).map_err(|_| LlmError::new("recognition_configuration"))?;
    model.input = vec![InputModality::Text, InputModality::Image];
    if matches!(config.provider, crate::Provider::Anthropic) {
        model.compat = Some(rpi_ai::model::StreamingProtocolCompat::AnthropicMessages(
            rpi_ai::model::AnthropicMessagesCompat {
                supports_strict_tools: Some(true),
                ..Default::default()
            },
        ));
    }
    let context = bridge::context(&request, &model)?;
    let signal = cancel.child_token();
    let _guard = CancelOnDrop(signal.clone());
    let options = SimpleStreamOptions {
        signal: signal.clone(),
        timeout: Some(config.limits.timeout),
        stream_idle_timeout: Some(config.limits.timeout),
        max_retries: Some(0),
        max_tokens: Some(u64::from(request.max_output_tokens.unwrap_or(8000)).clamp(1, 16_384)),
        temperature: request.temperature.map(f64::from),
        ..Default::default()
    };
    let operation = async {
        let mut stream = provider.stream_simple(&model, &context, &options).await;
        // Never mix commentary and tool arguments into a single JSON preview.
        let mut channel: Option<usize> = None;
        let mut text_mode = false;
        while let Some(event) = stream.next().await {
            match event {
                AssistantMessageEvent::TextDelta { delta, partial, .. } => {
                    check_size(&partial)?;
                    if channel.is_none() {
                        text_mode = true;
                        on_text(delta);
                    }
                }
                AssistantMessageEvent::ToolCallDelta {
                    content_index,
                    delta,
                    partial,
                } => {
                    check_size(&partial)?;
                    if !text_mode
                        && partial.content.get(content_index).is_some_and(
                            |c| matches!(c,Content::ToolCall(t) if t.name==RESULT_TOOL),
                        )
                        && (channel.is_none() || channel == Some(content_index))
                    {
                        channel = Some(content_index);
                        on_text(delta);
                    }
                }
                AssistantMessageEvent::Done { message, .. } => return response(&request, message),
                AssistantMessageEvent::Error { error, .. } => return Err(classify_error(&error)),
                AssistantMessageEvent::Start { partial }
                | AssistantMessageEvent::ThinkingDelta { partial, .. }
                | AssistantMessageEvent::ToolCallEnd { partial, .. } => check_size(&partial)?,
                _ => {}
            }
        }
        Err(LlmError::new("provider_stream_incomplete"))
    };
    tokio::select! {
        biased;
        _=cancel.cancelled()=>Err(LlmError::new("recognition_cancelled")),
        result=tokio::time::timeout(config.limits.timeout,operation)=>result.unwrap_or_else(|_|Err(LlmError::new("recognition_timeout"))),
    }
}
fn check_size(message: &AssistantMessage) -> Result<(), LlmError> {
    if serde_json::to_vec(message)
        .map_err(|_| LlmError::new("recognition_invalid_response"))?
        .len()
        > MAX_RESPONSE_BYTES
    {
        Err(LlmError::new("recognition_output_limit"))
    } else {
        Ok(())
    }
}
fn response(request: &LlmRequest, message: AssistantMessage) -> Result<LlmResponse, LlmError> {
    check_size(&message)?;
    if message.raw_stop_reason.as_deref() == Some("refusal") {
        return Err(LlmError::new("provider_refusal"));
    }
    match message.stop_reason {
        StopReason::Length => return Err(LlmError::new("provider_stream_incomplete")),
        StopReason::Error | StopReason::Aborted => return Err(classify_error(&message)),
        StopReason::Stop | StopReason::ToolUse => {}
        _ => return Err(LlmError::new("recognition_invalid_response")),
    }
    let calls: Vec<_> = message
        .content
        .iter()
        .filter_map(|c| {
            if let Content::ToolCall(c) = c {
                Some(c)
            } else {
                None
            }
        })
        .collect();
    if message.api == rpi_ai::types::Api::OpenaiResponses
        && calls
            .iter()
            .any(|call| !bridge::replayable_responses_id(&call.id))
    {
        return Err(LlmError::new("recognition_unsupported_call_id"));
    }
    if calls.len() > 1
        || (calls.is_empty() && message.stop_reason == StopReason::ToolUse)
        || (!calls.is_empty() && message.stop_reason != StopReason::ToolUse)
    {
        return Err(LlmError::new("recognition_invalid_response"));
    }
    let (content, finish_reason, object) = if let Some(call) = calls.first() {
        if call.recorded.is_some() || call.namespace.is_some() || !call.arguments.is_object() {
            return Err(LlmError::new("recognition_invalid_response"));
        }
        if call.name == RESULT_TOOL && request.response_format.is_some() {
            let content = call.arguments.to_string();
            let object = structured_output_from_content(&request.response_format, &content)?;
            (content, LlmFinishReason::Stop, object)
        } else if let Some(spec) = request
            .tools
            .iter()
            .find(|t| t.name == call.name && t.name == "ask_user")
        {
            structured_output_from_content(
                &Some(LlmResponseFormat::JsonSchema {
                    name: spec.name.clone(),
                    schema: spec.input_schema.clone(),
                    strict: Some(true),
                }),
                &call.arguments.to_string(),
            )?;
            (
                Content::text_only(&message.content, ""),
                LlmFinishReason::ToolCall,
                None,
            )
        } else {
            return Err(LlmError::new("recognition_invalid_tool"));
        }
    } else {
        let content = Content::text_only(&message.content, "");
        let object = structured_output_from_content(&request.response_format, &content)?;
        (content, LlmFinishReason::Stop, object)
    };
    let mut saved = bridge::saved_blocks(&message);
    // emit_result is an internal output envelope, not an owner-facing tool.
    if finish_reason == LlmFinishReason::Stop {
        saved = json!([{"type":"text","text":content}]);
    }
    Ok(LlmResponse {
        protocol_version: PROTOCOL_VERSION.into(),
        provider: request.provider.clone(),
        model: message
            .response_model
            .clone()
            .unwrap_or_else(|| message.model.clone()),
        content,
        finish_reason,
        object,
        usage: Some(LlmUsage {
            input_tokens: message.usage.input.max(0) as u32,
            output_tokens: message.usage.output.max(0) as u32,
            total_tokens: message.usage.total_tokens.max(0) as u32,
        }),
        metadata: json!({"anthropic_content":saved,"responses_output":{"pi_message":message}}),
    })
}
fn classify_error(message: &AssistantMessage) -> LlmError {
    let raw = message
        .error_message
        .as_deref()
        .unwrap_or_default()
        .to_ascii_lowercase();
    let code = if message.stop_reason == StopReason::Aborted {
        "recognition_cancelled"
    } else if message.raw_stop_reason.as_deref() == Some("refusal")
        || raw.contains("content_filter")
    {
        "provider_refusal"
    } else if raw.contains("timeout") || raw.contains("timed out") {
        "recognition_timeout"
    } else if raw.contains("without finish")
        || raw.contains("without message_stop")
        || raw.contains("incomplete")
        || raw.contains("unexpected eof")
        || raw.contains("before terminal")
        || raw.contains("before a terminal")
    {
        "provider_stream_incomplete"
    } else if raw.contains("connect") || raw.contains("request") || raw.contains("network") {
        "provider_request_failed"
    } else {
        "provider_error"
    };
    let mut error = LlmError::new(code);
    if let Some(status) = raw
        .strip_prefix("http error ")
        .and_then(|text| text.split_once(':'))
        .and_then(|(status, _)| status.parse::<u16>().ok())
        .filter(|status| (400..600).contains(status))
    {
        error.record.details = json!({"status":status});
        error.record.code = "provider_http_error".into();
    }
    error
}

#[cfg(test)]
mod tests {
    use super::*;
    use rpi_ai::types::Api;

    #[test]
    fn local_schema_rejects_extra_fields_wrong_types_and_trailing_content() {
        let format = Some(LlmResponseFormat::JsonSchema {
            name: "draft".into(),
            strict: Some(true),
            schema: json!({"type":"object","additionalProperties":false,"required":["grams"],"properties":{"grams":{"type":"number","exclusiveMinimum":0}}}),
        });
        assert!(structured_output_from_content(&format, r#"{"grams":100}"#).is_ok());
        for text in [
            r#"{"grams":"100"}"#,
            r#"{"grams":0}"#,
            r#"{"grams":100,"write":true}"#,
            r#"{"grams":100} trailing"#,
            "{}",
            "[]",
        ] {
            assert!(
                structured_output_from_content(&format, text).is_err(),
                "{text}"
            );
        }
        assert!(
            structured_output_from_content(&format, &" ".repeat(MAX_RESPONSE_BYTES + 1)).is_err()
        );
    }

    #[test]
    fn classifications_use_status_prefix_and_never_retain_provider_text() {
        let message = |text: &str| {
            AssistantMessage::terminal(
                Api::OpenaiCompletions,
                "navi-owned",
                "model",
                StopReason::Error,
                text,
                0,
            )
        };
        let error = classify_error(&message("http error 401: credential contents 503"));
        assert_eq!(error.record.details, json!({"status":401}));
        assert_eq!(error.to_string(), "provider_http_error");
        assert_eq!(
            classify_error(&message("invalid result id 401"))
                .record
                .details,
            json!({})
        );
        assert_eq!(
            classify_error(&message(
                "OpenAI Responses stream ended before a terminal response event"
            ))
            .record
            .code,
            "provider_stream_incomplete"
        );
    }

    #[tokio::test]
    async fn precancelled_call_never_needs_a_provider() {
        let config = Config {
            provider: crate::Provider::Anthropic,
            base_url: "invalid".into(),
            api_key: String::new(),
            model: "model".into(),
            system_prompt: String::new(),
            limits: crate::Limits::default(),
            context_summary: None,
        };
        let request: LlmRequest = serde_json::from_value(json!({
            "protocol_version":"agent.v1", "provider":"anthropic", "model":"model", "messages":[],
        }))
        .unwrap();
        let cancel = CancellationToken::new();
        cancel.cancel();
        assert_eq!(
            complete(&config, request, cancel, |_| panic!("cancelled preview"))
                .await
                .unwrap_err()
                .record
                .code,
            "recognition_cancelled"
        );
    }
}
