use std::sync::Arc;

use agent_llm::{
    AnthropicProvider, LlmProvider, MockLlmProvider, OllamaProvider, OpenAiCompatibleProvider,
};
use miette::{Result, miette};

#[derive(Debug, Clone)]
pub(crate) struct ChatLlmOptions {
    pub(crate) provider: String,
    pub(crate) model: String,
    pub(crate) mock_response: String,
    pub(crate) api_base_url: Option<String>,
    pub(crate) api_key_env: String,
    pub(crate) anthropic_version: String,
    pub(crate) temperature: Option<f32>,
    pub(crate) max_output_tokens: Option<u32>,
    pub(crate) max_tool_rounds: u32,
}

pub(crate) fn provider_from_options(options: &ChatLlmOptions) -> Result<Arc<dyn LlmProvider>> {
    match options.provider.as_str() {
        "mock" => Ok(Arc::new(MockLlmProvider::new(
            "mock",
            options.model.clone(),
            options.mock_response.clone(),
        ))),
        "openai-compatible" | "openai" => {
            let base_url = options.api_base_url.clone().ok_or_else(|| {
                miette!(
                    "--api-base-url or OPENAI_BASE_URL is required for provider '{}'",
                    options.provider
                )
            })?;
            let api_key = std::env::var(&options.api_key_env).map_err(|_| {
                miette!(
                    "environment variable {} is required for provider '{}'",
                    options.api_key_env,
                    options.provider
                )
            })?;
            OpenAiCompatibleProvider::new(options.provider.clone(), base_url, api_key)
                .map(|provider| Arc::new(provider) as Arc<dyn LlmProvider>)
                .map_err(|err| miette!(err.record.message))
        }
        "anthropic" => {
            let base_url = options
                .api_base_url
                .clone()
                .or_else(|| std::env::var("ANTHROPIC_BASE_URL").ok())
                .unwrap_or_else(|| "https://api.anthropic.com/v1".to_owned());
            let key_env = if options.api_key_env == "OPENAI_API_KEY" {
                "ANTHROPIC_API_KEY".to_owned()
            } else {
                options.api_key_env.clone()
            };
            let api_key = std::env::var(&key_env).map_err(|_| {
                miette!(
                    "environment variable {key_env} is required for provider '{}'",
                    options.provider
                )
            })?;
            AnthropicProvider::new(
                options.provider.clone(),
                base_url,
                api_key,
                options.anthropic_version.clone(),
            )
            .map(|provider| Arc::new(provider) as Arc<dyn LlmProvider>)
            .map_err(|err| miette!(err.record.message))
        }
        "ollama" | "local" => {
            let base_url = options
                .api_base_url
                .clone()
                .or_else(|| std::env::var("OLLAMA_BASE_URL").ok())
                .unwrap_or_else(|| "http://127.0.0.1:11434".to_owned());
            OllamaProvider::new(options.provider.clone(), base_url)
                .map(|provider| Arc::new(provider) as Arc<dyn LlmProvider>)
                .map_err(|err| miette!(err.record.message))
        }
        other => Err(miette!("unsupported LLM provider '{other}'")),
    }
}
