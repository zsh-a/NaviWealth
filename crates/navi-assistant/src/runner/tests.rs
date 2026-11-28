use std::sync::Mutex;

use futures::FutureExt;
use rpi_ai::{
    providers::faux::{FauxProvider, FauxScript, FauxStep, faux_assistant_message},
    types::{Api, Message, UserMessage},
};
use serde_json::json;

use super::*;

fn events() -> (EventHandler, Arc<Mutex<Vec<Event>>>) {
    let kept = Arc::new(Mutex::new(Vec::new()));
    let copy = kept.clone();
    (
        Arc::new(move |event| copy.lock().unwrap().push(event)),
        kept,
    )
}

fn tool() -> ToolSpec {
    ToolSpec {
        name: "lookup".into(),
        description: "Read a local fact".into(),
        parameters: json!({"type":"object","properties":{"query":{"type":"string"}},"required":["query"],"additionalProperties":false}),
    }
}

fn handler() -> ToolHandler {
    Arc::new(|_, params| async move { Ok(json!({"answer":params["query"]})) }.boxed())
}

#[tokio::test]
async fn multi_step_tool_results_are_checkpointed_and_continue_after_restart() {
    let script = FauxScript::new()
        .with_tool_call("lookup", json!({"query":"first"}))
        .with_tool_call("lookup", json!({"query":"second"}));
    script.append_responses(vec![FauxStep::factory(|context| {
        assert_eq!(
            context
                .messages
                .iter()
                .filter(|m| matches!(m, Message::ToolResult(_)))
                .count(),
            2
        );
        faux_assistant_message("Both facts found", StopReason::Stop)
    })]);
    let provider = FauxProvider::new(script);
    let (emit, observed) = events();
    let result = execute(
        provider.default_model().clone(),
        provider,
        "help".into(),
        Limits::default(),
        vec![],
        "Look up two facts".into(),
        vec![tool()],
        handler(),
        emit,
        CancellationToken::new(),
    )
    .await
    .unwrap();
    assert_eq!(result.text, "Both facts found");
    assert_eq!(result.history.len(), 6);
    {
        let observed = observed.lock().unwrap();
        assert_eq!(
            observed
                .iter()
                .filter(|e| matches!(e, Event::Agent(native) if matches!(native.as_ref(), AgentEvent::ToolExecutionEnd { is_error: false, .. })))
                .count(),
            2
        );
        assert!(
            observed.iter().any(
                |e| matches!(e, Event::Checkpoint(h) if h.len() == 1 && h[0]["kind"] == "user")
            )
        );
        assert!(observed.iter().any(
            |e| matches!(e, Event::Checkpoint(h) if h.len() == 3 && h[2]["kind"] == "tool_result")
        ));
    }
    let next = FauxScript::new();
    next.append_responses(vec![FauxStep::factory(|context| {
        assert_eq!(context.messages.len(), 7);
        faux_assistant_message("I remember both", StopReason::Stop)
    })]);
    let provider = FauxProvider::new(next);
    let result = execute(
        provider.default_model().clone(),
        provider,
        "help".into(),
        Limits::default(),
        result.history,
        "What did you find?".into(),
        vec![tool()],
        handler(),
        events().0,
        CancellationToken::new(),
    )
    .await
    .unwrap();
    assert_eq!(result.history.len(), 8);
    assert_eq!(result.text, "I remember both");
}

