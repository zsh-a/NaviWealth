use agent_llm::{
    AnthropicProvider, LlmProvider, LlmRequest, MockLlmProvider, OpenAiCompatibleProvider,
};
use anyhow::Result;
use serde_json::Value;

pub(super) fn profile_llm_provider(request: &LlmRequest) -> Result<Box<dyn LlmProvider>> {
    match request.provider.as_str() {
        "mock" => Ok(Box::new(MockLlmProvider::new(
            "mock",
            request.model.clone(),
            "mock response",
        ))),
        "openai" | "openai-compatible" => {
            let api_key = llm_metadata_string(request, "api_key")?;
            let base_url = llm_metadata_string(request, "base_url")
                .map(normalize_openai_base_url)
                .unwrap_or_else(|_| "https://api.openai.com/v1".to_owned());
            let provider =
                OpenAiCompatibleProvider::new(request.provider.clone(), base_url, api_key)
                    .map_err(llm_error_to_anyhow)?;
            Ok(Box::new(provider))
        }
        "anthropic" => {
            let api_key = llm_metadata_string(request, "api_key")?;
            let base_url = llm_metadata_string(request, "base_url")
                .unwrap_or_else(|_| "https://api.anthropic.com/v1".to_owned());
            let version = llm_metadata_string(request, "anthropic_version")
                .unwrap_or_else(|_| "2023-06-01".to_owned());
            let provider =
                AnthropicProvider::new(request.provider.clone(), base_url, api_key, version)
                    .map_err(llm_error_to_anyhow)?;
            Ok(Box::new(provider))
        }
        other => anyhow::bail!("unsupported LLM provider '{other}'"),
    }
}

pub(super) fn llm_error_to_anyhow(error: agent_llm::LlmError) -> anyhow::Error {
    anyhow::anyhow!(error.record.message.clone())
}

fn llm_metadata_string(request: &LlmRequest, key: &str) -> Result<String> {
    let value = request
        .metadata
        .get(key)
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_owned();
    if value.is_empty() {
        anyhow::bail!("LLM request metadata.{key} is required");
    }
    Ok(value)
}

fn normalize_openai_base_url(base_url: String) -> String {
    let base = base_url.trim().trim_end_matches('/').to_owned();
    if let Some(prefix) = base.strip_suffix("/v1/chat/completions") {
        return prefix.to_owned() + "/v1";
    }
    if let Some(prefix) = base.strip_suffix("/chat/completions") {
        return prefix.to_owned();
    }
    if base.ends_with("/v1") {
        base
    } else {
        base + "/v1"
    }
}
