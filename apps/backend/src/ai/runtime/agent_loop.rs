//! Provider-neutral LLM/tool loop.

use std::cell::RefCell;
use std::collections::BTreeMap;
use std::rc::Rc;

use async_trait::async_trait;
use futures_util::future::{select, Either};
use futures_util::StreamExt;
use gloo_timers::future::TimeoutFuture;
use serde_json::{json, Value};
use worker::D1Database;

use crate::ai::adapters::anthropic::wire::ToolSchema;
use crate::ai::guardrails::{
    self, ANTHROPIC_MAX_OUTPUT_TOKENS, MAX_PROPOSALS_PER_CONVERSATION, MAX_TOOL_ROUNDS,
};
use crate::ai::runtime::{AgentEvent, AgentRequest, EventSink, LlmAdapter, Session, StopReason};
use crate::ai::tools::{self, ToolCtx};
use crate::error::AppError;

#[derive(Debug, Clone, Copy)]
pub struct TurnBudget {
    pub max_rounds: u8,
    pub turn_timeout_ms: u32,
}

impl Default for TurnBudget {
    fn default() -> Self {
        Self {
            max_rounds: MAX_TOOL_ROUNDS,
            turn_timeout_ms: 60_000,
        }
    }
}

#[async_trait(?Send)]
pub trait ToolDispatcher {
    async fn dispatch(&self, session: &Session, name: &str, input: &Value) -> Value;
}

pub struct CloudToolDispatcher {
    db: D1Database,
    user_id: String,
}

impl CloudToolDispatcher {
    pub fn new(db: D1Database, user_id: String) -> Self {
        Self { db, user_id }
    }
}

#[async_trait(?Send)]
impl ToolDispatcher for CloudToolDispatcher {
    async fn dispatch(&self, session: &Session, name: &str, input: &Value) -> Value {
        let ctx = ToolCtx {
            user_id: &self.user_id,
            db: &self.db,
            portfolio_snapshot: session.portfolio_snapshot.as_ref(),
            context_tier: session.context_tier,
        };
        tools::registry().dispatch(&ctx, name, input).await
    }
}

pub struct AgentLoop<A: LlmAdapter> {
    adapter: A,
    model: String,
    tool_schemas: Vec<ToolSchema>,
    dispatcher: Rc<dyn ToolDispatcher>,
    budget: TurnBudget,
}

impl<A: LlmAdapter> AgentLoop<A> {
    pub fn new(
        adapter: A,
        model: String,
        dispatcher: Rc<dyn ToolDispatcher>,
        budget: TurnBudget,
    ) -> Self {
        Self {
            adapter,
            model,
            tool_schemas: tools::registry().schemas(),
            dispatcher,
            budget,
        }
    }

    pub async fn run(
        &self,
        session: &mut Session,
        sink: &mut dyn EventSink,
    ) -> Result<StopReason, AppError> {
        if self.budget.turn_timeout_ms == 0 {
            return emit_timeout(session, sink);
        }

        let work = Box::pin(self.run_inner(session, sink));
        let timeout = Box::pin(TimeoutFuture::new(self.budget.turn_timeout_ms));
        match select(work, timeout).await {
            Either::Left((result, _)) => return result,
            Either::Right((_, work)) => {
                drop(work);
            }
        };
        emit_timeout(session, sink)
    }