#[tokio::test]
async fn cancellation_closes_pending_tool_and_never_reexecutes_it_on_resume() {
    let provider =
        FauxProvider::new(FauxScript::new().with_tool_call("lookup", json!({"query":"wait"})));
    let cancel = CancellationToken::new();
    let triggered = cancel.clone();
    let calls = Arc::new(AtomicUsize::new(0));
    let invoked = calls.clone();
    let handler: ToolHandler = Arc::new(move |_, _| {
        invoked.fetch_add(1, Ordering::Relaxed);
        triggered.cancel();
        futures::future::pending().boxed()
    });
    let (emit, observed) = events();
    let result = tokio::time::timeout(
        std::time::Duration::from_secs(2),
        execute(
            provider.default_model().clone(),
            provider,
            "help".into(),
            Limits::default(),
            vec![],
            "Run".into(),
            vec![tool()],
            handler.clone(),
            emit,
            cancel,
        ),
    )
    .await
    .unwrap();
    assert_eq!(result.unwrap_err(), "assistant_cancelled");
    assert_eq!(calls.load(Ordering::Relaxed), 1);
    let history = observed
        .lock()
        .unwrap()
        .iter()
        .rev()
        .find_map(|e| match e {
            Event::Checkpoint(h) => Some(h.clone()),
            _ => None,
        })
        .unwrap();
    assert!(
        history
            .iter()
            .any(|m| m["kind"] == "tool_result" && m["isError"] == true)
    );
    let provider = FauxProvider::new(FauxScript::new().with_text("Stopped; no action repeated"));
    let result = execute(
        provider.default_model().clone(),
        provider,
        "help".into(),
        Limits::default(),
        history,
        "What happened?".into(),
        vec![tool()],
        handler,
        events().0,
        CancellationToken::new(),
    )
    .await
    .unwrap();
    assert_eq!(result.text, "Stopped; no action repeated");
    assert_eq!(calls.load(Ordering::Relaxed), 1);
}

#[tokio::test]
async fn turn_budget_stops_loop_without_losing_completed_tool() {
    let provider = FauxProvider::new(
        FauxScript::new()
            .with_tool_call("lookup", json!({"query":"one"}))
            .with_tool_call("lookup", json!({"query":"two"})),
    );
    let (emit, observed) = events();
    let result = execute(
        provider.default_model().clone(),
        provider,
        "help".into(),
        Limits {
            max_turns: 1,
            ..Limits::default()
        },
        vec![],
        "Run".into(),
        vec![tool()],
        handler(),
        emit,
        CancellationToken::new(),
    )
    .await;
    assert_eq!(result.unwrap_err(), "assistant_step_limit");
    assert_eq!(
        observed
            .lock()
            .unwrap()
            .iter()
            .filter(|e| matches!(e, Event::Agent(native) if matches!(native.as_ref(), AgentEvent::ToolExecutionStart { .. })))
            .count(),
        1
    );
    assert!(observed.lock().unwrap().iter().any(|e| matches!(e, Event::Checkpoint(h) if h.iter().any(|m|m["kind"] == "tool_result" && m["isError"] == false))));
}

#[tokio::test]
async fn provider_errors_never_leak_raw_body_into_events_or_errors() {
    let script = FauxScript::new();
    script.append_responses(vec![FauxStep::message(AssistantMessage::terminal(
        Api::AnthropicMessages,
        "faux",
        "faux",
        StopReason::Error,
        "secret-api-key body",
        0,
    ))]);
    let provider = FauxProvider::new(script);
    let (emit, observed) = events();
    let result = execute(
        provider.default_model().clone(),
        provider,
        "help".into(),
        Limits::default(),
        vec![],
        "Run".into(),
        vec![],
        handler(),
        emit,
        CancellationToken::new(),
    )
    .await;
    assert_eq!(result.unwrap_err(), "assistant_provider");
    assert!(!format!("{:?}", observed.lock().unwrap()).contains("secret-api-key"));
}

#[tokio::test]
async fn context_window_keeps_whole_turns_without_deleting_transcript() {
    let mut old = vec![AgentMessage::from(UserMessage::new("x".repeat(4000), 0))];
    old.push(faux_assistant_message("old answer", StopReason::Stop).into());
    let script = FauxScript::new();
    script.append_responses(vec![FauxStep::factory(|context| {
        assert_eq!(context.messages.len(), 1);
        faux_assistant_message("new answer", StopReason::Stop)
    })]);
    let provider = FauxProvider::new(script);
    let (emit, observed) = events();
    let result = execute(
        provider.default_model().clone(),
        provider,
        "help".into(),
        Limits {
            context_chars: 2048,
            ..Limits::default()
        },
        history::encode(&old),
        "New question".into(),
        vec![],
        handler(),
        emit,
        CancellationToken::new(),
    )
    .await
    .unwrap();
    assert_eq!(result.history.len(), 4);
    assert!(
        observed
            .lock()
            .unwrap()
            .iter()
            .any(|e| matches!(e, Event::ContextTrimmed { messages: 2 }))
    );
}

