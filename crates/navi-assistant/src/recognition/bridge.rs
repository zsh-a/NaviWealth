use super::*;
use base64::{Engine, engine::general_purpose::STANDARD};
use rpi_ai::types::{
    AssistantMessage, ConstrainedSamplingConfig, ConstrainedStrictness, ImageContent,
    ImageContentType, Schema, StopReason, ThinkingContent, ThinkingContentType, ToolResultMessage,
    ToolResultRole,
};
use rpi_ai::{Content, Context, Message, Model, Tool, UserMessage};

fn block(value: &ContentBlock) -> Result<Content, LlmError> {
    value.validate()?;
    Ok(match value {
        ContentBlock::Text { text } => Content::text(text),
        ContentBlock::Image {
            source: ImageSource::Base64 { media_type, data },
        } => Content::Image(ImageContent {
            kind: ImageContentType,
            data: STANDARD.encode(data).into(),
            mime_type: media_type.clone(),
        }),
        ContentBlock::ToolUse { id, name, input } => Content::tool_call(id, name, input.clone()),
        ContentBlock::Thinking {
            thinking,
            signature,
        } => Content::Thinking(ThinkingContent {
            kind: ThinkingContentType,
            thinking: thinking.clone(),
            thinking_signature: (!signature.is_empty()).then(|| signature.clone()),
            redacted: false,
        }),
        ContentBlock::RedactedThinking { data } => Content::Thinking(ThinkingContent {
            kind: ThinkingContentType,
            thinking: String::new(),
            thinking_signature: Some(data.clone()),
            redacted: true,
        }),
        ContentBlock::ToolResult { .. } => {
            return Err(LlmError::new("recognition_invalid_content"));
        }
    })
}
fn blocks(value: &MessageContent) -> Vec<ContentBlock> {
    match value {
        MessageContent::Text(text) => vec![ContentBlock::Text { text: text.clone() }],
        MessageContent::Blocks(v) => v.clone(),
    }
}
fn tool_result(id: &str, name: &str, text: String, is_error: bool) -> Message {
    ToolResultMessage {
        role: ToolResultRole,
        tool_call_id: id.into(),
        tool_name: name.into(),
        content: vec![Content::text(text)],
        details: None,
        usage: None,
        added_tool_names: vec![],
        is_error,
        timestamp: 0,
    }
    .into()
}
fn native_assistant(message: &LlmMessage, model: &Model) -> Result<AssistantMessage, LlmError> {
    if let Some(value) = message.metadata.pointer("/responses_output/pi_message") {
        let native: AssistantMessage = serde_json::from_value(value.clone())
            .map_err(|_| LlmError::new("recognition_invalid_history"))?;
        validate_native(message, &native)?;
        return Ok(native);
    }
    let mut native = AssistantMessage::empty(model.api.clone(), &model.provider, &model.id, 0);
    native.content = blocks(&message.content)
        .iter()
        .map(block)
        .collect::<Result<_, _>>()?;
    // Old captures persisted the Responses output array. Convert its opaque
    // reasoning and message/function IDs into pi's supported replay signatures.
    if let Some(items) = message
        .metadata
        .get("responses_output")
        .and_then(Value::as_array)
    {
        let mut converted = Vec::new();
        for item in items {
            match item["type"].as_str() {
                Some("reasoning") => converted.push(Content::Thinking(ThinkingContent {
                    kind: ThinkingContentType,
                    thinking: String::new(),
                    thinking_signature: Some(item.to_string()),
                    redacted: false,
                })),
                Some("message") => {
                    if let Some(content) = item["content"].as_array() {
                        for part in content {
                            if let Some(text) = part["text"].as_str() {
                                let mut content = Content::text(text);
                                if let Content::Text(t) = &mut content {
                                    t.text_signature = item["id"].as_str().map(|id| {
                                        json!({"v":1,"id":id,"phase":item.get("phase").cloned().unwrap_or(Value::Null)}).to_string()
                                    });
                                }
                                converted.push(content);
                            }
                        }
                    }
                }
                Some("function_call") => {
                    let call = item["call_id"]
                        .as_str()
                        .ok_or_else(|| LlmError::new("recognition_invalid_history"))?;
                    let id = item["id"]
                        .as_str()
                        .map_or_else(|| call.to_owned(), |id| format!("{call}|{id}"));
                    let name = item["name"]
                        .as_str()
                        .ok_or_else(|| LlmError::new("recognition_invalid_history"))?;
                    let args = item["arguments"]
                        .as_str()
                        .ok_or_else(|| LlmError::new("recognition_invalid_history"))?;
                    converted.push(Content::tool_call(
                        id,
                        name,
                        serde_json::from_str(args)
                            .map_err(|_| LlmError::new("recognition_invalid_history"))?,
                    ));
                }
                _ => return Err(LlmError::new("recognition_invalid_history")),
            }
        }
        if !converted.is_empty() {
            native.content = converted;
        }
    }
    native.stop_reason = if native
        .content
        .iter()
        .any(|b| matches!(b, Content::ToolCall(_)))
    {
        StopReason::ToolUse
    } else {
        StopReason::Stop
    };
    validate_native(message, &native)?;
    Ok(native)
}

