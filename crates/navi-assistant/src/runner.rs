use std::sync::{
    Arc,
    atomic::{AtomicBool, AtomicUsize, Ordering},
};

use async_trait::async_trait;
use base64::{Engine, engine::general_purpose::STANDARD};
use rpi_agent::{
    AgentBuilder, AgentError, AgentEvent, AgentMessage, AgentTool, AgentToolResult,
    ToolExecutionMode, ToolResultPartial,
};
use rpi_ai::{
    Model, Provider as PiProvider,
    event_stream::create_assistant_message_event_stream_with_cancellation,
    types::{
        AssistantMessage, AssistantMessageEvent, Content, ErrorReason, ImageContent, StopReason,
        Tool, UserContent, UserMessage,
    },
};
use serde_json::Value;

use crate::{
    CancellationToken, Config, ContextSummary, Event, EventHandler, ImageInput, Limits, RunResult,
    ToolHandler, ToolSpec, compaction, diagnostics, history, provider,
};

struct HostTool {
    schema: Tool,
    handler: ToolHandler,
    terminal: bool,
}

#[async_trait]
impl AgentTool for HostTool {
    fn schema(&self) -> &Tool {
        &self.schema
    }
    fn label(&self) -> &str {
        &self.schema.name
    }
    fn execution_mode(&self) -> ToolExecutionMode {
        ToolExecutionMode::Sequential
    }
    async fn execute(
        &self,
        _: &str,
        params: Value,
        signal: CancellationToken,
        _: Arc<dyn Fn(ToolResultPartial) + Send + Sync>,
    ) -> Result<AgentToolResult, AgentError> {
        let result = tokio::select! {
            biased;
            _ = signal.cancelled() => return Err(AgentError::Abort),
            result = (self.handler)(self.schema.name.clone(), params) => result,
        };
        let result = result.map_err(|error| AgentError::tool(safe_tool_error(&error)))?;
        let text =
            serde_json::to_string(&result).map_err(|_| AgentError::tool("assistant_tool"))?;
        if text.len() > 64_000 {
            return Err(AgentError::tool("assistant_tool_result_limit"));
        }
        let mut result = AgentToolResult::text(text);
        result.terminate = self.terminal;
        Ok(result)
    }
}

fn safe_tool_error(error: &str) -> &str {
    if !error.is_empty()
        && error.len() <= 96
        && error
            .bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'_')
    {
        error
    } else {
        "assistant_tool"
    }
}

/// Run one owner-submitted turn. Safe error codes are deliberately terse so a
/// mobile host can localize them without rendering upstream diagnostics.
pub async fn run(
    config: Config,
    history: Vec<Value>,
    prompt: String,
    tools: Vec<ToolSpec>,
    handler: ToolHandler,
    events: EventHandler,
    cancel: CancellationToken,
) -> Result<RunResult, String> {
    let (model, provider) = provider::build(&config)?;
    execute_with_summary(
        model,
        provider,
        config.system_prompt,
        config.limits,
        config.context_summary,
        history,
        prompt,
        tools,
        handler,
        events,
        cancel,
    )
    .await
}

/// Run a unified conversation turn with up to four prepared images. The host
/// persists attachment references; every emitted checkpoint omits image bytes.
/// Successful record proposals and clarification-only batches end this run and
/// wait for the next explicit owner action, without a redundant model request.
#[allow(clippy::too_many_arguments)]
pub async fn run_multimodal(
    config: Config,
    history: Vec<Value>,
    prompt: String,
    images: Vec<ImageInput>,
    tools: Vec<ToolSpec>,
    handler: ToolHandler,
    events: EventHandler,
    cancel: CancellationToken,
) -> Result<RunResult, String> {
    if images.len() > 4
        || images.iter().any(|image| {
            image.data.is_empty()
                || image.data.len() > 2 * 1024 * 1024
                || !matches!(
                    image.mime_type.as_str(),
                    "image/jpeg" | "image/png" | "image/webp" | "image/gif"
                )
        })
    {
        return Err("assistant_image_limit".into());
    }
    let (mut model, provider) = provider::build(&config)?;
    model.input = vec![rpi_ai::InputModality::Text, rpi_ai::InputModality::Image];
    let prompt = if images.is_empty() {
        UserMessage::new(prompt, 0)
    } else {
        let mut content = Vec::new();
        if !prompt.trim().is_empty() {
            content.push(Content::text(prompt));
        }
        content.extend(images.into_iter().map(|image| {
            Content::Image(ImageContent {
                kind: Default::default(),
                data: STANDARD.encode(image.data).into(),
                mime_type: image.mime_type,
            })
        }));
        UserMessage::new(UserContent::Blocks(content), 0)
    };
    execute_input(
        model,
        provider,
        config.system_prompt,
        config.limits,
        config.context_summary,
        history,
        prompt,
        tools,
        handler,
        events,
        cancel,
        true,
    )
    .await
}

