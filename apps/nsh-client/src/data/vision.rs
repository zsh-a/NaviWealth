//! Thin NSH platform transport over the shared LLM client and meal core.

use std::{future::Future, pin::Pin, rc::Rc, sync::OnceLock, time::Duration};

use futures::stream::{self, Iter};
use health_core::{
    consent::{Consent, UploadTarget},
    photo::{MealPhoto, PhotoRole},
    recognition::{Lang, MealEstimate, RecognitionError, recognize_meal},
};
use llm_client::{Bytes, CapabilityCache, Client, HttpResponse, Timeouts, Transport};
use llm_protocol::{Endpoint, HttpRequest, LlmError, LlmRequest, Protocol};
use nsh_core::prelude::{fetch, timer};
use serde_json::json;

use super::meals::new_food_id;
use crate::domain::{
    ProviderError, VisionFailure,
    account::{ModelAccount, Provider},
};

pub const RECOGNIZE_TIMEOUT: Duration = Duration::from_secs(150);
pub const PING_TIMEOUT: Duration = Duration::from_secs(60);

static CAPABILITIES: OnceLock<CapabilityCache> = OnceLock::new();

type Body = Iter<std::vec::IntoIter<Result<Bytes, LlmError>>>;

/// NSH fetch is local to its engine thread and currently returns a whole body.
/// The client accepts that body as one chunk without requiring Tokio or TLS.
struct NshTransport {
    epoch: nsh_core::time::Instant,
}

impl NshTransport {
    fn new() -> Self {
        Self {
            epoch: nsh_core::time::now(),
        }
    }
}

impl Transport for NshTransport {
    type Body = Body;
    type SendFuture<'a> = Pin<Box<dyn Future<Output = Result<HttpResponse<Body>, LlmError>> + 'a>>;
    type SleepFuture<'a> = Pin<Box<dyn Future<Output = ()> + 'a>>;

    fn send(&self, request: HttpRequest) -> Self::SendFuture<'_> {
        Box::pin(async move {
            let mut http = nsh_core::platform::HttpRequest::new("POST", request.url);
            // Credentials must never follow a redirect to a different destination.
            http.follow_redirects = false;
            for (name, value) in request.headers {
                http = http.header(name, value);
            }
            let response = fetch(http.body(request.body)).await.map_err(|_| {
                LlmError::provider(
                    "network_error",
                    "The platform request failed",
                    // Whole-body NSH fetch cannot tell whether the provider
                    // already began replying. Leave replay to the user.
                    false,
                    json!({}),
                )
            })?;
            Ok(HttpResponse {
                status: response.status(),
                headers: response.head.headers,
                body: stream::iter(vec![Ok(Bytes::from(response.body))]),
            })
        })
    }

    fn sleep(&self, duration: Duration) -> Self::SleepFuture<'_> {
        Box::pin(async move {
            timer(duration).await;
        })
    }

    fn now(&self) -> Duration {
        self.epoch.elapsed()
    }
}

fn endpoint(account: &ModelAccount) -> Result<Endpoint, VisionFailure> {
    let protocol = match account.provider {
        Provider::Anthropic => Protocol::Anthropic,
        Provider::OpenAiCompatible => Protocol::OpenAiCompatible,
    };
    let provider = match account.provider {
        Provider::Anthropic => "anthropic",
        Provider::OpenAiCompatible => "openai",
    };
    Endpoint::new(
        protocol,
        provider,
        account.normalized_base_url(),
        &account.api_key,
    )
    .map_err(llm_failure)
}

pub fn upload_target(account: &ModelAccount) -> UploadTarget {
    let provider = match account.provider {
        Provider::Anthropic => "anthropic",
        Provider::OpenAiCompatible => "openai",
    };
    UploadTarget::new(provider, &account.normalized_base_url(), &account.model)
}

pub async fn recognize(
    account: ModelAccount,
    jpeg: Rc<Vec<u8>>,
    lang: Lang,
    consent: Consent,
) -> Result<MealEstimate, VisionFailure> {
    let client = Client::new(endpoint(&account)?, NshTransport::new())
        .with_capability_cache(CAPABILITIES.get_or_init(CapabilityCache::default).clone())
        .with_timeouts(Timeouts {
            total: RECOGNIZE_TIMEOUT,
            ..Timeouts::default()
        });
    let photos = [MealPhoto::new((*jpeg).clone(), PhotoRole::Overview, None)];
    let mut estimate = recognize_meal(&client, &account.model, &photos, &consent, lang, "")
        .await
        .map_err(recognition_failure)?;
    for food in &mut estimate.recognition.foods {
        food.id = new_food_id();
    }
    Ok(estimate)
}

pub async fn ping(account: ModelAccount) -> Result<(String, f64), VisionFailure> {
    let started = nsh_core::time::now();
    let request: LlmRequest = serde_json::from_value(json!({
        "protocol_version":"agent.v1", "provider": match account.provider {
            Provider::Anthropic => "anthropic", Provider::OpenAiCompatible => "openai"
        }, "model":account.model.trim(),
        "messages":[{"role":"user","content":"Reply with OK."}], "max_output_tokens":32
    }))
    .map_err(|_| VisionFailure::Unreadable)?;
    let client = Client::new(endpoint(&account)?, NshTransport::new()).with_timeouts(Timeouts {
        total: PING_TIMEOUT,
        ..Timeouts::default()
    });
    let response = client.complete(request).await.map_err(llm_failure)?;
    Ok((response.model, started.elapsed().as_secs_f64()))
}

fn recognition_failure(error: RecognitionError) -> VisionFailure {
    match error {
        RecognitionError::Truncated => VisionFailure::Truncated,
        RecognitionError::Refused => VisionFailure::Refused,
        RecognitionError::Photo(_) => VisionFailure::Photo,
        RecognitionError::Consent(_) => VisionFailure::Refused,
        RecognitionError::Llm(error) => llm_failure(error),
        _ => VisionFailure::Unreadable,
    }
}

fn llm_failure(error: LlmError) -> VisionFailure {
    let code = error.record.code.as_str();
    let status = error
        .record
        .details
        .get("status")
        .and_then(serde_json::Value::as_u64)
        .unwrap_or(0) as u16;
    if code.contains("timeout") {
        return VisionFailure::Timeout;
    }
    if code.contains("refusal") || code.contains("content_filter") {
        return VisionFailure::Refused;
    }
    if code.contains("network") || code.contains("transport") {
        return VisionFailure::Offline("Network request failed".into());
    }
    let problem = match status {
        401 => ProviderError::Unauthorized,
        403 => ProviderError::Forbidden,
        404 => ProviderError::NotFound,
        429 => ProviderError::RateLimited,
        503 | 529 => ProviderError::Overloaded,
        500..=599 => ProviderError::Server(status),
        400..=499 => ProviderError::Rejected {
            status,
            message: "The model rejected the request. Check the account and image support.".into(),
        },
        _ if code.contains("rate_limit") => ProviderError::RateLimited,
        _ => ProviderError::Decode,
    };
    VisionFailure::Provider(problem)
}
