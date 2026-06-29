use agent_core::PROTOCOL_VERSION;
use agent_llm::{
    AnthropicProvider, LlmProvider, LlmRequest, MockLlmProvider, OllamaProvider,
    OpenAiCompatibleProvider, user_message,
};
use miette::{Result, miette};
use serde_json::json;

use crate::print_json;

pub(crate) struct LlmCompleteOptions {
    pub(crate) prompt: String,
    pub(crate) provider: String,
    pub(crate) model: String,
    pub(crate) mock_response: String,
    pub(crate) api_base_url: Option<String>,
    pub(crate) api_key_env: String,
    pub(crate) temperature: Option<f32>,
    pub(crate) max_output_tokens: Option<u32>,
    pub(crate) anthropic_version: String,
}

pub(crate) async fn run_llm_complete(options: LlmCompleteOptions) -> Result<()> {
    let request = LlmRequest {
        protocol_version: PROTOCOL_VERSION.to_owned(),
        provider: options.provider.clone(),
        model: options.model.clone(),
        messages: vec![user_message(options.prompt)],
        temperature: options.temperature,
        max_output_tokens: options.max_output_tokens,
        tools: vec![],
        metadata: json!({"mock_response": options.mock_response}),
    };
    let response = match options.provider.as_str() {
        "mock" => {
            MockLlmProvider::new("mock", options.model, "mock response")
                .complete(request)
                .await
        }
        "openai-compatible" | "openai" => {
            let base_url = options.api_base_url.ok_or_else(|| {
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
                .map_err(|err| miette!(err.record.message))?
                .complete(request)
                .await
        }
        "anthropic" => {
            let base_url = options
                .api_base_url
                .or_else(|| std::env::var("ANTHROPIC_BASE_URL").ok())
                .unwrap_or_else(|| "https://api.anthropic.com/v1".to_owned());
            let key_env = if options.api_key_env == "OPENAI_API_KEY" {
                "ANTHROPIC_API_KEY".to_owned()
            } else {
                options.api_key_env
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
                options.anthropic_version,
            )
            .map_err(|err| miette!(err.record.message))?
            .complete(request)
            .await
        }
        "ollama" | "local" => {
            let base_url = options
                .api_base_url
                .or_else(|| std::env::var("OLLAMA_BASE_URL").ok())
                .unwrap_or_else(|| "http://127.0.0.1:11434".to_owned());
            OllamaProvider::new(options.provider.clone(), base_url)
                .map_err(|err| miette!(err.record.message))?
                .complete(request)
                .await
        }
        other => Err(agent_llm::LlmError::validation(format!(
            "unsupported LLM provider '{other}'"
        ))),
    }
    .map_err(|err| miette!(err.record.message))?;
    print_json(&response)
}