#[test]
fn interrupted_history_repair_retains_tool_identity_and_rejects_orphan_results() {
    let message = rpi_ai::providers::faux::faux_assistant_message(
        vec![rpi_ai::providers::faux::FauxBlock::tool_call(
            "lookup",
            json!({"query":"q"}),
        )],
        StopReason::ToolUse,
    );
    let call_id = match &message.content[0] {
        Content::ToolCall(call) => call.id.clone(),
        _ => unreachable!(),
    };
    let decoded = history::decode(history::encode(&[message.into()])).unwrap();
    assert_eq!(decoded.len(), 2);
    let AgentMessage::ToolResult(result) = &decoded[1] else {
        panic!("missing result")
    };
    assert_eq!(result.tool_call_id, call_id);
    assert!(result.is_error);
    assert!(history::decode(history::encode(&decoded[1..])).is_err());
    assert!(history::decode(vec![json!({"kind":"made_up"})]).is_err());
}

#[tokio::test]
async fn invalid_tool_arguments_never_reach_the_host() {
    for arguments in [
        json!({}),
        json!({"query": []}),
        json!({"query":"q","unexpected":"extra"}),
    ] {
        let provider = FauxProvider::new(
            FauxScript::new()
                .with_tool_call("lookup", arguments)
                .with_text("Need valid arguments"),
        );
        let calls = Arc::new(AtomicUsize::new(0));
        let copy = calls.clone();
        let handler: ToolHandler = Arc::new(move |_, _| {
            copy.fetch_add(1, Ordering::Relaxed);
            async { Ok(json!({})) }.boxed()
        });
        let result = execute(
            provider.default_model().clone(),
            provider,
            "help".into(),
            Limits::default(),
            vec![],
            "Run".into(),
            vec![tool()],
            handler,
            events().0,
            CancellationToken::new(),
        )
        .await
        .unwrap();
        assert_eq!(calls.load(Ordering::Relaxed), 0);
        assert!(
            result
                .history
                .iter()
                .any(|message| message["kind"] == "tool_result" && message["isError"] == true)
        );
    }
}

#[tokio::test]
async fn cjk_prompt_limit_matches_the_eight_thousand_character_composer() {
    let provider = FauxProvider::new(FauxScript::new().with_text("Received"));
    let result = execute(
        provider.default_model().clone(),
        provider,
        "help".into(),
        Limits::default(),
        vec![],
        "中".repeat(8000),
        vec![],
        handler(),
        events().0,
        CancellationToken::new(),
    )
    .await
    .unwrap();
    assert_eq!(result.text, "Received");
    let provider = FauxProvider::new(FauxScript::new().with_text("Must not run"));
    let result = execute(
        provider.default_model().clone(),
        provider,
        "help".into(),
        Limits::default(),
        vec![],
        "中".repeat(8001),
        vec![],
        handler(),
        events().0,
        CancellationToken::new(),
    )
    .await;
    assert_eq!(result.unwrap_err(), "assistant_prompt_limit");
}

#[tokio::test]
async fn cancellation_in_second_tool_preserves_first_completed_call() {
    let provider = FauxProvider::new(
        FauxScript::new()
            .with_tool_call("lookup", json!({"query":"first"}))
            .with_tool_call("lookup", json!({"query":"second"})),
    );
    let cancel = CancellationToken::new();
    let triggered = cancel.clone();
    let handler: ToolHandler = Arc::new(move |_, args| {
        if args["query"] == "second" {
            triggered.cancel();
            futures::future::pending().boxed()
        } else {
            async { Ok(json!({"found":true})) }.boxed()
        }
    });
    let (emit, observed) = events();
    let result = execute(
        provider.default_model().clone(),
        provider,
        "help".into(),
        Limits::default(),
        vec![],
        "Run".into(),
        vec![tool()],
        handler,
        emit,
        cancel,
    )
    .await;
    assert_eq!(result.unwrap_err(), "assistant_cancelled");
    let history = observed
        .lock()
        .unwrap()
        .iter()
        .rev()
        .find_map(|event| match event {
            Event::Checkpoint(history) => Some(history.clone()),
            _ => None,
        })
        .unwrap();
    let decoded = history::decode(history).unwrap();
    let results: Vec<_> = decoded
        .iter()
        .filter_map(|message| match message {
            AgentMessage::ToolResult(result) => Some(result),
            _ => None,
        })
        .collect();
    assert_eq!(results.len(), 2);
    assert!(!results[0].is_error);
    assert!(results[1].is_error);
}