#[allow(clippy::too_many_arguments)]
async fn execute_with_summary(
    model: Model,
    provider: Arc<dyn PiProvider>,
    system_prompt: String,
    limits: Limits,
    context_summary: Option<ContextSummary>,
    values: Vec<Value>,
    prompt: String,
    tools: Vec<ToolSpec>,
    handler: ToolHandler,
    events: EventHandler,
    cancel: CancellationToken,
) -> Result<RunResult, String> {
    execute_input(
        model,
        provider,
        system_prompt,
        limits,
        context_summary,
        values,
        UserMessage::new(prompt, 0),
        tools,
        handler,
        events,
        cancel,
        false,
    )
    .await
}

#[allow(clippy::too_many_arguments)]
async fn execute_input(
    model: Model,
    provider: Arc<dyn PiProvider>,
    system_prompt: String,
    limits: Limits,
    context_summary: Option<ContextSummary>,
    values: Vec<Value>,
    prompt: UserMessage,
    tools: Vec<ToolSpec>,
    handler: ToolHandler,
    events: EventHandler,
    cancel: CancellationToken,
    terminal_tools: bool,
) -> Result<RunResult, String> {
    if cancel.is_cancelled() {
        return Err("assistant_cancelled".into());
    }
    let (text, has_images) = match &prompt.content {
        UserContent::Text(text) => (text.clone(), false),
        UserContent::Blocks(blocks) => (
            Content::text_only(blocks, ""),
            blocks
                .iter()
                .any(|block| matches!(block, Content::Image(_))),
        ),
    };
    if (!has_images && text.trim().is_empty())
        || text.len() > 32_000
        || text.chars().count() > 8_000
    {
        return Err("assistant_prompt_limit".into());
    }
    if tools.len() > 32
        || limits.max_turns == 0
        || limits.max_turns > 32
        || limits.timeout.is_zero()
        || limits.timeout.as_secs() > 600
        || limits.context_chars < 1024
        || limits.context_chars > 1_000_000
    {
        return Err("assistant_configuration".into());
    }
    if let Some(summary) = &context_summary {
        crate::validate_context_summary(summary, &values)?;
    }
    let deadline_at = tokio::time::Instant::now() + limits.timeout;
    let mut transcript = history::decode(values)?;
    let tool_impls: Vec<Arc<dyn AgentTool>> = tools
        .into_iter()
        .map(|spec| {
            Arc::new(HostTool {
                terminal: terminal_tools
                    && matches!(
                        spec.name.as_str(),
                        "propose_record" | "revise_record" | "ask_user"
                    ),
                schema: Tool {
                    name: spec.name,
                    description: spec.description,
                    parameters: rpi_ai::types::Schema::new(spec.parameters),
                    constrained_sampling: None,
                },
                handler: handler.clone(),
            }) as Arc<dyn AgentTool>
        })
        .collect();
    let schemas: Vec<_> = tool_impls
        .iter()
        .map(|tool| tool.schema().clone())
        .collect();
    // A cancelled preparation still records the newly submitted owner turn.
    let mut initial = transcript.clone();
    initial.push(prompt.clone().into());
    events(Event::Checkpoint(history::encode(&initial)));
    let preparation_cancel = cancel.child_token();
    let preparation = compaction::prepare(
        &model,
        provider.clone(),
        &system_prompt,
        &limits,
        &transcript,
        &prompt,
        &schemas,
        context_summary,
        &events,
        &preparation_cancel,
    );
    let (context_summary, summary_calls) = tokio::select! {
        biased;
        _ = cancel.cancelled() => return Err("assistant_cancelled".into()),
        _ = tokio::time::sleep_until(deadline_at) => {
            preparation_cancel.cancel();
            return Err("assistant_timeout".into());
        }
        result = preparation => result?,
    };
    let failure = Arc::new(AtomicUsize::new(0));
    let stream = bounded_stream(
        provider,
        limits.clone(),
        events.clone(),
        failure.clone(),
        context_summary.clone(),
        summary_calls,
    );
    let agent = AgentBuilder::new()
        .model(model)
        .system_prompt(system_prompt)
        .messages(transcript.clone())
        .tools(tool_impls)
        .tool_execution(ToolExecutionMode::Sequential)
        .stream_fn(stream)
        .build()
        .map_err(|_| "assistant_configuration")?;
    let mut receiver = agent.subscribe();
    // Abort is a no-op upstream until prompt's first poll installs its active
    // run. A stop/deadline between preparation and that poll must return directly.
    let started = AtomicBool::new(false);
    let prompt = async {
        // Check the actual clock as well as the timer: a synchronous host
        // callback can pass the deadline before the timer driver next polls.
        if cancel.is_cancelled() || tokio::time::Instant::now() >= deadline_at {
            return Err(AgentError::Abort);
        }
        started.store(true, Ordering::Relaxed);
        agent.prompt_message(prompt.into()).await
    };
    tokio::pin!(prompt);
    let deadline = tokio::time::sleep_until(deadline_at);
    tokio::pin!(deadline);
    let mut interrupted = None;
    let result = loop {
        tokio::select! {
            biased;
            _ = cancel.cancelled(), if interrupted.is_none() => {
                if !started.load(Ordering::Relaxed) {
                    return Err("assistant_cancelled".into());
                }
                interrupted = Some("assistant_cancelled");
                agent.abort();
            }
            _ = &mut deadline, if interrupted.is_none() => {
                if !started.load(Ordering::Relaxed) {
                    return Err("assistant_timeout".into());
                }
                interrupted = Some("assistant_timeout");
                agent.abort();
            }
            result = &mut prompt => break result,
            event = receiver.recv() => match event {
                Ok(event) => observe(event, &mut transcript, &events),
                Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => {
                    interrupted = Some("assistant_stream");
                    agent.abort();
                }
                Err(tokio::sync::broadcast::error::RecvError::Closed) => break Err(AgentError::State("closed".into())),
            }
        }
    };
    if !started.load(Ordering::Relaxed) {
        return Err(if cancel.is_cancelled() {
            "assistant_cancelled"
        } else {
            "assistant_timeout"
        }
        .into());
    }
    while let Ok(event) = receiver.try_recv() {
        observe(event, &mut transcript, &events);
    }
    // The authoritative state also covers event-buffer loss. Repair unfinished
    // calls before persisting the terminal checkpoint; no tool is replayed.
    let history = history::encode(&agent.state().messages);
    let history = history::encode(&history::decode(history)?);
    events(Event::Checkpoint(history.clone()));
    if let Some(reason) = interrupted {
        return Err(reason.into());
    }
    match failure.load(Ordering::Relaxed) {
        1 => return Err("assistant_step_limit".into()),
        2 => return Err("assistant_context_limit".into()),
        3 => return Err("assistant_output_limit".into()),
        code => {
            if let Some(code) = diagnostics::from_index(code) {
                return Err(code.into());
            }
        }
    }
    result.map_err(|_| "assistant_provider")?;
    let state = agent.state();
    let last = state
        .messages
        .iter()
        .rev()
        .find_map(AgentMessage::as_assistant)
        .ok_or("assistant_provider")?;
    if matches!(
        last.stop_reason,
        StopReason::Error | StopReason::Aborted | StopReason::Pending
    ) {
        return Err(diagnostics::classify(last).into());
    }
    if last.stop_reason == StopReason::Length {
        return Err("assistant_output_truncated".into());
    }
    if last.raw_stop_reason.as_deref() == Some("refusal") {
        return Err("assistant_refusal".into());
    }
    let text = Content::text_only(&last.content, "\n");
    if text.trim().is_empty()
        && !last
            .content
            .iter()
            .any(|block| matches!(block, Content::ToolCall(_)))
    {
        return Err("assistant_empty_response".into());
    }
    Ok(RunResult {
        history,
        text,
        context_summary,
    })
}

