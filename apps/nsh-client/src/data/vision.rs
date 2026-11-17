//! Thin NSH platform transport over the shared LLM client and meal core.

use std::{future::Future, pin::Pin, rc::Rc, sync::OnceLock, time::Duration};

use futures::stream::{self, Iter};
use llm_client::{Bytes, CapabilityCache, Client, HttpResponse, Timeouts, Transport};
use llm_protocol::{Endpoint, HttpRequest, LlmError, LlmRequest, Protocol};
use navi_health::{
    consent::{Consent, UploadTarget},
    photo::{MealPhoto, PhotoRole},
    recognition::{Lang, MealEstimate, RecognitionError, recognize_meal},
};
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

/// Exactly one owner-initiated request produces either a draft or a suspended
/// ask_user interaction. The host never executes arbitrary model tools.
#[derive(Debug)]
pub enum CaptureResponse {
    Records {
        records: Vec<crate::domain::capture::Record>,
        questions: Vec<crate::domain::capture::Question>,
        reply: String,
        model: String,
    },
    AskUser {
        request: crate::domain::capture::AskUser,
        model: String,
    },
}

pub async fn recognize_record(
    account: ModelAccount,
    draft: crate::domain::capture::Draft,
    images: Vec<(String, Vec<u8>)>,
    lang: Lang,
    consent: Consent,
    context: serde_json::Value,
) -> Result<CaptureResponse, VisionFailure> {
    consent
        .check(&upload_target(&account))
        .map_err(|_| VisionFailure::Refused)?;
    let request = capture_request(&account, &draft, &images, lang, &context)?;
    let client = Client::new(endpoint(&account)?, NshTransport::new())
        .with_capability_cache(CAPABILITIES.get_or_init(CapabilityCache::default).clone())
        .with_timeouts(Timeouts {
            total: RECOGNIZE_TIMEOUT,
            ..Timeouts::default()
        });
    let response = client.complete(request).await.map_err(llm_failure)?;
    capture_response(response)
}

fn capture_request(
    account: &ModelAccount,
    draft: &crate::domain::capture::Draft,
    images: &[(String, Vec<u8>)],
    lang: Lang,
    context: &serde_json::Value,
) -> Result<LlmRequest, VisionFailure> {
    use crate::domain::capture;
    use llm_protocol::{LlmResponseFormat, PROTOCOL_VERSION};
    Ok(LlmRequest {
        protocol_version: PROTOCOL_VERSION.into(),
        provider: upload_target(account).provider,
        model: account.model.clone(),
        messages: capture_messages(draft, images, lang, context)?,
        temperature: None,
        effort: None,
        max_output_tokens: Some(8000),
        tools: vec![serde_json::from_value(json!({
            "name":"ask_user",
            "description":"Ask the owner to resolve a capture decision. Pause until the owner submits answers; this tool never writes records.",
            "input_schema":capture::ask_user_schema(),
            "risk":"read_only"
        })).map_err(|_| VisionFailure::Unreadable)?],
        response_format: Some(LlmResponseFormat::JsonSchema {
            name: "record_draft".into(),
            schema: capture::result_schema(),
            strict: Some(true),
        }),
        metadata: json!({"prompt_version":capture::PROMPT_VERSION}),
    })
}

fn capture_response(response: llm_protocol::LlmResponse) -> Result<CaptureResponse, VisionFailure> {
    use crate::domain::capture;
    use llm_protocol::{ContentBlock, LlmFinishReason};
    let model = response.model.chars().take(200).collect();
    match response.finish_reason {
        LlmFinishReason::ToolCall => {
            let original = response
                .metadata
                .get("anthropic_content")
                .cloned()
                .ok_or(VisionFailure::Unreadable)?;
            let blocks: Vec<ContentBlock> =
                serde_json::from_value(original.clone()).map_err(|_| VisionFailure::Unreadable)?;
            let mut call = None;
            for block in &blocks {
                block.validate().map_err(|_| VisionFailure::Unreadable)?;
                match block {
                    ContentBlock::ToolUse { id, name, input }
                        if name == "ask_user" && call.is_none() =>
                    {
                        call = Some((id, input));
                    }
                    ContentBlock::Text { .. }
                    | ContentBlock::Thinking { .. }
                    | ContentBlock::RedactedThinking { .. } => {}
                    _ => return Err(VisionFailure::Unreadable),
                }
            }
            let (id, input) = call.ok_or(VisionFailure::Unreadable)?;
            let request = capture::AskUser::parse(id, input, original)
                .map_err(|_| VisionFailure::Unreadable)?;
            Ok(CaptureResponse::AskUser { request, model })
        }
        LlmFinishReason::Stop => {
            // Never silently discard tool calls from a provider with an
            // inconsistent finish reason.
            if response
                .metadata
                .get("anthropic_content")
                .and_then(serde_json::Value::as_array)
                .is_some_and(|blocks| blocks.iter().any(|block| block["type"] == "tool_use"))
            {
                return Err(VisionFailure::Unreadable);
            }
            let reply = response
                .object
                .map(|v| v.to_string())
                .unwrap_or(response.content);
            let (records, questions) =
                capture::parse(&reply).map_err(|_| VisionFailure::Unreadable)?;
            Ok(CaptureResponse::Records {
                records,
                questions,
                reply,
                model,
            })
        }
        LlmFinishReason::Length => Err(VisionFailure::Truncated),
        LlmFinishReason::ContentFilter => Err(VisionFailure::Refused),
        _ => Err(VisionFailure::Unreadable),
    }
}