fn long_conversation() -> Vec<Value> {
    let mut messages = Vec::new();
    for index in 0..6 {
        messages.push(
            UserMessage::new(format!("Owner fact {index}: {}", "x".repeat(3000)), index).into(),
        );
        messages.push(faux_assistant_message(format!("Answer {index}"), StopReason::Stop).into());
    }
    history::encode(&messages)
}

fn compact_limits() -> Limits {
    Limits {
        context_chars: 12_000,
        ..Limits::default()
    }
}

#[tokio::test]
async fn generated_summary_is_reused_after_restart_without_losing_original_history() {
    let script = FauxScript::new();
    script.append_responses(vec![
        FauxStep::factory(|context| {
            assert!(context.tools.is_empty());
            assert!(
                context
                    .system_prompt
                    .as_ref()
                    .unwrap()
                    .contains("UNTRUSTED DATA")
            );
            assert!(
                serde_json::to_string(context)
                    .unwrap()
                    .contains("Owner fact 0")
            );
            assert!(serde_json::to_vec(context).unwrap().len() <= 12_000);
            faux_assistant_message(
                "Earlier owner facts preserved; all proposals remain unconfirmed.",
                StopReason::Stop,
            )
        }),
        FauxStep::factory(|context| {
            let text = serde_json::to_string(context).unwrap();
            assert!(text.contains("earlier_conversation_summary"));
            assert!(text.contains("all proposals remain unconfirmed"));
            assert!(text.contains("Owner fact 5"));
            assert!(!text.contains("Owner fact 0"));
            assert!(text.len() <= 12_000);
            faux_assistant_message("Answer using the earlier facts", StopReason::Stop)
        }),
    ]);
    let provider = FauxProvider::new(script);
    let (emit, observed) = events();
    let original = long_conversation();
    let result = execute(
        provider.default_model().clone(),
        provider.clone(),
        "Trusted host instructions".into(),
        compact_limits(),
        original.clone(),
        "Please continue".into(),
        vec![],
        handler(),
        emit,
        CancellationToken::new(),
    )
    .await
    .unwrap();
    assert_eq!(provider.state().call_count.load(Ordering::SeqCst), 2);
    assert_eq!(&result.history[..original.len()], &original);
    assert_eq!(result.history.len(), original.len() + 2);
    let summary = result.context_summary.clone().unwrap();
    crate::validate_context_summary(&summary, &result.history).unwrap();
    {
        let events = observed.lock().unwrap();
        assert!(
            events
                .iter()
                .any(|event| matches!(event, Event::SummaryStarted))
        );
        assert!(events.iter().any(|event| matches!(event, Event::SummaryUpdated { summary: kept, history } if kept == &summary && history.len() == original.len()+1 && history.last().unwrap()["content"] == "Please continue")));
        assert!(!events.iter().any(
            |event| matches!(event, Event::Agent(native) if matches!(native.as_ref(), AgentEvent::MessageUpdate { assistant_message_event: AssistantMessageEvent::TextDelta {delta, ..}, .. } if delta.contains("Earlier owner facts")))
        ));
        assert!(
            !events
                .iter()
                .any(|event| matches!(event, Event::ContextTrimmed { .. }))
        );
    }
    let script = FauxScript::new();
    script.append_responses(vec![FauxStep::factory(|context| {
        assert!(
            serde_json::to_string(context)
                .unwrap()
                .contains("all proposals remain unconfirmed")
        );
        faux_assistant_message(
            "Continued without another summary request",
            StopReason::Stop,
        )
    })]);
    let provider = FauxProvider::new(script);
    let resumed = execute_with_summary(
        provider.default_model().clone(),
        provider.clone(),
        "Trusted host instructions".into(),
        compact_limits(),
        Some(summary.clone()),
        result.history,
        "And next?".into(),
        vec![],
        handler(),
        events().0,
        CancellationToken::new(),
    )
    .await
    .unwrap();
    assert_eq!(provider.state().call_count.load(Ordering::SeqCst), 1);
    assert_eq!(resumed.context_summary, Some(summary));
    assert_eq!(resumed.history.len(), original.len() + 4);
}

