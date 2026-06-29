use std::sync::Arc;

use agent_core::{
    AgentError, AgentEvent, AgentServices, AgentStateStore, ProposalEnvelope, RunId, ToolContext,
    ToolError, ToolRegistry, TraceEvent, TraceSink, UserContext,
};
use async_trait::async_trait;
use serde_json::{Value, json};

pub struct BasicAgentServices {
    agent_id: String,
    run_id: RunId,
    user: Option<UserContext>,
    tools: Arc<dyn ToolRegistry>,
    state_store: Arc<dyn AgentStateStore>,
}

pub(crate) struct TracedAgentServices {
    pub(crate) inner: Arc<dyn AgentServices>,
    pub(crate) trace: Arc<dyn TraceSink>,
    pub(crate) run_id: RunId,
    pub(crate) agent_id: String,
}

impl BasicAgentServices {
    pub fn new(
        agent_id: impl Into<String>,
        run_id: RunId,
        user: Option<UserContext>,
        tools: Arc<dyn ToolRegistry>,
        state_store: Arc<dyn AgentStateStore>,
    ) -> Self {
        Self {
            agent_id: agent_id.into(),
            run_id,
            user,
            tools,
            state_store,
        }
    }
}

#[async_trait]
impl AgentServices for BasicAgentServices {
    async fn call_tool(&self, name: &str, input: Value) -> Result<Value, ToolError> {
        self.tools
            .call(
                name,
                input,
                ToolContext {
                    run_id: self.run_id.clone(),
                    agent_id: self.agent_id.clone(),
                    user: self.user.clone(),
                },
            )
            .await
    }

    async fn emit_event(&self, _event: AgentEvent) -> Result<(), AgentError> {
        Ok(())
    }

    async fn load_state(&self, key: &str) -> Result<Option<Value>, AgentError> {
        self.state_store
            .load(&self.agent_id, key)
            .await
            .map_err(|e| AgentError::internal(e.to_string()))
    }

    async fn save_state(&self, key: &str, value: Value) -> Result<(), AgentError> {
        self.state_store
            .save(&self.agent_id, key, value)
            .await
            .map_err(|e| AgentError::internal(e.to_string()))
    }
}

#[async_trait]
impl AgentServices for TracedAgentServices {
    async fn call_tool(&self, name: &str, input: Value) -> Result<Value, ToolError> {
        self.inner.call_tool(name, input).await
    }

    async fn emit_event(&self, event: AgentEvent) -> Result<(), AgentError> {
        self.inner.emit_event(event).await
    }

    async fn load_state(&self, key: &str) -> Result<Option<Value>, AgentError> {
        let started_at = std::time::Instant::now();
        match self.inner.load_state(key).await {
            Ok(value) => {
                let mut payload = json!({
                    "run_id": self.run_id.0.clone(),
                    "agent_id": self.agent_id.clone(),
                    "key": key,
                    "duration_ms": started_at.elapsed().as_millis(),
                    "status": "completed",
                    "found": value.is_some(),
                });
                if let Some(value) = &value {
                    payload["value_hash"] = json!(state_value_hash(value));
                    payload["value"] = value.clone();
                }
                self.trace
                    .emit(TraceEvent::new("state_read", payload))
                    .await?;
                Ok(value)
            }
            Err(error) => {
                self.trace
                    .emit(TraceEvent::new(
                        "state_read_failed",
                        json!({
                            "run_id": self.run_id.0.clone(),
                            "agent_id": self.agent_id.clone(),
                            "key": key,
                            "duration_ms": started_at.elapsed().as_millis(),
                            "status": "failed",
                            "error": error.record.clone(),
                        }),
                    ))
                    .await?;
                Err(error)
            }
        }
    }

    async fn save_state(&self, key: &str, value: Value) -> Result<(), AgentError> {
        let started_at = std::time::Instant::now();
        let value_hash = state_value_hash(&value);
        match self.inner.save_state(key, value.clone()).await {
            Ok(()) => {
                self.trace
                    .emit(TraceEvent::new(
                        "state_write",
                        json!({
                            "run_id": self.run_id.0.clone(),
                            "agent_id": self.agent_id.clone(),
                            "key": key,
                            "duration_ms": started_at.elapsed().as_millis(),
                            "status": "completed",
                            "value_hash": value_hash,
                            "value": value,
                        }),
                    ))
                    .await?;
                Ok(())
            }
            Err(error) => {
                self.trace
                    .emit(TraceEvent::new(
                        "state_write_failed",
                        json!({
                            "run_id": self.run_id.0.clone(),
                            "agent_id": self.agent_id.clone(),
                            "key": key,
                            "duration_ms": started_at.elapsed().as_millis(),
                            "status": "failed",
                            "value_hash": value_hash,
                            "error": error.record.clone(),
                        }),
                    ))
                    .await?;
                Err(error)
            }
        }
    }

    async fn create_proposal(&self, proposal: ProposalEnvelope) -> Result<(), AgentError> {
        let started_at = std::time::Instant::now();
        match self.inner.create_proposal(proposal.clone()).await {
            Ok(()) => {
                self.trace
                    .emit(TraceEvent::new(
                        "proposal_created",
                        json!({
                            "run_id": self.run_id.0.clone(),
                            "agent_id": self.agent_id.clone(),
                            "proposal_id": proposal.proposal_id.0,
                            "kind": proposal.kind,
                            "summary": proposal.summary,
                            "status": proposal.status,
                            "duration_ms": started_at.elapsed().as_millis(),
                        }),
                    ))
                    .await?;
                Ok(())
            }
            Err(error) => {
                self.trace
                    .emit(TraceEvent::new(
                        "proposal_create_failed",
                        json!({
                            "run_id": self.run_id.0.clone(),
                            "agent_id": self.agent_id.clone(),
                            "kind": proposal.kind,
                            "summary": proposal.summary,
                            "duration_ms": started_at.elapsed().as_millis(),
                            "error": error.record.clone(),
                        }),
                    ))
                    .await?;
                Err(error)
            }
        }
    }
}

fn state_value_hash(value: &Value) -> String {
    let bytes = serde_json::to_vec(value).unwrap_or_default();
    format!("blake3:{}", blake3::hash(&bytes).to_hex())
}