fn observe(event: AgentEvent, transcript: &mut Vec<AgentMessage>, events: &EventHandler) {
    match event {
        AgentEvent::MessageUpdate {
            assistant_message_event:
                AssistantMessageEvent::TextDelta { .. }
                | AssistantMessageEvent::ThinkingStart { .. }
                | AssistantMessageEvent::ThinkingDelta { .. }
                | AssistantMessageEvent::ThinkingEnd { .. },
            ..
        }
        | AgentEvent::ToolExecutionStart { .. }
        | AgentEvent::ToolExecutionEnd { .. } => events(Event::Agent(Box::new(event))),
        AgentEvent::MessageEnd { mut message, .. } => {
            history::sanitize(&mut message);
            transcript.push(message);
            events(Event::Checkpoint(history::encode(transcript)));
        }
        _ => {}
    }
}

fn bounded_stream(
    provider: Arc<dyn PiProvider>,
    limits: Limits,
    events: EventHandler,
    failure: Arc<AtomicUsize>,
    context_summary: Option<ContextSummary>,
    initial_calls: usize,
) -> rpi_agent::StreamFn {
    let calls = Arc::new(AtomicUsize::new(initial_calls));
    rpi_agent::stream_fn(move |model, context, options| {
        let model = model.clone();
        let mut context = context.clone();
        let mut options = options.clone();
        options.max_tokens = Some(limits.output_tokens.clamp(256, 16_384));
        options.timeout = Some(limits.timeout);
        options.stream_idle_timeout = Some(std::time::Duration::from_secs(45));
        options.max_retries = Some(0);
        let (mut output, stream) =
            create_assistant_message_event_stream_with_cancellation(&options.signal);
        let mut reason = if calls.fetch_add(1, Ordering::Relaxed) >= limits.max_turns {
            failure.store(1, Ordering::Relaxed);
            Some("assistant_step_limit")
        } else {
            match compaction::bound_context(
                &mut context,
                context_summary.as_ref(),
                limits.context_chars,
            ) {
                Ok(0) => None,
                Ok(messages) => {
                    events(Event::ContextTrimmed { messages });
                    None
                }
                Err(_) => {
                    failure.store(2, Ordering::Relaxed);
                    Some("assistant_context_limit")
                }
            }
        };
        // Text-context trimming must not remove or inflate this turn's images.
        // The provider envelope adds a small bounded overhead to this projection.
        if reason.is_none()
            && serde_json::to_vec(&context).map_or(true, |bytes| bytes.len() > 13_000_000)
        {
            failure.store(2, Ordering::Relaxed);
            reason = Some("assistant_context_limit");
        }
        let provider = provider.clone();
        let failure = failure.clone();
        tokio::spawn(async move {
            if let Some(reason) = reason {
                output.push(error_event(&model, reason)).await;
                return;
            }
            let mut input = tokio::select! {
                biased;
                _ = options.signal.cancelled() => { output.push(error_event(&model, "assistant_cancelled")).await; return; }
                stream = provider.stream_simple(&model, &context, &options) => stream,
            };
            let mut text_bytes = 0;
            let mut terminal = false;
            loop {
                let event = tokio::select! {
                    biased;
                    _ = options.signal.cancelled() => { output.push(error_event(&model, "assistant_cancelled")).await; return; }
                    event = input.next() => event,
                };
                let Some(event) = event else {
                    break;
                };
                terminal |= matches!(
                    event,
                    AssistantMessageEvent::Done { .. } | AssistantMessageEvent::Error { .. }
                );
                if let AssistantMessageEvent::TextDelta { delta, .. } = &event {
                    text_bytes += delta.len();
                    if text_bytes > 64_000 {
                        failure.store(3, Ordering::Relaxed);
                        output
                            .push(error_event(&model, "assistant_output_limit"))
                            .await;
                        return;
                    }
                }
                let event = match event {
                    AssistantMessageEvent::Error { reason, mut error } => {
                        let code = diagnostics::classify(&error);
                        failure.store(diagnostics::index(code), Ordering::Relaxed);
                        error.error_message = Some(code.into());
                        error.raw_stop_reason = None;
                        error.content.clear();
                        AssistantMessageEvent::Error { reason, error }
                    }
                    event => event,
                };
                if !output.push(event).await {
                    break;
                }
            }
            if !terminal {
                failure.store(
                    diagnostics::index("assistant_stream_incomplete"),
                    Ordering::Relaxed,
                );
                output
                    .push(error_event(&model, "assistant_stream_incomplete"))
                    .await;
            }
        });
        stream
    })
}

fn error_event(model: &Model, reason: &str) -> AssistantMessageEvent {
    AssistantMessageEvent::Error {
        reason: ErrorReason::Error,
        error: AssistantMessage::terminal(
            model.api.clone(),
            &model.provider,
            &model.id,
            StopReason::Error,
            reason,
            0,
        ),
    }
}

#[cfg(test)]
#[allow(clippy::too_many_arguments)]
async fn execute(
    model: Model,
    provider: Arc<dyn PiProvider>,
    system_prompt: String,
    limits: Limits,
    values: Vec<Value>,
    prompt: String,
    tools: Vec<ToolSpec>,
    handler: ToolHandler,
    events: EventHandler,
    cancel: CancellationToken,
) -> Result<RunResult, String> {
    execute_with_summary(
        model,
        provider,
        system_prompt,
        limits,
        None,
        values,
        prompt,
        tools,
        handler,
        events,
        cancel,
    )
    .await
}

#[cfg(test)]
mod tests;