#[tokio::test]
async fn summary_generation_rejects_tools_and_truncation_then_falls_back_without_executing() {
    for bad in [
        FauxStep::tool_call("lookup", json!({"query":"do not execute"})),
        FauxStep::message(faux_assistant_message("partial", StopReason::Length)),
        FauxStep::text("中".repeat(5000)),
    ] {
        let script = FauxScript::new();
        script.append_responses(vec![bad, FauxStep::text("Continued from recent messages")]);
        let provider = FauxProvider::new(script);
        let (emit, observed) = events();
        let calls = Arc::new(AtomicUsize::new(0));
        let calls_clone = calls.clone();
        let handler: ToolHandler = Arc::new(move |_, _| {
            calls_clone.fetch_add(1, Ordering::Relaxed);
            async { Ok(json!({})) }.boxed()
        });
        let result = execute(
            provider.default_model().clone(),
            provider.clone(),
            "help".into(),
            compact_limits(),
            long_conversation(),
            "Continue".into(),
            vec![tool()],
            handler,
            emit,
            CancellationToken::new(),
        )
        .await
        .unwrap();
        assert_eq!(calls.load(Ordering::Relaxed), 0);
        assert!(result.context_summary.is_none());
        assert_eq!(result.history.len(), 14);
        assert_eq!(provider.state().call_count.load(Ordering::Relaxed), 2);
        let events = observed.lock().unwrap();
        assert!(
            !events
                .iter()
                .any(|e| matches!(e, Event::SummaryUpdated { .. }))
        );
        assert!(
            events
                .iter()
                .any(|e| matches!(e, Event::ContextTrimmed { messages } if *messages > 0))
        );
    }
}

#[tokio::test]
async fn summary_calls_share_the_tool_loop_request_budget() {
    let provider = FauxProvider::new(
        FauxScript::new()
            .with_text("Earlier context")
            .with_tool_call("lookup", json!({"query":"one"}))
            .with_text("Must not be reached"),
    );
    let result = execute(
        provider.default_model().clone(),
        provider.clone(),
        "help".into(),
        Limits {
            max_turns: 2,
            ..compact_limits()
        },
        long_conversation(),
        "Continue".into(),
        vec![tool()],
        handler(),
        events().0,
        CancellationToken::new(),
    )
    .await;
    assert_eq!(result.unwrap_err(), "assistant_step_limit");
    assert_eq!(provider.state().call_count.load(Ordering::SeqCst), 2);
    assert_eq!(provider.script().pending_count(), 1);
}

#[tokio::test]
async fn cancellation_during_preparation_never_publishes_a_summary_or_drops_the_owner_turn() {
    let cancel = CancellationToken::new();
    let triggered = cancel.clone();
    let script = FauxScript::new();
    script.append_responses(vec![
        FauxStep::factory(move |_| {
            triggered.cancel();
            faux_assistant_message("must not be persisted", StopReason::Stop)
        }),
        FauxStep::text("must not continue"),
    ]);
    let provider = FauxProvider::new(script);
    let (emit, observed) = events();
    let result = execute(
        provider.default_model().clone(),
        provider.clone(),
        "help".into(),
        compact_limits(),
        long_conversation(),
        "Keep this submitted question".into(),
        vec![],
        handler(),
        emit,
        cancel,
    )
    .await;
    assert_eq!(result.unwrap_err(), "assistant_cancelled");
    let events = observed.lock().unwrap();
    assert!(
        !events
            .iter()
            .any(|e| matches!(e, Event::SummaryUpdated { .. }))
    );
    let history = events
        .iter()
        .rev()
        .find_map(|e| match e {
            Event::Checkpoint(h) => Some(h),
            _ => None,
        })
        .unwrap();
    assert_eq!(history.len(), 13);
    assert_eq!(
        history.last().unwrap()["content"],
        "Keep this submitted question"
    );
    assert_eq!(provider.script().pending_count(), 1);
}

#[tokio::test]
async fn total_deadline_also_limits_summary_preparation() {
    let provider = FauxProvider::new(
        FauxScript::new()
            .with_text("a long summary that streams slowly")
            .with_text("must not continue")
            .with_tokens_per_second(1.0),
    );
    let result = execute(
        provider.default_model().clone(),
        provider.clone(),
        "help".into(),
        Limits {
            timeout: std::time::Duration::from_millis(30),
            ..compact_limits()
        },
        long_conversation(),
        "Continue".into(),
        vec![],
        handler(),
        events().0,
        CancellationToken::new(),
    )
    .await;
    assert_eq!(result.unwrap_err(), "assistant_timeout");
    assert_eq!(provider.script().pending_count(), 1);
}