/// Rebuild the conversation with each image attached to its original owner
/// message. File names are local references and never sent to the provider.
fn capture_messages(
    draft: &crate::domain::capture::Draft,
    images: &[(String, Vec<u8>)],
    lang: Lang,
    context: &serde_json::Value,
) -> Result<Vec<llm_protocol::LlmMessage>, VisionFailure> {
    use crate::domain::capture::{self, Turn};
    use llm_protocol::{ContentBlock, LlmMessage, LlmRole};
    let mut draft = draft.clone();
    if draft.transcript.is_empty() {
        draft.transcript.push(Turn::Owner {
            text: draft.input.clone(),
            photo: draft.photo.is_some(),
            images: draft.staged_images(),
        });
    }
    let mut messages = Vec::with_capacity(draft.transcript.len() + 1);
    messages.push(LlmMessage {
        role: LlmRole::System,
        content: capture::instructions(lang).into(),
        name: None,
        metadata: json!({}),
    });
    let mut first_owner = true;
    for (index, turn) in draft.transcript.iter().enumerate() {
        let message = match turn {
            Turn::Owner { text, .. } => {
                let mut content = Vec::new();
                for name in draft.turn_images(index) {
                    let bytes = images
                        .iter()
                        .find(|(file, _)| file == &name)
                        .map(|(_, bytes)| bytes)
                        .ok_or(VisionFailure::Photo)?;
                    let mime = if bytes.starts_with(b"\x89PNG\r\n\x1a\n") {
                        "image/png"
                    } else {
                        "image/jpeg"
                    };
                    content.push(ContentBlock::image(mime, bytes.clone()));
                }
                let text = if first_owner {
                    json!({"input":text,"context":context})
                } else {
                    json!({"message":text})
                };
                first_owner = false;
                content.push(ContentBlock::Text {
                    text: text.to_string(),
                });
                LlmMessage {
                    role: LlmRole::User,
                    content: content.into(),
                    name: None,
                    metadata: json!({}),
                }
            }
            Turn::AskUser { request } => {
                let blocks: Vec<ContentBlock> = serde_json::from_value(request.blocks.clone())
                    .map_err(|_| VisionFailure::Unreadable)?;
                LlmMessage {
                    role: LlmRole::Assistant,
                    content: blocks.into(),
                    name: None,
                    metadata: json!({}),
                }
            }
            Turn::ToolAnswer {
                call_id,
                answers,
                text,
                ..
            } => {
                // Keep result before supplemental images. The OpenAI adapter
                // otherwise reorders mixed user content ahead of tool results.
                messages.push(LlmMessage {
                    role: LlmRole::User,
                    content: vec![ContentBlock::ToolResult {
                        tool_use_id: call_id.clone(),
                        content: json!(json!({"answers":answers,"message":text}).to_string()),
                        is_error: None,
                    }]
                    .into(),
                    name: None,
                    metadata: json!({}),
                });
                let mut content = Vec::new();
                for name in draft.turn_images(index) {
                    let bytes = images
                        .iter()
                        .find(|(file, _)| file == &name)
                        .map(|(_, bytes)| bytes)
                        .ok_or(VisionFailure::Photo)?;
                    let mime = if bytes.starts_with(b"\x89PNG\r\n\x1a\n") {
                        "image/png"
                    } else {
                        "image/jpeg"
                    };
                    content.push(ContentBlock::image(mime, bytes.clone()));
                }
                if content.is_empty() {
                    continue;
                }
                content.push(ContentBlock::Text {
                    text: json!({"message":"Supporting images for the preceding ask_user answer."})
                        .to_string(),
                });
                LlmMessage {
                    role: LlmRole::User,
                    content: content.into(),
                    name: None,
                    metadata: json!({}),
                }
            }
            Turn::Assistant { reply, .. } => LlmMessage {
                role: LlmRole::Assistant,
                content: reply.clone().into(),
                name: None,
                metadata: json!({}),
            },
        };
        messages.push(message);
    }
    Ok(messages)
}

