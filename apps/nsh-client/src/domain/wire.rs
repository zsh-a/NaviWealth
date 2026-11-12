//! The two provider APIs on the wire: building a request and reading its
//! reply, with no I/O, so every shape is tested here and the app only
//! sends bytes through the platform's network stack.

use base64::Engine;
use serde_json::{Value, json};

use super::{
    account::{ModelAccount, Provider},
    recognition::{Lang, response_schema, system_prompt, user_text},
};

/// The Anthropic API version requests are written for.
pub const ANTHROPIC_VERSION: &str = "2026-10-21";
/// Room for the model's thinking and its JSON answer.
pub const ANTHROPIC_MAX_TOKENS: u32 = 16000;

/// An HTTP request, ready to send.
#[derive(Debug, Clone, PartialEq)]
pub struct WireRequest {
    pub url: String,
    pub headers: Vec<(String, String)>,
    pub body: Vec<u8>,
}

/// What to ask.
#[derive(Debug, Clone, Copy)]
pub enum Ask<'a> {
    /// Estimate the meal in this JPEG.
    Meal { jpeg: &'a [u8], lang: Lang },
    /// The smallest request that proves the account works.
    Ping,
}

/// The request asking `account` for `ask`; `structured` asks the provider
/// to enforce the JSON answer (a JSON Schema on Anthropic, JSON mode on
/// OpenAI-compatible servers).
pub fn build_request(account: &ModelAccount, ask: Ask<'_>, structured: bool) -> WireRequest {
    let base = account.normalized_base_url();
    let model = account.model.trim();
    let key = account.api_key.trim();
    let mut headers = vec![("content-type".to_owned(), "application/json".to_owned())];
    let (url, body) = match account.provider {
        Provider::Anthropic => {
            headers.push(("x-api-key".to_owned(), key.to_owned()));
            headers.push(("anthropic-version".to_owned(), ANTHROPIC_VERSION.to_owned()));
            (
                format!("{base}/messages"),
                anthropic_body(model, ask, structured),
            )
        }
        Provider::OpenAiCompatible => {
            if !key.is_empty() {
                headers.push(("authorization".to_owned(), format!("Bearer {key}")));
            }
            (
                format!("{base}/chat/completions"),
                openai_body(model, ask, structured),
            )
        }
    };
    WireRequest {
        url,
        headers,
        body: serde_json::to_vec(&body).unwrap_or_default(),
    }
}

fn anthropic_body(model: &str, ask: Ask<'_>, structured: bool) -> Value {
    match ask {
        Ask::Meal { jpeg, lang } => {
            let mut body = json!({
                "model": model,
                "max_tokens": ANTHROPIC_MAX_TOKENS,
                "system": system_prompt(lang),
                "messages": [{
                    "role": "user",
                    "content": [
                        {
                            "type": "image",
                            "source": { "type": "base64", "media_type": "image/jpeg", "data": encode(jpeg) }
                        },
                        { "type": "text", "text": user_text(lang) }
                    ]
                }]
            });
            if structured {
                body["output_config"] =
                    json!({ "format": { "type": "json_schema", "schema": response_schema() } });
            }
            body
        }
        Ask::Ping => json!({
            "model": model,
            "max_tokens": 1024,
            "messages": [{ "role": "user", "content": "Reply with the word OK." }]
        }),
    }
}

fn openai_body(model: &str, ask: Ask<'_>, structured: bool) -> Value {
    match ask {
        Ask::Meal { jpeg, lang } => {
            let mut body = json!({
                "model": model,
                "messages": [
                    { "role": "system", "content": system_prompt(lang) },
                    {
                        "role": "user",
                        "content": [
                            { "type": "text", "text": user_text(lang) },
                            {
                                "type": "image_url",
                                "image_url": { "url": format!("data:image/jpeg;base64,{}", encode(jpeg)) }
                            }
                        ]
                    }
                ]
            });
            if structured {
                body["response_format"] = json!({ "type": "json_object" });
            }
            body
        }
        Ask::Ping => json!({
            "model": model,
            "messages": [{ "role": "user", "content": "Reply with the word OK." }]
        }),
    }
}

fn encode(bytes: &[u8]) -> String {
    base64::engine::general_purpose::STANDARD.encode(bytes)
}

/// How the model's turn ended.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Stop {
    /// It finished.
    Complete,
    /// It ran out of output tokens: the answer is cut off.
    Truncated,
    /// It (or the provider's safety system) declined.
    Refused,
}

/// A reply's text.
#[derive(Debug, Clone, PartialEq)]
pub struct ModelReply {
    pub text: String,
    /// The model that answered, as the provider names it.
    pub model: Option<String>,
    pub stop: Stop,
}

/// Why a provider gave no usable reply.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ProviderError {
    /// 401: the key is wrong or revoked.
    Unauthorized,
    /// 403: the key may not use this model or feature.
    Forbidden,
    /// 404: the base URL or the model does not exist.
    NotFound,
    /// 429: too many requests, or the quota is used up.
    RateLimited,
    /// 503 / 529: the provider is overloaded.
    Overloaded,
    /// Another 5xx.
    Server(u16),
    /// The request was refused as invalid (400, 413, 422 …), with the
    /// provider's message: often a model that takes no images.
    Rejected { status: u16, message: String },
    /// A success whose body is not the API's shape.
    Decode,
}