#[tokio::test]
async fn stopping_between_summary_and_first_agent_poll_never_starts_a_new_request() {
    for timeout in [false, true] {
        let provider = FauxProvider::new(
            FauxScript::new()
                .with_text("Earlier facts")
                .with_text("MUST NOT START"),
        );
        let cancel = CancellationToken::new();
        let triggered = cancel.clone();
        let (record, observed) = events();
        let emit: EventHandler = Arc::new(move |event| {
            let summarized = matches!(event, Event::SummaryUpdated { .. });
            record(event);
            if summarized {
                if timeout {
                    std::thread::sleep(std::time::Duration::from_millis(80));
                } else {
                    triggered.cancel();
                }
            }
        });
        let result = execute(
            provider.default_model().clone(),
            provider.clone(),
            "help".into(),
            Limits {
                timeout: std::time::Duration::from_millis(60),
                ..compact_limits()
            },
            long_conversation(),
            "Keep the current owner question".into(),
            vec![],
            handler(),
            emit,
            cancel,
        )
        .await;
        assert_eq!(
            result.unwrap_err(),
            if timeout {
                "assistant_timeout"
            } else {
                "assistant_cancelled"
            }
        );
        assert_eq!(provider.state().call_count.load(Ordering::SeqCst), 1);
        assert_eq!(provider.script().pending_count(), 1);
        for event in observed.lock().unwrap().iter() {
            let kept = match event {
                Event::Checkpoint(history) | Event::SummaryUpdated { history, .. } => Some(history),
                _ => None,
            };
            if let Some(history) = kept {
                assert_eq!(
                    history.len(),
                    13,
                    "no checkpoint removes the submitted question"
                );
                assert_eq!(
                    history.last().unwrap()["content"],
                    "Keep the current owner question"
                );
            }
        }
    }
}

#[tokio::test]
async fn incremental_summary_extends_the_bound_prefix_and_keeps_recent_turns() {
    let original = long_conversation();
    let summary =
        ContextSummary::new(&original, 6, "Previous summarized owner facts.".into()).unwrap();
    let mut extended = original;
    for index in 6..9 {
        extended.extend(history::encode(&[
            UserMessage::new(
                format!("Added owner fact {index}: {}", "x".repeat(3000)),
                index,
            )
            .into(),
            faux_assistant_message(format!("Answer {index}"), StopReason::Stop).into(),
        ]));
    }
    let script = FauxScript::new();
    script.append_responses(vec![
        FauxStep::factory(|context| {
            let text = serde_json::to_string(context).unwrap();
            assert!(context.tools.is_empty());
            assert!(text.contains("Previous summarized owner facts"));
            assert!(text.contains("Owner fact 3"));
            assert!(!text.contains("Owner fact 0"));
            faux_assistant_message(
                "Merged previous and additional facts; no approval granted.",
                StopReason::Stop,
            )
        }),
        FauxStep::factory(|context| {
            let text = serde_json::to_string(context).unwrap();
            assert!(text.contains("Merged previous and additional facts"));
            assert!(text.contains("Added owner fact 8"));
            faux_assistant_message("Answer with merged context", StopReason::Stop)
        }),
    ]);
    let provider = FauxProvider::new(script);
    let result = execute_with_summary(
        provider.default_model().clone(),
        provider.clone(),
        "help".into(),
        compact_limits(),
        Some(summary.clone()),
        extended.clone(),
        "Continue".into(),
        vec![],
        handler(),
        events().0,
        CancellationToken::new(),
    )
    .await
    .unwrap();
    assert_eq!(provider.state().call_count.load(Ordering::SeqCst), 2);
    let next = result.context_summary.unwrap();
    assert!(next.covered_messages > summary.covered_messages);
    crate::validate_context_summary(&next, &result.history).unwrap();
    assert_eq!(&result.history[..extended.len()], &extended);
}

fn image_prompt() -> UserMessage {
    UserMessage::new(
        UserContent::Blocks(vec![Content::Image(ImageContent {
            kind: Default::default(),
            data: STANDARD.encode(vec![0xAB; 128 * 1024]).into(),
            mime_type: "image/png".into(),
        })]),
        0,
    )
}

