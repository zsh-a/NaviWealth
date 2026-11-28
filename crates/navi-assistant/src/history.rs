use rpi_agent::AgentMessage;
use rpi_ai::types::{
    Content, Context, Message, StopReason, ToolCall, ToolResultMessage, ToolResultRole, UserContent,
};
use serde_json::Value;

/// Interrupted calls are closed as errors, never executed again merely because
/// a persisted session was loaded. A new user turn is always required.
pub(crate) fn decode(values: Vec<Value>) -> Result<Vec<AgentMessage>, String> {
    if values.len() > 4096
        || serde_json::to_vec(&values)
            .map_err(|_| "assistant_history")?
            .len()
            > 8_000_000
    {
        return Err("assistant_history_limit".into());
    }
    let mut messages = Vec::new();
    let mut pending: Vec<ToolCall> = Vec::new();
    for value in values {
        let mut message: AgentMessage =
            serde_json::from_value(value).map_err(|_| "assistant_history")?;
        match &message {
            AgentMessage::Custom(_) => return Err("assistant_history".into()),
            AgentMessage::ToolResult(result) => {
                let index = pending
                    .iter()
                    .position(|call| {
                        call.id == result.tool_call_id && call.name == result.tool_name
                    })
                    .ok_or("assistant_history")?;
                pending.remove(index);
            }
            _ => close_pending(&mut messages, &mut pending),
        }
        sanitize(&mut message);
        if let AgentMessage::Assistant(assistant) = &message {
            pending = assistant
                .content
                .iter()
                .filter_map(|item| match item {
                    Content::ToolCall(call) => Some(call.clone()),
                    _ => None,
                })
                .collect();
        }
        messages.push(message);
    }
    close_pending(&mut messages, &mut pending);
    Ok(messages)
}

pub const INTERRUPTED_TOOL_RESULT: &str = "Interrupted. The outcome is unknown. Check existing drafts and data before proposing the action again; do not automatically repeat a write.";

fn close_pending(messages: &mut Vec<AgentMessage>, pending: &mut Vec<ToolCall>) {
    for call in pending.drain(..) {
        messages.push(AgentMessage::from(ToolResultMessage {
            role: ToolResultRole,
            tool_call_id: call.id,
            tool_name: call.name,
            content: vec![Content::text(INTERRUPTED_TOOL_RESULT)],
            details: None,
            usage: None,
            added_tool_names: Vec::new(),
            is_error: true,
            timestamp: 0,
        }));
    }
}

pub(crate) const OMITTED_IMAGE: &str = "[Image attached to this turn is stored on the device and omitted from saved model history. Do not claim to inspect it unless the host reattaches it to the current request.]";

fn redact_images(blocks: &mut [Content]) {
    for block in blocks {
        if matches!(block, Content::Image(_)) {
            *block = Content::text(OMITTED_IMAGE);
        }
    }
}

pub(crate) fn sanitize(message: &mut AgentMessage) {
    match message {
        AgentMessage::User(user) => {
            if let UserContent::Blocks(blocks) = &mut user.content {
                redact_images(blocks);
            }
        }
        AgentMessage::Assistant(assistant) => redact_images(&mut assistant.content),
        AgentMessage::ToolResult(result) => redact_images(&mut result.content),
        AgentMessage::Custom(_) => {}
    }

    if let AgentMessage::Assistant(assistant) = message
        && matches!(
            assistant.stop_reason,
            StopReason::Error | StopReason::Aborted
        )
    {
        // Upstream diagnostics can contain a provider response body. Store only
        // a stable code, even if the caller logs serialized checkpoints.
        assistant.error_message =
            Some(crate::diagnostics::sanitize(assistant.error_message.as_deref()).into());
        assistant.raw_stop_reason = None;
        assistant.content.clear();
    }
}

pub(crate) fn encode(messages: &[AgentMessage]) -> Vec<Value> {
    messages
        .iter()
        .filter_map(|message| {
            let mut message = message.clone();
            sanitize(&mut message);
            serde_json::to_value(message).ok()
        })
        .collect()
}

/// The text-context budget is independent of this turn's bounded image bytes.
/// Images are checked separately at the request boundary, never silently dropped
/// merely to make a text budget fit.
pub(crate) fn context_size(context: &Context) -> Result<usize, String> {
    let mut text = context.clone();
    for message in &mut text.messages {
        match message {
            Message::User(user) => {
                if let UserContent::Blocks(blocks) = &mut user.content {
                    redact_images(blocks);
                }
            }
            Message::Assistant(assistant) => redact_images(&mut assistant.content),
            Message::ToolResult(result) => redact_images(&mut result.content),
        }
    }
    Ok(serde_json::to_vec(&text)
        .map_err(|_| "assistant_context_limit")?
        .len())
}

/// Shrink only the provider window. Never split a user turn, which would
/// orphan tool calls or erase their results while retaining the instructions.
pub(crate) fn bound_context(context: &mut Context, limit: usize) -> Result<usize, String> {
    context.messages.retain(|message| !matches!(message,
        Message::Assistant(assistant) if matches!(assistant.stop_reason, StopReason::Error | StopReason::Aborted)
    ));
    let mut removed = 0;
    while context_size(context)? > limit {
        let next = context
            .messages
            .iter()
            .enumerate()
            .skip(1)
            .find_map(|(i, message)| matches!(message, Message::User(_)).then_some(i));
        let Some(next) = next else {
            return Err("assistant_context_limit".into());
        };
        context.messages.drain(..next);
        removed += next;
    }
    Ok(removed)
}
