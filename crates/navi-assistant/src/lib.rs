//! A mobile host boundary around pi-rust. No shell, file tools, environment
//! credentials or implicit persistence: the application owns all of those.

mod compaction;
mod diagnostics;
mod history;
mod provider;
pub mod recognition;
mod runner;

use std::{sync::Arc, time::Duration};

use futures::future::BoxFuture;
use serde::{Deserialize, Serialize};
use serde_json::Value;

pub use compaction::{ContextSummary, validate_context_summary};
pub use history::INTERRUPTED_TOOL_RESULT;
pub use rpi_agent::{AgentEvent, AgentMessage};
pub use rpi_ai::types::{AssistantMessageEvent, Content};
pub use runner::{run, run_multimodal};
pub use tokio_util::sync::CancellationToken;

/// Validate persisted provider history before accepting an imported backup.
/// Incomplete calls from an interrupted run are valid; continuation closes
/// them as errors. Unknown roles, malformed messages and orphan results fail.
pub fn validate_history(values: &[Value]) -> Result<(), String> {
    history::decode(values.to_vec()).map(|_| ())
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Provider {
    Anthropic,
    OpenAiCompatible,
    OpenAiResponses,
}

/// Intentionally has no Debug implementation: credentials never enter logs.
#[derive(Clone)]
pub struct Config {
    pub provider: Provider,
    pub base_url: String,
    pub api_key: String,
    pub model: String,
    pub system_prompt: String,
    pub limits: Limits,
    /// A previously saved, source-bound summary. Never an approved memory or instruction.
    pub context_summary: Option<ContextSummary>,
}

#[derive(Debug, Clone)]
pub struct Limits {
    pub max_turns: usize,
    pub timeout: Duration,
    /// Serialized provider context bound, in UTF-8 bytes (conservative for CJK).
    pub context_chars: usize,
    pub output_tokens: u64,
}

impl Default for Limits {
    fn default() -> Self {
        Self {
            max_turns: 8,
            timeout: Duration::from_secs(150),
            context_chars: 120_000,
            output_tokens: 4096,
        }
    }
}

#[derive(Debug, Clone)]
pub struct ToolSpec {
    pub name: String,
    pub description: String,
    pub parameters: Value,
}

/// A prepared, metadata-free image owned by the host. Image bytes are sent only
/// for this owner-submitted turn; checkpoints retain an omission notice instead
/// of base64. The host keeps file references and explicitly reattaches evidence.
#[derive(Clone)]
pub struct ImageInput {
    pub mime_type: String,
    pub data: Vec<u8>,
}

/// Tool failures should be safe, user-facing codes, never raw network errors.
pub type ToolHandler =
    Arc<dyn Fn(String, Value) -> BoxFuture<'static, Result<Value, String>> + Send + Sync>;
pub type EventHandler = Arc<dyn Fn(Event) + Send + Sync>;

#[derive(Debug, Clone)]
pub enum Event {
    /// Native pi-rust display events. Checkpoint and compaction notifications
    /// below belong to the local session lifecycle.
    Agent(Box<AgentEvent>),
    /// Full transcript, including provider-native tool IDs and signatures.
    /// The host must persist this before accepting a subsequent turn.
    Checkpoint(Vec<Value>),
    /// Only the model's input window was shortened; the transcript remains intact.
    ContextTrimmed {
        messages: usize,
    },
    SummaryStarted,
    /// Persist both fields atomically. The source prefix is part of this full history.
    SummaryUpdated {
        summary: ContextSummary,
        history: Vec<Value>,
    },
}

#[derive(Debug, Clone)]
pub struct RunResult {
    pub history: Vec<Value>,
    pub text: String,
    pub context_summary: Option<ContextSummary>,
}
