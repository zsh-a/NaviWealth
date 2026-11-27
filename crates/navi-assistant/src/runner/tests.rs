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
                .filter(|e| matches!(
                    e,
                    Event::ToolFinished {
                        is_error: false,
                        ..
                    }
                ))
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
            .filter(|e| matches!(e, Event::ToolStarted { .. }))
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