    async fn run_inner(
        &self,
        session: &mut Session,
        sink: &mut dyn EventSink,
    ) -> Result<StopReason, AppError> {
        let system = session.system_prompt();
        let tool_values = encode_values(&self.tool_schemas)?;
        let mut last_stop = StopReason::EndTurn;

        for round in 0..self.budget.max_rounds {
            session.rounds_used = round + 1;
            let message_values = encode_values(&session.messages)?;
            let req = AgentRequest {
                model: &self.model,
                max_tokens: ANTHROPIC_MAX_OUTPUT_TOKENS,
                system: &system,
                messages: &message_values,
                tools: &tool_values,
            };

            let stream = match self.adapter.stream(req).await {
                Ok(stream) => stream,
                Err(e) => return self.finish_with_error(session, sink, e.to_string()),
            };

            let model_round = match collect_model_round(stream, sink).await? {
                ModelRoundOutcome::Complete(round) => round,
                ModelRoundOutcome::Error { code, message } => {
                    sink.emit(AgentEvent::Error { code, message })?;
                    sink.emit(AgentEvent::Stop {
                        reason: StopReason::Error,
                        rounds: session.rounds_used,
                    })?;
                    return Ok(StopReason::Error);
                }
            };
            last_stop = model_round.stop_reason;

            if model_round.tool_uses.is_empty() {
                break;
            }

            let proposals_before = guardrails::count_existing_proposals(&session.messages);
            session
                .messages
                .push(crate::ai::adapters::anthropic::wire::ChatMessage {
                    role: "assistant".into(),
                    content: Value::Array(model_round.assistant_content),
                });

            let mut tool_results = Vec::with_capacity(model_round.tool_uses.len());
            let mut proposals_this_turn = 0u8;
            for tool_use in &model_round.tool_uses {
                let is_propose = tool_use.name.starts_with("propose_");
                let output = if is_propose
                    && proposals_before.saturating_add(proposals_this_turn)
                        >= MAX_PROPOSALS_PER_CONVERSATION
                {
                    proposal_cap_exceeded()
                } else {
                    if is_propose {
                        proposals_this_turn = proposals_this_turn.saturating_add(1);
                    }
                    self.dispatcher
                        .dispatch(session, &tool_use.name, &tool_use.input)
                        .await
                };

                sink.emit(AgentEvent::ToolResult {
                    id: tool_use.id.clone(),
                    name: tool_use.name.clone(),
                    output: output.clone(),
                })?;
                tool_results.push(tool_result_block(&tool_use.id, &output));
            }

            session
                .messages
                .push(crate::ai::adapters::anthropic::wire::ChatMessage {
                    role: "user".into(),
                    content: Value::Array(tool_results),
                });
        }

        if session.rounds_used >= self.budget.max_rounds && last_stop == StopReason::ToolUse {
            sink.emit(AgentEvent::Error {
                code: "tool_round_budget_exhausted".into(),
                message: "tool round budget exhausted".into(),
            })?;
        }
        sink.emit(AgentEvent::Stop {
            reason: last_stop,
            rounds: session.rounds_used,
        })?;
        Ok(last_stop)
    }

    fn finish_with_error(
        &self,
        session: &Session,
        sink: &mut dyn EventSink,
        message: String,
    ) -> Result<StopReason, AppError> {
        sink.emit(AgentEvent::Error {
            code: "provider_error".into(),
            message,
        })?;
        sink.emit(AgentEvent::Stop {
            reason: StopReason::Error,
            rounds: session.rounds_used,
        })?;
        Ok(StopReason::Error)
    }
}

fn emit_timeout(session: &Session, sink: &mut dyn EventSink) -> Result<StopReason, AppError> {
    sink.emit(AgentEvent::Error {
        code: "chat_timeout".into(),
        message: "chat turn timed out".into(),
    })?;
    sink.emit(AgentEvent::Stop {
        reason: StopReason::Error,
        rounds: session.rounds_used,
    })?;
    Ok(StopReason::Error)
}

#[derive(Debug, Clone, PartialEq)]
struct ToolUse {
    id: String,
    name: String,
    input: Value,
}

#[derive(Debug)]
struct ModelRound {
    assistant_content: Vec<Value>,
    tool_uses: Vec<ToolUse>,
    stop_reason: StopReason,
}

enum ModelRoundOutcome {
    Complete(ModelRound),
    Error { code: String, message: String },
}

async fn collect_model_round(
    mut stream: futures_util::stream::BoxStream<'_, AgentEvent>,
    sink: &mut dyn EventSink,
) -> Result<ModelRoundOutcome, AppError> {
    let mut text = String::new();
    let mut tool_names = BTreeMap::<String, String>::new();
    let mut assistant_content = Vec::new();
    let mut tool_uses = Vec::new();
    let mut stop_reason = StopReason::EndTurn;

    while let Some(event) = stream.next().await {
        match event {
            AgentEvent::TextDelta { text: delta } => {
                text.push_str(&delta);
                sink.emit(AgentEvent::TextDelta { text: delta })?;
            }
            AgentEvent::ThinkingDelta { .. } | AgentEvent::Usage { .. } => {
                sink.emit(event)?;
            }
            AgentEvent::ToolCallStart { id, name } => {
                flush_text_block(&mut text, &mut assistant_content);
                tool_names.insert(id.clone(), name.clone());
                sink.emit(AgentEvent::ToolCallStart { id, name })?;
            }
            AgentEvent::ToolCallDelta {
                id,
                partial_input_json,
            } => {
                sink.emit(AgentEvent::ToolCallDelta {
                    id,
                    partial_input_json,
                })?;
            }
            AgentEvent::ToolCallEnd { id, input } => {
                let name = tool_names.remove(&id).unwrap_or_default();
                assistant_content.push(json!({
                    "type": "tool_use",
                    "id": id,
                    "name": name,
                    "input": input,
                }));
                if let Some(block) = assistant_content.last() {
                    tool_uses.push(ToolUse {
                        id: block["id"].as_str().unwrap_or_default().into(),
                        name: block["name"].as_str().unwrap_or_default().into(),
                        input: block["input"].clone(),
                    });
                }
                sink.emit(AgentEvent::ToolCallEnd {
                    id: tool_uses.last().map(|t| t.id.clone()).unwrap_or_default(),
                    input: tool_uses
                        .last()
                        .map(|t| t.input.clone())
                        .unwrap_or(Value::Null),
                })?;
            }
            AgentEvent::ToolResult { .. } => {}
            AgentEvent::Stop { reason, .. } => {
                stop_reason = reason;
            }
            AgentEvent::Error { code, message } => {
                return Ok(ModelRoundOutcome::Error { code, message });
            }
        }
    }

    flush_text_block(&mut text, &mut assistant_content);
    Ok(ModelRoundOutcome::Complete(ModelRound {
        assistant_content,
        tool_uses,
        stop_reason,
    }))
}