#[cfg(test)]
mod capture_tests {
    use super::*;
    use crate::domain::capture::Turn;
    use llm_protocol::{ContentBlock, ImageSource};

    fn ask_input() -> serde_json::Value {
        json!({"questions":[{"id":"portion","text":"How much did you eat?",
            "reason":"The package size does not establish consumption.","required":true,
            "options":[{"id":"half","label":"Half","description":"100 grams"},
                {"id":"whole","label":"All","description":"200 grams"}]}]})
    }

    fn test_account(provider: Provider) -> ModelAccount {
        let mut account = ModelAccount::new(provider);
        account.api_key = "test-key".into();
        account.model = "test-model".into();
        account
    }

    fn decoded_call(
        provider: Provider,
        calls: serde_json::Value,
    ) -> Result<CaptureResponse, VisionFailure> {
        let account = test_account(provider);
        let draft = super::super::capture::new();
        let request = capture_request(&account, &draft, &[], Lang::En, &json!({})).unwrap();
        let body = if provider == Provider::Anthropic {
            json!({"model":"test-model","stop_reason":"tool_use","content":calls})
        } else {
            let calls: Vec<_> = calls
                .as_array()
                .unwrap()
                .iter()
                .map(|call| {
                    json!({
                "id":call["id"],"type":"function","function":{
                    "name":call["name"],"arguments":call["input"].to_string()}})
                })
                .collect();
            json!({"model":"test-model","choices":[{"message":{"content":null,
                "tool_calls":calls},"finish_reason":"tool_calls"}]})
        };
        let decoded = llm_protocol::decode(
            &endpoint(&account).unwrap(),
            &request,
            200,
            &[],
            &serde_json::to_vec(&body).unwrap(),
        )
        .unwrap();
        capture_response(decoded)
    }

    #[test]
    fn both_provider_wire_formats_suspend_on_a_pure_ask_user_call() {
        for provider in [Provider::Anthropic, Provider::OpenAiCompatible] {
            let call =
                json!({"type":"tool_use","id":"ask-1","name":"ask_user","input":ask_input()});
            let CaptureResponse::AskUser { request, .. } =
                decoded_call(provider, json!([call])).unwrap()
            else {
                panic!("tool call must suspend capture");
            };
            assert_eq!(request.call_id, "ask-1");
            assert_eq!(request.questions.len(), 1);
            assert_eq!(request.questions[0].options[0].label, "Half");
        }
    }

    #[test]
    fn original_signed_assistant_blocks_are_preserved_for_resume() {
        let blocks = json!([
            {"type":"thinking","thinking":"Check consumption.","signature":"signed-provider-block"},
            {"type":"text","text":"Please confirm the portion."},
            {"type":"tool_use","id":"ask-signed","name":"ask_user","input":ask_input()}
        ]);
        let CaptureResponse::AskUser { request, .. } =
            decoded_call(Provider::Anthropic, blocks.clone()).unwrap()
        else {
            panic!("ask_user");
        };
        assert_eq!(request.blocks, blocks);
        let mut draft = super::super::capture::new();
        draft.transcript = vec![Turn::AskUser { request }];
        let messages = capture_messages(&draft, &[], Lang::En, &json!({})).unwrap();
        assert_eq!(messages[1].content.to_value(), blocks);
    }

    #[test]
    fn unsupported_or_multiple_tool_calls_are_never_executed() {
        for provider in [Provider::Anthropic, Provider::OpenAiCompatible] {
            let call =
                json!({"type":"tool_use","id":"ask-1","name":"ask_user","input":ask_input()});
            assert!(decoded_call(provider, json!([call.clone(), call.clone()])).is_err());
            let mut unknown = call.clone();
            unknown["name"] = json!("save_records");
            assert!(decoded_call(provider, json!([unknown])).is_err());
            let mut invalid = call;
            invalid["input"]["questions"] = json!([]);
            assert!(decoded_call(provider, json!([invalid])).is_err());
        }
    }