/// Reads a provider's HTTP reply.
pub fn parse_reply(
    provider: Provider,
    status: u16,
    body: &str,
) -> Result<ModelReply, ProviderError> {
    if !(200..300).contains(&status) {
        return Err(status_error(status, body));
    }
    let value: Value = serde_json::from_str(body).map_err(|_| ProviderError::Decode)?;
    let model = value
        .get("model")
        .and_then(Value::as_str)
        .map(str::to_owned);
    match provider {
        Provider::Anthropic => {
            let blocks = value
                .get("content")
                .and_then(Value::as_array)
                .ok_or(ProviderError::Decode)?;
            let text = blocks
                .iter()
                .filter(|block| block.get("type").and_then(Value::as_str) == Some("text"))
                .filter_map(|block| block.get("text").and_then(Value::as_str))
                .collect::<Vec<_>>()
                .join("");
            let stop = match value.get("stop_reason").and_then(Value::as_str) {
                Some("max_tokens") => Stop::Truncated,
                Some("refusal") => Stop::Refused,
                _ => Stop::Complete,
            };
            Ok(ModelReply { text, model, stop })
        }
        Provider::OpenAiCompatible => {
            let choice = value
                .get("choices")
                .and_then(Value::as_array)
                .and_then(|choices| choices.first())
                .ok_or(ProviderError::Decode)?;
            let message = choice.get("message").ok_or(ProviderError::Decode)?;
            let text = match message.get("content") {
                Some(Value::String(text)) => text.clone(),
                Some(Value::Array(parts)) => parts
                    .iter()
                    .filter_map(|part| part.get("text").and_then(Value::as_str))
                    .collect::<Vec<_>>()
                    .join(""),
                _ => String::new(),
            };
            let refused = message.get("refusal").is_some_and(|r| !r.is_null());
            let stop = match choice.get("finish_reason").and_then(Value::as_str) {
                _ if refused => Stop::Refused,
                Some("length") => Stop::Truncated,
                Some("content_filter") => Stop::Refused,
                _ => Stop::Complete,
            };
            Ok(ModelReply { text, model, stop })
        }
    }
}

fn status_error(status: u16, body: &str) -> ProviderError {
    match status {
        401 => ProviderError::Unauthorized,
        403 => ProviderError::Forbidden,
        404 => ProviderError::NotFound,
        429 => ProviderError::RateLimited,
        503 | 529 => ProviderError::Overloaded,
        500..=599 => ProviderError::Server(status),
        _ => ProviderError::Rejected {
            status,
            message: error_message(body),
        },
    }
}

/// The provider's own words for an error (`error.message` in both APIs),
/// or the start of the body.
pub fn error_message(body: &str) -> String {
    let message = serde_json::from_str::<Value>(body).ok().and_then(|value| {
        value
            .pointer("/error/message")
            .or_else(|| value.get("message"))
            .and_then(Value::as_str)
            .map(str::to_owned)
    });
    let message = message.unwrap_or_else(|| body.trim().to_owned());
    message.chars().take(240).collect()
}