fn validate_native(message: &LlmMessage, native: &AssistantMessage) -> Result<(), LlmError> {
    let invalid = || LlmError::new("recognition_invalid_history");
    let calls: Vec<_> = native
        .content
        .iter()
        .filter_map(|block| {
            if let Content::ToolCall(call) = block {
                Some(call)
            } else {
                None
            }
        })
        .collect();
    if calls.len() > 1
        || !matches!(native.stop_reason, StopReason::Stop | StopReason::ToolUse)
        || (calls.is_empty() != (native.stop_reason == StopReason::Stop))
    {
        return Err(invalid());
    }
    if native.api == rpi_ai::types::Api::OpenaiResponses
        && calls.iter().any(|call| !replayable_responses_id(&call.id))
    {
        return Err(invalid());
    }
    let stored = blocks(&message.content);
    let stored_calls: Vec<_> = stored
        .iter()
        .filter_map(|block| {
            if let ContentBlock::ToolUse { id, name, input } = block {
                Some((id, name, input))
            } else {
                None
            }
        })
        .collect();
    if let Some(call) = calls.first() {
        if call.recorded.is_some()
            || call.namespace.is_some()
            || call.id.is_empty()
            || !call.arguments.is_object()
        {
            return Err(invalid());
        }
        if call.name == RESULT_TOOL {
            let text = message.content.as_str().ok_or_else(invalid)?;
            let value: Value = serde_json::from_str(text).map_err(|_| invalid())?;
            if !stored_calls.is_empty() || value != call.arguments {
                return Err(invalid());
            }
        } else if call.name == "ask_user" {
            let [(id, name, input)] = stored_calls.as_slice() else {
                return Err(invalid());
            };
            if call_key(id) != call_key(&call.id)
                || *name != &call.name
                || *input != &call.arguments
            {
                return Err(invalid());
            }
        } else {
            return Err(invalid());
        }
    } else {
        if !stored_calls.is_empty() {
            return Err(invalid());
        }
        let stored_text = stored
            .iter()
            .filter_map(|block| {
                if let ContentBlock::Text { text } = block {
                    Some(text.as_str())
                } else {
                    None
                }
            })
            .collect::<String>();
        let native_text = Content::text_only(&native.content, "");
        if native_text != stored_text
            && !(serde_json::from_str::<Value>(&native_text)
                .ok()
                .zip(serde_json::from_str::<Value>(&stored_text).ok())
                .is_some_and(|(a, b)| a == b))
        {
            return Err(invalid());
        }
    }
    Ok(())
}
pub(super) fn context(request: &LlmRequest, model: &Model) -> Result<Context, LlmError> {
    let mut context = Context::default();
    let mut pending = std::collections::HashMap::<String, (String, String)>::new();
    let mut seen = std::collections::HashSet::new();
    for (index, message) in request.messages.iter().enumerate() {
        match message.role {
            LlmRole::System => {
                if index != 0 {
                    return Err(LlmError::new("recognition_invalid_history"));
                }
                let text = message
                    .content
                    .as_str()
                    .ok_or_else(|| LlmError::new("recognition_invalid_history"))?;
                context.system_prompt.get_or_insert_default().push_str(text);
            }
            LlmRole::Assistant => {
                if !pending.is_empty() {
                    return Err(LlmError::new("recognition_unanswered_tool"));
                }
                let native = native_assistant(message, model)?;
                let mut acknowledgements = Vec::new();
                for content in &native.content {
                    if let Content::ToolCall(call) = content {
                        if !seen.insert(call_key(&call.id).to_owned()) {
                            return Err(LlmError::new("recognition_invalid_history"));
                        }
                        if call.name == RESULT_TOOL {
                            acknowledgements.push(tool_result(
                                &call.id,
                                RESULT_TOOL,
                                "Draft presented for owner review; no records were written.".into(),
                                false,
                            ));
                        } else if call.name == "ask_user" {
                            pending.insert(
                                call_key(&call.id).into(),
                                (call.id.clone(), call.name.clone()),
                            );
                        } else {
                            return Err(LlmError::new("recognition_invalid_history"));
                        }
                    }
                }
                context.messages.push(native.into());
                context.messages.extend(acknowledgements);
            }
            LlmRole::User | LlmRole::Tool => {
                let mut user = Vec::new();
                for content in blocks(&message.content) {
                    if let ContentBlock::ToolResult {
                        tool_use_id,
                        content,
                        is_error,
                    } = content
                    {
                        if !user.is_empty() {
                            context.messages.push(
                                UserMessage::new(
                                    rpi_ai::types::UserContent::Blocks(std::mem::take(&mut user)),
                                    0,
                                )
                                .into(),
                            );
                        }
                        let key = call_key(&tool_use_id);
                        let (id, name) = pending
                            .remove(key)
                            .ok_or_else(|| LlmError::new("recognition_invalid_history"))?;
                        context.messages.push(tool_result(
                            &id,
                            &name,
                            content
                                .as_str()
                                .map(str::to_owned)
                                .unwrap_or_else(|| content.to_string()),
                            is_error.unwrap_or(false),
                        ));
                    } else {
                        if !pending.is_empty()
                            || matches!(
                                content,
                                ContentBlock::ToolUse { .. }
                                    | ContentBlock::Thinking { .. }
                                    | ContentBlock::RedactedThinking { .. }
                            )
                        {
                            return Err(LlmError::new("recognition_invalid_history"));
                        }
                        user.push(block(&content)?);
                    }
                }
                if !user.is_empty() {
                    context
                        .messages
                        .push(UserMessage::new(rpi_ai::types::UserContent::Blocks(user), 0).into());
                }
            }
        }
    }
    if !pending.is_empty() {
        return Err(LlmError::new("recognition_unanswered_tool"));
    }
    for spec in &request.tools {
        if spec.name != "ask_user" {
            return Err(LlmError::new("recognition_invalid_tool"));
        }
        context.tools.push(tool(
            &spec.name,
            &spec.description,
            spec.input_schema.clone(),
        ));
    }
    if let Some(format) = &request.response_format {
        let schema = match format {
            LlmResponseFormat::JsonSchema { schema, .. } => schema.clone(),
            LlmResponseFormat::JsonObject => json!({"type":"object"}),
        };
        context.tools.push(tool(
            RESULT_TOOL,
            "Return the final structured estimate or capture draft for owner review. \
             This only returns data and never writes records.",
            schema,
        ));
        context.system_prompt.get_or_insert_default().push_str(
            "\nReturn your final structured result using emit_result, or ask_user when \
             owner clarification is needed. Never call both. Exactly one tool call per \
             response. No tool executes a business write.",
        );
    }
    Ok(context)
}
fn tool(name: &str, description: &str, parameters: Value) -> Tool {
    Tool {
        name: name.into(),
        description: description.into(),
        parameters: Schema::new(parameters),
        constrained_sampling: Some(ConstrainedSamplingConfig::JsonSchema {
            strict: ConstrainedStrictness::Prefer,
        }),
    }
}
pub(super) fn saved_blocks(message: &AssistantMessage) -> Value {
    Value::Array(message.content.iter().filter_map(|content| match content {
        Content::Text(text) => Some(json!({"type":"text", "text":text.text})),
        Content::Thinking(thinking) if thinking.redacted => Some(json!({
            "type":"redacted_thinking", "data":thinking.thinking_signature.clone().unwrap_or_default(),
        })),
        Content::Thinking(thinking) => Some(json!({
            "type":"thinking", "thinking":thinking.thinking,
            "signature":thinking.thinking_signature.clone().unwrap_or_default(),
        })),
        Content::ToolCall(call) => Some(json!({
            "type":"tool_use", "id": if message.api == rpi_ai::types::Api::OpenaiResponses { call_key(&call.id) } else { &call.id }, "name":call.name, "input":call.arguments,
        })),
        Content::Image(_) => None,
    }).collect())
}

/// pi-rust normalizes foreign/opaque IDs. Recognition resumes the same owner
/// interaction, so fail closed if native Responses IDs would change on replay.
pub(super) fn replayable_responses_id(id: &str) -> bool {
    fn safe(part: &str) -> bool {
        !part.is_empty()
            && part.len() <= 64
            && !part.ends_with('_')
            && part
                .bytes()
                .all(|c| c.is_ascii_alphanumeric() || matches!(c, b'_' | b'-'))
    }
    match id.split_once('|') {
        Some((call, item)) => {
            call.starts_with("call_") && item.starts_with("fc_") && safe(call) && safe(item)
        }
        None => safe(id),
    }
}
fn call_key(id: &str) -> &str {
    if replayable_responses_id(id) {
        id.split('|').next().unwrap_or(id)
    } else {
        id
    }
}
