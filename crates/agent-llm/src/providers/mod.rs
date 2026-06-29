mod anthropic;
mod ollama;
mod openai;

use serde_json::Value;

pub use anthropic::AnthropicProvider;
pub use ollama::OllamaProvider;
pub use openai::OpenAiCompatibleProvider;

use crate::types::LlmError;

fn llm_content_as_text<'a>(content: &'a Value, provider: &str) -> Result<&'a str, LlmError> {
    content.as_str().ok_or_else(|| {
        LlmError::validation(format!(
            "{provider} provider only supports text message content"
        ))
    })
}