/// Whether a 400 says the provider does not take the structured-answer
/// option, so the request should be sent again without it.
pub fn rejects_structured_output(status: u16, body: &str) -> bool {
    if status != 400 {
        return false;
    }
    let body = body.to_ascii_lowercase();
    [
        "output_config",
        "response_format",
        "json_schema",
        "json_object",
        "structured output",
    ]
    .iter()
    .any(|word| body.contains(word))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn account(provider: Provider) -> ModelAccount {
        let mut account = ModelAccount::new(provider);
        account.api_key = "key-1".into();
        account.model = "vision-model".into();
        account
    }

    fn body(request: &WireRequest) -> Value {
        serde_json::from_slice(&request.body).unwrap()
    }

    fn header<'a>(request: &'a WireRequest, name: &str) -> Option<&'a str> {
        request
            .headers
            .iter()
            .find(|(n, _)| n == name)
            .map(|(_, v)| v.as_str())
    }

    #[test]
    fn anthropic_meal_request() {
        let jpeg = [0xff, 0xd8, 0xff];
        let request = build_request(
            &account(Provider::Anthropic),
            Ask::Meal {
                jpeg: &jpeg,
                lang: Lang::Zh,
            },
            true,
        );
        assert_eq!(request.url, "https://api.anthropic.com/v1/messages");
        assert_eq!(header(&request, "x-api-key"), Some("key-1"));
        assert_eq!(
            header(&request, "anthropic-version"),
            Some(ANTHROPIC_VERSION)
        );
        let body = body(&request);
        assert_eq!(body["model"], "vision-model");
        assert_eq!(body["max_tokens"], ANTHROPIC_MAX_TOKENS);
        let image = &body["messages"][0]["content"][0];
        assert_eq!(image["type"], "image");
        assert_eq!(image["source"]["media_type"], "image/jpeg");
        assert_eq!(image["source"]["data"], "/9j/");
        assert_eq!(body["output_config"]["format"]["type"], "json_schema");
        // The 2026-10-21 API rejects sampling parameters.
        assert!(body.get("temperature").is_none());
        let plain = build_request(
            &account(Provider::Anthropic),
            Ask::Meal {
                jpeg: &jpeg,
                lang: Lang::Zh,
            },
            false,
        );
        assert!(self::body(&plain).get("output_config").is_none());
    }

    #[test]
    fn openai_meal_request() {
        let request = build_request(
            &account(Provider::OpenAiCompatible),
            Ask::Meal {
                jpeg: &[1, 2, 3],
                lang: Lang::En,
            },
            true,
        );
        assert_eq!(request.url, "https://api.openai.com/v1/chat/completions");
        assert_eq!(header(&request, "authorization"), Some("Bearer key-1"));
        let body = body(&request);
        assert_eq!(body["messages"][0]["role"], "system");
        let image = &body["messages"][1]["content"][1];
        assert_eq!(image["image_url"]["url"], "data:image/jpeg;base64,AQID");
        assert_eq!(body["response_format"]["type"], "json_object");

        let mut keyless = account(Provider::OpenAiCompatible);
        keyless.api_key.clear();
        let ping = build_request(&keyless, Ask::Ping, false);
        assert!(header(&ping, "authorization").is_none());
    }

    #[test]
    fn reads_anthropic_replies() {
        let body = r#"{"model":"claude-opus-5-5","stop_reason":"end_turn","content":[
            {"type":"thinking","thinking":""},{"type":"text","text":"{\"foods\":"},{"type":"text","text":"[]}"}]}"#;
        let reply = parse_reply(Provider::Anthropic, 200, body).unwrap();
        assert_eq!(reply.text, "{\"foods\":[]}");
        assert_eq!(reply.model.as_deref(), Some("claude-opus-5-5"));
        assert_eq!(reply.stop, Stop::Complete);
        let cut = r#"{"stop_reason":"max_tokens","content":[]}"#;
        assert_eq!(
            parse_reply(Provider::Anthropic, 200, cut).unwrap().stop,
            Stop::Truncated
        );
        let refused = r#"{"stop_reason":"refusal","content":[]}"#;
        assert_eq!(
            parse_reply(Provider::Anthropic, 200, refused).unwrap().stop,
            Stop::Refused
        );
        assert_eq!(
            parse_reply(Provider::Anthropic, 200, "<html>"),
            Err(ProviderError::Decode)
        );
    }

    #[test]
    fn reads_openai_replies() {
        let body =
            r#"{"model":"m","choices":[{"finish_reason":"stop","message":{"content":"{}"}}]}"#;
        assert_eq!(
            parse_reply(Provider::OpenAiCompatible, 200, body)
                .unwrap()
                .text,
            "{}"
        );
        let parts = r#"{"choices":[{"finish_reason":"length","message":{"content":[{"type":"text","text":"{"}]}}]}"#;
        let reply = parse_reply(Provider::OpenAiCompatible, 200, parts).unwrap();
        assert_eq!((reply.text.as_str(), reply.stop), ("{", Stop::Truncated));
        let refusal =
            r#"{"choices":[{"finish_reason":"stop","message":{"content":null,"refusal":"no"}}]}"#;
        assert_eq!(
            parse_reply(Provider::OpenAiCompatible, 200, refusal)
                .unwrap()
                .stop,
            Stop::Refused
        );
        assert_eq!(
            parse_reply(Provider::OpenAiCompatible, 200, r#"{"choices":[]}"#),
            Err(ProviderError::Decode)
        );
    }

    #[test]
    fn maps_error_statuses() {
        let reply = |status| {
            parse_reply(
                Provider::Anthropic,
                status,
                r#"{"error":{"message":"No images for this model"}}"#,
            )
        };
        assert_eq!(reply(401), Err(ProviderError::Unauthorized));
        assert_eq!(reply(404), Err(ProviderError::NotFound));
        assert_eq!(reply(429), Err(ProviderError::RateLimited));
        assert_eq!(reply(529), Err(ProviderError::Overloaded));
        assert_eq!(reply(502), Err(ProviderError::Server(502)));
        assert_eq!(
            reply(400),
            Err(ProviderError::Rejected {
                status: 400,
                message: "No images for this model".into()
            })
        );
        assert_eq!(error_message("  plain failure  "), "plain failure");
    }

    #[test]
    fn notices_a_refused_structured_option() {
        assert!(rejects_structured_output(
            400,
            r#"{"error":{"message":"Unknown field: output_config"}}"#
        ));
        assert!(rejects_structured_output(
            400,
            "response_format is not supported"
        ));
        assert!(!rejects_structured_output(400, "image too large"));
        assert!(!rejects_structured_output(500, "response_format"));
    }
}