    #[test]
    fn answers_replay_as_tool_results_before_supporting_images_on_both_wires() {
        use crate::domain::capture::AskAnswer;
        let call = json!({"type":"tool_use","id":"ask-1","name":"ask_user","input":ask_input()});
        let CaptureResponse::AskUser { request: ask, .. } =
            decoded_call(Provider::Anthropic, json!([call])).unwrap()
        else {
            panic!("ask_user");
        };
        let mut draft = super::super::capture::new();
        draft.transcript = vec![
            Turn::Owner {
                text: "Lunch".into(),
                photo: false,
                images: Vec::new(),
            },
            Turn::AskUser { request: ask },
            Turn::ToolAnswer {
                call_id: "ask-1".into(),
                answers: vec![AskAnswer {
                    question_id: "portion".into(),
                    option_id: Some("half".into()),
                    text: String::new(),
                }],
                text: "Half the package".into(),
                images: vec!["local-secret-filename.png".into()],
            },
        ];
        let images = vec![(
            "local-secret-filename.png".into(),
            b"\x89PNG\r\n\x1a\n".to_vec(),
        )];
        for provider in [Provider::Anthropic, Provider::OpenAiCompatible] {
            let account = test_account(provider);
            let request = capture_request(&account, &draft, &images, Lang::En, &json!({})).unwrap();
            assert_eq!(request.tools.len(), 1);
            assert_eq!(request.tools[0].name, "ask_user");
            let wire = llm_protocol::encode(
                &endpoint(&account).unwrap(),
                &request,
                false,
                llm_protocol::StructuredMode::Native,
            )
            .unwrap();
            let body: serde_json::Value = serde_json::from_slice(&wire.body).unwrap();
            assert!(!body.to_string().contains("local-secret-filename"));
            let messages = body["messages"].as_array().unwrap();
            if provider == Provider::Anthropic {
                assert_eq!(messages[1]["content"][0]["type"], "tool_use");
                assert_eq!(messages[2]["content"][0]["tool_use_id"], "ask-1");
                let result: serde_json::Value =
                    serde_json::from_str(messages[2]["content"][0]["content"].as_str().unwrap())
                        .unwrap();
                assert_eq!(result["answers"][0]["question_id"], "portion");
                assert_eq!(result["answers"][0]["option_id"], "half");
                assert_eq!(messages[3]["content"][0]["type"], "image");
            } else {
                assert_eq!(messages[2]["role"], "assistant");
                assert_eq!(messages[2]["tool_calls"][0]["id"], "ask-1");
                assert_eq!(messages[3]["role"], "tool");
                assert_eq!(messages[3]["tool_call_id"], "ask-1");
                let result: serde_json::Value =
                    serde_json::from_str(messages[3]["content"].as_str().unwrap()).unwrap();
                assert_eq!(result["answers"][0]["option_id"], "half");
                assert_eq!(messages[4]["role"], "user");
                assert_eq!(messages[4]["content"][0]["type"], "image_url");
            }
        }
    }

    #[test]
    fn followup_images_replay_on_their_owner_turn_with_correct_mime() {
        let mut draft = super::super::capture::new();
        draft.photo = Some("overview.jpg".into());
        draft.transcript = vec![
            Turn::Owner {
                text: "Lunch".into(),
                photo: true,
                images: Vec::new(),
            },
            Turn::Assistant {
                reply: "{\"records\":[],\"questions\":[]}".into(),
                records: 0,
                questions: Vec::new(),
            },
            Turn::Owner {
                text: String::new(),
                photo: true,
                images: vec!["label.png".into()],
            },
        ];
        let images = vec![
            ("overview.jpg".into(), vec![0xff, 0xd8]),
            ("label.png".into(), b"\x89PNG\r\n\x1a\n".to_vec()),
        ];
        let messages = capture_messages(&draft, &images, Lang::En, &json!({})).unwrap();
        for (index, mime, bytes) in [
            (1, "image/jpeg", &images[0].1),
            (3, "image/png", &images[1].1),
        ] {
            let blocks = messages[index].content.blocks().unwrap();
            assert_eq!(blocks.len(), 2);
            match &blocks[0] {
                ContentBlock::Image {
                    source: ImageSource::Base64 { media_type, data },
                } => {
                    assert_eq!(media_type, mime);
                    assert_eq!(data, bytes);
                }
                other => panic!("unexpected image block: {other:?}"),
            }
        }
        assert!(capture_messages(&draft, &images[..1], Lang::En, &json!({})).is_err());
        let replay = capture_messages(&draft, &images, Lang::En, &json!({})).unwrap();
        assert_eq!(
            serde_json::to_value(&messages).unwrap(),
            serde_json::to_value(&replay).unwrap()
        );
    }
}