fn flush_text_block(text: &mut String, content: &mut Vec<Value>) {
    if !text.is_empty() {
        content.push(json!({"type": "text", "text": std::mem::take(text)}));
    }
}

fn proposal_cap_exceeded() -> Value {
    json!({
        "error": "proposal_cap_exceeded",
        "code": "proposal_cap_exceeded",
        "limit": MAX_PROPOSALS_PER_CONVERSATION,
        "message": format!(
            "本次对话已达到 {MAX_PROPOSALS_PER_CONVERSATION} 个 propose_* 上限。\
             请让用户先在前端确认页处理已有的提议（确认或取消），再继续录入。"
        ),
    })
}

fn tool_result_block(tool_use_id: &str, output: &Value) -> Value {
    let serialized = serde_json::to_string(output).unwrap_or_else(|_| "null".into());
    json!({
        "type": "tool_result",
        "tool_use_id": tool_use_id,
        "content": serialized,
    })
}

fn encode_values<T: serde::Serialize>(items: &[T]) -> Result<Vec<Value>, AppError> {
    items
        .iter()
        .map(|item| serde_json::to_value(item).map_err(|e| AppError::Internal(format!("ser: {e}"))))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ai::adapters::anthropic::wire::ChatMessage;
    use crate::ai::adapters::mock::{MockAdapter, MockRound};
    use crate::ai::runtime::AgentEvent;

    #[derive(Default)]
    struct RecordingDispatcher {
        calls: RefCell<Vec<String>>,
    }

    #[async_trait(?Send)]
    impl ToolDispatcher for RecordingDispatcher {
        async fn dispatch(&self, _session: &Session, name: &str, _input: &Value) -> Value {
            self.calls.borrow_mut().push(name.to_string());
            json!({"ok": true, "tool": name})
        }
    }

    fn session(messages: Vec<ChatMessage>) -> Session {
        Session::new(messages, None, None, None)
    }

    fn user_message(text: &str) -> ChatMessage {
        ChatMessage {
            role: "user".into(),
            content: json!(text),
        }
    }

    fn loop_with(
        adapter: MockAdapter,
        dispatcher: Rc<dyn ToolDispatcher>,
        budget: TurnBudget,
    ) -> AgentLoop<MockAdapter> {
        AgentLoop::new(adapter, "test-model".into(), dispatcher, budget)
    }

    #[test]
    fn tool_result_block_serializes_output_for_next_llm_round() {
        let output = json!({"alerts": [{"kind": "asset_concentration"}]});
        let block = tool_result_block("toolu_1", &output);

        assert_eq!(block["type"], "tool_result");
        assert_eq!(block["tool_use_id"], "toolu_1");
        let decoded: Value = serde_json::from_str(block["content"].as_str().unwrap()).unwrap();
        assert_eq!(decoded, output);
    }

    #[test]
    fn advances_multiple_tool_rounds() {
        futures_executor::block_on(async {
            let dispatcher = Rc::new(RecordingDispatcher::default());
            let adapter = MockAdapter::scripted(vec![
                MockRound::events(vec![
                    AgentEvent::TextDelta {
                        text: "checking".into(),
                    },
                    AgentEvent::ToolCallStart {
                        id: "t1".into(),
                        name: "get_risk_alerts".into(),
                    },
                    AgentEvent::ToolCallEnd {
                        id: "t1".into(),
                        input: json!({}),
                    },
                    AgentEvent::Stop {
                        reason: StopReason::ToolUse,
                        rounds: 0,
                    },
                ]),
                MockRound::events(vec![
                    AgentEvent::TextDelta {
                        text: "done".into(),
                    },
                    AgentEvent::Stop {
                        reason: StopReason::EndTurn,
                        rounds: 0,
                    },
                ]),
            ]);
            let agent = loop_with(adapter, dispatcher.clone(), TurnBudget::default());
            let mut session = session(vec![user_message("hi")]);
            let mut events = Vec::new();

            let reason = agent.run_inner(&mut session, &mut events).await.unwrap();

            assert_eq!(reason, StopReason::EndTurn);
            assert_eq!(session.rounds_used, 2);
            assert_eq!(dispatcher.calls.borrow().as_slice(), ["get_risk_alerts"]);
            assert_eq!(session.messages.len(), 3);
            assert_eq!(
                events.last(),
                Some(&AgentEvent::Stop {
                    reason: StopReason::EndTurn,
                    rounds: 2
                })
            );
        });
    }

    #[test]
    fn proposal_cap_exceeded_skips_dispatch() {
        futures_executor::block_on(async {
            let dispatcher = Rc::new(RecordingDispatcher::default());
            let mut messages = Vec::new();
            for i in 0..MAX_PROPOSALS_PER_CONVERSATION {
                messages.push(ChatMessage {
                role: "assistant".into(),
                content: json!([{"type": "tool_use", "id": format!("old_{i}"), "name": "propose_expense", "input": {}}]),
            });
            }
            messages.push(user_message("add another"));
            let adapter = MockAdapter::scripted(vec![
                MockRound::events(vec![
                    AgentEvent::ToolCallStart {
                        id: "t1".into(),
                        name: "propose_expense".into(),
                    },
                    AgentEvent::ToolCallEnd {
                        id: "t1".into(),
                        input: json!({}),
                    },
                    AgentEvent::Stop {
                        reason: StopReason::ToolUse,
                        rounds: 0,
                    },
                ]),
                MockRound::events(vec![AgentEvent::Stop {
                    reason: StopReason::EndTurn,
                    rounds: 0,
                }]),
            ]);
            let agent = loop_with(adapter, dispatcher.clone(), TurnBudget::default());
            let mut session = session(messages);
            let mut events = Vec::new();

            let reason = agent.run_inner(&mut session, &mut events).await.unwrap();

            assert_eq!(reason, StopReason::EndTurn);
            assert!(dispatcher.calls.borrow().is_empty());
            assert!(events.iter().any(|event| matches!(
                event,
                AgentEvent::ToolResult { output, .. }
                    if output["code"] == "proposal_cap_exceeded"
            )));
        });
    }

    #[test]
    fn turn_budget_timeout_emits_error_then_done() {
        futures_executor::block_on(async {
            let dispatcher = Rc::new(RecordingDispatcher::default());
            let adapter = MockAdapter::scripted(vec![MockRound::never()]);
            let agent = loop_with(
                adapter,
                dispatcher,
                TurnBudget {
                    max_rounds: 3,
                    turn_timeout_ms: 0,
                },
            );
            let mut session = session(vec![user_message("hi")]);
            let mut events = Vec::new();

            let reason = agent.run(&mut session, &mut events).await.unwrap();

            assert_eq!(reason, StopReason::Error);
            assert!(matches!(
                events.as_slice(),
                [
                    AgentEvent::Error { code, .. },
                    AgentEvent::Stop { reason: StopReason::Error, .. }
                ] if code == "chat_timeout"
            ));
        });
    }

    #[test]
    fn provider_error_emits_error_then_done() {
        futures_executor::block_on(async {
            let dispatcher = Rc::new(RecordingDispatcher::default());
            let adapter = MockAdapter::scripted(vec![MockRound::error("upstream failed")]);
            let agent = loop_with(adapter, dispatcher, TurnBudget::default());
            let mut session = session(vec![user_message("hi")]);
            let mut events = Vec::new();

            let reason = agent.run_inner(&mut session, &mut events).await.unwrap();

            assert_eq!(reason, StopReason::Error);
            assert!(matches!(
                events.as_slice(),
                [
                    AgentEvent::Error { code, message },
                    AgentEvent::Stop { reason: StopReason::Error, .. }
                ] if code == "provider_error" && message.contains("upstream failed")
            ));
        });
    }
}
