//! A mobile host boundary around pi-rust. No shell, file tools, environment
//! credentials or implicit persistence: the application owns all of those.

mod history;
mod provider;
mod runner;

use std::{sync::Arc, time::Duration};

use futures::future::BoxFuture;
use serde::{Deserialize, Serialize};
use serde_json::Value;

pub use runner::run;
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

/// Tool failures should be safe, user-facing codes, never raw network errors.
pub type ToolHandler =
    Arc<dyn Fn(String, Value) -> BoxFuture<'static, Result<Value, String>> + Send + Sync>;
pub type EventHandler = Arc<dyn Fn(Event) + Send + Sync>;

#[derive(Debug, Clone)]
pub enum Event {
    TextDelta(String),
    ToolStarted {
        name: String,
    },
    ToolFinished {
        name: String,
        is_error: bool,
    },
    /// Full transcript, including provider-native tool IDs and signatures.
    /// The host must persist this before accepting a subsequent turn.
    Checkpoint(Vec<Value>),
    /// Only the model's input window was shortened; the transcript remains intact.
    ContextTrimmed {
        messages: usize,
    },
}

#[derive(Debug, Clone)]
pub struct RunResult {
    pub history: Vec<Value>,
    pub text: String,
}
