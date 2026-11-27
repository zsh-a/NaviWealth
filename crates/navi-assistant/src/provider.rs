use std::sync::Arc;

use rpi_ai::{
    Model, Provider as PiProvider,
    providers::{
        anthropic::AnthropicProvider, openai_completions::OpenAiCompletionsProvider,
        openai_responses::OpenAiResponsesProvider,
    },
    types::Api,
};

use crate::{Config, Provider};

pub(crate) fn build(config: &Config) -> Result<(Model, Arc<dyn PiProvider>), String> {
    if (config.provider == Provider::Anthropic && config.api_key.trim().is_empty())
        || config.model.trim().is_empty()
        || config.model.len() > 256
    {
        return Err("assistant_configuration".into());
    }
    let base = normalize_base(config.provider, &config.base_url)?;
    let api = match config.provider {
        Provider::Anthropic => Api::AnthropicMessages,
        Provider::OpenAiCompatible => Api::OpenaiCompletions,
        Provider::OpenAiResponses => Api::OpenaiResponses,
    };
    let mut model = Model::new(&config.model, &config.model, api, "navi-owned", base);
    model.context_window = 32_768;
    model.max_tokens = config.limits.output_tokens.clamp(256, 16_384);
    let client = reqwest::Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .connect_timeout(std::time::Duration::from_secs(20))
        .timeout(config.limits.timeout)
        .build()
        .map_err(|_| "assistant_configuration")?;
    let key = (!config.api_key.trim().is_empty()).then(|| config.api_key.clone());
    if config.provider == Provider::OpenAiResponses && key.is_none() {
        // v0.29.0 Responses requires an auth header name even for an anonymous
        // server. An explicitly empty value satisfies that local check without
        // manufacturing a credential or consulting OPENAI_API_KEY. Unlike the
        // Chat provider, this version cannot omit the header entirely.
        model.headers = Some(std::collections::BTreeMap::from([(
            "Authorization".into(),
            String::new(),
        )]));
    }
    let models = vec![model.clone()];
    let provider: Arc<dyn PiProvider> = match config.provider {
        Provider::Anthropic => Arc::new(AnthropicProvider::with_models_without_env_api_key(
            key, client, models,
        )),
        Provider::OpenAiCompatible if key.is_none() => Arc::new(
            OpenAiCompletionsProvider::with_models_without_auth("navi-owned", client, models),
        ),
        Provider::OpenAiCompatible => {
            Arc::new(OpenAiCompletionsProvider::with_models_without_env_api_key(
                "navi-owned",
                key,
                client,
                models,
            ))
        }
        Provider::OpenAiResponses => {
            Arc::new(OpenAiResponsesProvider::with_models_without_env_api_key(
                "navi-owned",
                key,
                client,
                models,
            ))
        }
    };
    Ok((model, provider))
}

fn normalize_base(provider: Provider, base: &str) -> Result<String, String> {
    let url = url::Url::parse(base.trim()).map_err(|_| "assistant_configuration")?;
    // The host owns endpoint consent, including explicit HTTP on the owner's
    // LAN. This is not a model-selected web-fetch URL. Never downgrade HTTPS.
    if !matches!(url.scheme(), "https" | "http")
        || url.host_str().is_none()
        || !url.username().is_empty()
        || url.password().is_some()
        || url.query().is_some()
        || url.fragment().is_some()
    {
        return Err("assistant_configuration".into());
    }
    let base = url.as_str().trim_end_matches('/');
    // pi-rust's Anthropic adapter appends /v1/messages itself; the two OpenAI
    // adapters accept both a root and a /v1 prefix.
    Ok(if provider == Provider::Anthropic {
        base.strip_suffix("/v1").unwrap_or(base)
    } else {
        base
    }
    .into())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn owner_profile_prefixes_and_credential_boundaries() {
        assert_eq!(
            normalize_base(Provider::Anthropic, "https://example.com/proxy/v1/").unwrap(),
            "https://example.com/proxy"
        );
        for provider in [Provider::OpenAiCompatible, Provider::OpenAiResponses] {
            assert_eq!(
                normalize_base(provider, "https://example.com/proxy/v1/").unwrap(),
                "https://example.com/proxy/v1"
            );
        }
        for bad in [
            "https://secret@example.com/v1",
            "https://example.com/v1?key=secret",
            "file:///tmp/model",
        ] {
            assert!(normalize_base(Provider::Anthropic, bad).is_err());
        }
        assert!(normalize_base(Provider::OpenAiCompatible, "http://127.0.0.1:1234/v1").is_ok());
        assert!(normalize_base(Provider::OpenAiCompatible, "http://192.168.1.2:1234/v1").is_ok());
    }
}