#[tokio::test]
async fn successful_owner_proposals_suspend_and_resume_without_repeating_tools() {
    for name in ["ask_user", "propose_record", "revise_record"] {
        let provider = FauxProvider::new(
            FauxScript::new()
                .with_tool_call(name, json!({"query":"details"}))
                .with_text("Must not request an extra response"),
        );
        let mut spec = tool();
        spec.name = name.into();
        let calls = Arc::new(AtomicUsize::new(0));
        let copy = calls.clone();
        let host: ToolHandler = Arc::new(move |_, _| {
            copy.fetch_add(1, Ordering::Relaxed);
            async { Ok(json!({"status":"awaiting_owner"})) }.boxed()
        });
        let (emit, observed) = events();
        let result = execute_input(
            provider.default_model().clone(),
            provider.clone(),
            "Help".into(),
            Limits::default(),
            None,
            vec![],
            image_prompt(),
            vec![spec.clone()],
            host.clone(),
            emit,
            CancellationToken::new(),
            true,
        )
        .await
        .unwrap();
        assert_eq!(provider.state().call_count.load(Ordering::SeqCst), 1);
        assert_eq!(provider.script().pending_count(), 1);
        assert_eq!(result.history.len(), 3);
        assert_eq!(result.history[2]["kind"], "tool_result");
        assert_eq!(result.history[2]["isError"], false);
        assert_eq!(calls.load(Ordering::Relaxed), 1);
        for event in observed.lock().unwrap().iter() {
            if let Event::Checkpoint(kept) = event {
                let text = serde_json::to_string(kept).unwrap();
                assert!(!text.contains("q6urq6ur"));
                assert!(text.contains(history::OMITTED_IMAGE));
            }
        }
        let next = FauxScript::new();
        next.append_responses(vec![FauxStep::factory(|context| {
            assert_eq!(context.messages.len(), 4);
            assert!(
                matches!(&context.messages[2], Message::ToolResult(result) if !result.is_error)
            );
            faux_assistant_message("Owner answered; continuing", StopReason::Stop)
        })]);
        let next = FauxProvider::new(next);
        let resumed = execute_input(
            next.default_model().clone(),
            next,
            "Help".into(),
            Limits::default(),
            None,
            result.history,
            UserMessage::new("My answer", 0),
            vec![spec],
            host,
            events().0,
            CancellationToken::new(),
            true,
        )
        .await
        .unwrap();
        assert_eq!(calls.load(Ordering::Relaxed), 1);
        assert_eq!(resumed.text, "Owner answered; continuing");
    }
}

#[tokio::test]
async fn rejected_proposal_does_not_suspend_the_model_loop() {
    let provider = FauxProvider::new(
        FauxScript::new()
            .with_tool_call("propose_record", json!({"query":"invalid"}))
            .with_text("The proposal needs correction"),
    );
    let mut spec = tool();
    spec.name = "propose_record".into();
    let result = execute_input(
        provider.default_model().clone(),
        provider.clone(),
        "Help".into(),
        Limits::default(),
        None,
        vec![],
        UserMessage::new("Record", 0),
        vec![spec],
        Arc::new(|_, _| async { Err("assistant_tool".into()) }.boxed()),
        events().0,
        CancellationToken::new(),
        true,
    )
    .await
    .unwrap();
    assert_eq!(provider.state().call_count.load(Ordering::SeqCst), 2);
    assert_eq!(result.text, "The proposal needs correction");
    assert_eq!(result.history[2]["isError"], true);
}

#[tokio::test]
async fn cancelled_image_turn_preserves_text_only_checkpoint_and_tool_identity() {
    let provider =
        FauxProvider::new(FauxScript::new().with_tool_call("lookup", json!({"query":"wait"})));
    let cancel = CancellationToken::new();
    let trigger = cancel.clone();
    let (emit, observed) = events();
    let result = execute_input(
        provider.default_model().clone(),
        provider,
        "Help".into(),
        Limits::default(),
        None,
        vec![],
        image_prompt(),
        vec![tool()],
        Arc::new(move |_, _| {
            trigger.cancel();
            futures::future::pending().boxed()
        }),
        emit,
        cancel,
        true,
    )
    .await;
    assert_eq!(result.unwrap_err(), "assistant_cancelled");
    let events = observed.lock().unwrap();
    let kept = events
        .iter()
        .rev()
        .find_map(|event| match event {
            Event::Checkpoint(kept) => Some(kept),
            _ => None,
        })
        .unwrap();
    let text = serde_json::to_string(kept).unwrap();
    assert!(text.contains(history::OMITTED_IMAGE));
    assert!(!text.contains("q6urq6ur"));
    let decoded = history::decode(kept.clone()).unwrap();
    assert!(
        decoded.iter().any(|message| matches!(message, AgentMessage::ToolResult(result) if result.is_error && result.tool_name == "lookup"))
    );
}

#[tokio::test]
async fn image_history_summary_bindings_survive_redaction_and_restart() {
    let mut original = history::encode(&[
        image_prompt().into(),
        faux_assistant_message(
            "Earlier meal image; no owner confirmation yet",
            StopReason::Stop,
        )
        .into(),
    ]);
    original.extend(long_conversation());
    let script = FauxScript::new();
    script.append_responses(vec![
        FauxStep::factory(|context| {
            let text = serde_json::to_string(context).unwrap();
            assert!(!text.contains("q6urq6ur"));
            assert!(text.contains(history::OMITTED_IMAGE));
            faux_assistant_message("Earlier image and facts; all drafts are unconfirmed.", StopReason::Stop)
        }),
        FauxStep::factory(|context| {
            assert!(context.messages.iter().any(|message| matches!(message, Message::User(user) if matches!(&user.content, UserContent::Blocks(blocks) if blocks.iter().any(|block| matches!(block, Content::Image(_)))))));
            faux_assistant_message("New image received", StopReason::Stop)
        }),
    ]);
    let provider = FauxProvider::new(script);
    let (emit, observed) = events();
    let result = execute_input(
        provider.default_model().clone(),
        provider,
        "Help".into(),
        compact_limits(),
        None,
        original.clone(),
        image_prompt(),
        vec![],
        handler(),
        emit,
        CancellationToken::new(),
        true,
    )
    .await
    .unwrap();
    assert_eq!(&result.history[..original.len()], &original);
    let summary = result.context_summary.unwrap();
    crate::validate_context_summary(&summary, &result.history).unwrap();
    for event in observed.lock().unwrap().iter() {
        if let Event::SummaryUpdated { summary, history } = event {
            crate::validate_context_summary(summary, history).unwrap();
            assert!(!serde_json::to_string(history).unwrap().contains("q6urq6ur"));
        }
    }
    let provider = FauxProvider::new(FauxScript::new().with_text("Continued"));
    let result = execute_input(
        provider.default_model().clone(),
        provider.clone(),
        "Help".into(),
        compact_limits(),
        Some(summary),
        result.history,
        UserMessage::new("Continue", 0),
        vec![],
        handler(),
        events().0,
        CancellationToken::new(),
        true,
    )
    .await
    .unwrap();
    assert_eq!(provider.state().call_count.load(Ordering::SeqCst), 1);
    assert_eq!(result.text, "Continued");
}

#[test]
fn redacting_image_history_preserves_provider_tool_ids_and_signatures() {
    let mut assistant = faux_assistant_message(
        vec![rpi_ai::providers::faux::FauxBlock::tool_call(
            "lookup",
            json!({"query":"q"}),
        )],
        StopReason::ToolUse,
    );
    let Content::ToolCall(call) = &mut assistant.content[0] else {
        unreachable!()
    };
    call.id = "call_provider-id|opaque-item-id".into();
    call.thought_signature = Some("opaque-signed-context".into());
    call.namespace = Some("owner_tools".into());
    let original = call.clone();
    let kept =
        history::decode(history::encode(&[image_prompt().into(), assistant.into()])).unwrap();
    let AgentMessage::Assistant(assistant) = &kept[1] else {
        unreachable!()
    };
    assert_eq!(assistant.content[0], Content::ToolCall(original.clone()));
    let AgentMessage::ToolResult(result) = &kept[2] else {
        unreachable!()
    };
    assert_eq!(result.tool_call_id, original.id);
    assert_eq!(result.tool_name, original.name);
    assert!(result.is_error);
    assert!(
        serde_json::to_string(&history::encode(&kept))
            .unwrap()
            .contains(history::OMITTED_IMAGE)
    );
}
