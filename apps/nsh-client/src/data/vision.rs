//! On-device recognition through the shared protocol client and owner profiles.

mod streaming;

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
            let status = response.status();
            let mut headers = response.head.headers;
            // Simple test/host adapters may omit the media type of a whole JSON response.
            if !headers
                .iter()
                .any(|(name, _)| name.eq_ignore_ascii_case("content-type"))
                && response
                    .body
                    .iter()
                    .copied()
                    .find(|byte| !byte.is_ascii_whitespace())
                    == Some(b'{')
            {
                headers.push(("content-type".into(), "application/json".into()));
            }
            Ok(HttpResponse {
                status,
                headers,
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
        Provider::OpenAiResponses => Protocol::OpenAiResponses,
    };
    let provider = match account.provider {
        Provider::Anthropic => "anthropic",
        Provider::OpenAiCompatible => "openai",
        Provider::OpenAiResponses => "openai_responses",
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
        Provider::OpenAiResponses => "openai_responses",
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
            Provider::Anthropic => "anthropic", Provider::OpenAiCompatible => "openai", Provider::OpenAiResponses => "openai_responses"
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
    // Runtime codes are bounded classifications, never response content. Keep
    // enough detail to distinguish provider errors from structured-output failures.
    let safe_code: String = code
        .chars()
        .filter(|c| c.is_ascii_alphanumeric() || *c == '_')
        .take(80)
        .collect();
    log::warn!("vision: model request failed (code={safe_code})");
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
    if code == "provider_stream_incomplete" {
        return VisionFailure::Truncated;
    }
    if code.contains("network")
        || code.contains("transport")
        || matches!(code, "provider_connect_failed" | "provider_request_failed")
    {
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
        provider_output: Option<serde_json::Value>,
    },
    AskUser {
        request: crate::domain::capture::AskUser,
        model: String,
    },
}

pub use streaming::{recognize_record_stream, use_host_capture_transport};

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

fn capture_response(
    response: llm_protocol::LlmResponse,
    image_count: usize,
) -> Result<CaptureResponse, VisionFailure> {
    use crate::domain::capture;
    use llm_protocol::{ContentBlock, LlmFinishReason};
    let model = response.model.chars().take(200).collect();
    let provider_output = response.metadata.get("responses_output").cloned();
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
            let mut request = capture::AskUser::parse(id, input, original)
                .map_err(|_| VisionFailure::Unreadable)?;
            request.provider_output = provider_output;
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
            if !capture::valid_meal_image_numbers(&records, image_count) {
                return Err(VisionFailure::Unreadable);
            }
            Ok(CaptureResponse::Records {
                records,
                questions,
                reply,
                model,
                provider_output,
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
    let sent_images = draft.sent_images();
    let mut first_owner = true;
    for (index, turn) in draft.transcript.iter().enumerate() {
        let turn_images = draft.turn_images(index);
        let image_numbers = turn_images
            .iter()
            .map(|name| {
                sent_images
                    .iter()
                    .position(|sent| sent == name)
                    .map(|n| n + 1)
                    .ok_or(VisionFailure::Photo)
            })
            .collect::<Result<Vec<_>, _>>()?;
        let message = match turn {
            Turn::Owner { text, .. } => {
                let mut content = Vec::new();
                for name in &turn_images {
                    let bytes = images
                        .iter()
                        .find(|(file, _)| file == name)
                        .map(|(_, bytes)| bytes)
                        .ok_or(VisionFailure::Photo)?;
                    let mime = if bytes.starts_with(b"\x89PNG\r\n\x1a\n") {
                        "image/png"
                    } else {
                        "image/jpeg"
                    };
                    content.push(ContentBlock::image(mime, bytes.clone()));
                }
                let mut text = if first_owner {
                    json!({"input":text,"context":context})
                } else {
                    json!({"message":text})
                };
                if !image_numbers.is_empty() {
                    text["image_numbers"] = json!(image_numbers);
                }
                first_owner = false;
                include_current_records(&mut text, &draft, index);
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
                    metadata: provider_metadata(&request.provider_output),
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
                let mut result = json!({"answers":answers,"message":text});
                include_current_records(&mut result, &draft, index);
                messages.push(LlmMessage {
                    role: LlmRole::User,
                    content: vec![ContentBlock::ToolResult {
                        tool_use_id: call_id.clone(),
                        content: json!(result.to_string()),
                        is_error: None,
                    }]
                    .into(),
                    name: None,
                    metadata: json!({}),
                });
                let mut content = Vec::new();
                for name in &turn_images {
                    let bytes = images
                        .iter()
                        .find(|(file, _)| file == name)
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
                    text: json!({"message":"Supporting images for the preceding ask_user answer.","image_numbers":image_numbers})
                        .to_string(),
                });
                LlmMessage {
                    role: LlmRole::User,
                    content: content.into(),
                    name: None,
                    metadata: json!({}),
                }
            }
            Turn::Assistant {
                reply,
                provider_output,
                ..
            } => LlmMessage {
                role: LlmRole::Assistant,
                content: reply.clone().into(),
                name: None,
                metadata: provider_metadata(provider_output),
            },
        };
        messages.push(message);
    }
    Ok(messages)
}

/// Keep provider-native history intact. A local edit or removal made since
/// the preceding proposal belongs only to the latest owner continuation.
fn include_current_records(
    payload: &mut serde_json::Value,
    draft: &crate::domain::capture::Draft,
    index: usize,
) {
    use crate::domain::capture::{Record, Turn};
    use navi_finance::{assets, holdings::format_units, money::format};
    if index + 1 != draft.transcript.len()
        || !draft.transcript[..index]
            .iter()
            .any(|turn| matches!(turn, Turn::Assistant { records, .. } if *records > 0))
    {
        return;
    }
    let records = draft.records.iter().map(|record| match record {
        Record::Money { day, draft } => json!({"kind":"money","day":day,"money":draft}),
        Record::Meal { day, slot, estimate,source_image } => {
            let foods: Vec<_> = estimate.foods.iter().map(|food| json!({"name":food.name,"grams":food.grams})).collect();
            json!({"kind":"meal","day":day,"slot":slot,"meal":{"title":estimate.title,"foods":foods,"source_image":source_image.number()}})
        }
        Record::Weight {day,kg} => json!({"kind":"weight","day":day,"weight_kg":kg}),
        Record::Trade {day,security,currency,kind,quantity,price,amount,fee,cash} => {
            let dividend = *kind == navi_finance::holdings::Kind::Dividend;
            json!({"kind":"trade","day":day,"trade":{"security":security,"currency":currency,"kind":kind,
                "quantity":(!dividend).then(|| format_units(*quantity)), "unit_price":(!dividend).then(|| format_units(*price)),
                "amount":dividend.then(|| format(*amount)),"fee":format(*fee),"cash":cash}})
        }
        Record::Balance {day,account,actual} => json!({"kind":"balance","day":day,
            "balance":{"account":account,"actual":format(assets::displayed(account,*actual))}}),
        Record::Price {day,security,currency,price} => json!({"kind":"price","day":day,
            "price":{"security":security,"currency":currency,"unit_price":format_units(*price)}}),
        Record::Note {day,text} => json!({"kind":"note","day":day,"note":text}),
    }).collect::<Vec<_>>();
    payload["current_records"] = json!(records);
}

fn provider_metadata(output: &Option<serde_json::Value>) -> serde_json::Value {
    output
        .as_ref()
        .map_or_else(|| json!({}), |output| json!({"responses_output": output}))
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
        let body =
            if provider == Provider::Anthropic {
                json!({"model":"test-model","stop_reason":"tool_use","content":calls})
            } else if provider == Provider::OpenAiResponses {
                let calls: Vec<_> = calls.as_array().unwrap().iter().map(|call| json!({
                "type":"function_call", "id":format!("fc_{}", call["id"].as_str().unwrap()),
                "call_id":call["id"], "name":call["name"],
                "arguments":call["input"].to_string(), "status":"completed"
            })).collect();
                json!({"id":"resp_test","model":"test-model","status":"completed","output":calls})
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
        capture_response(decoded, 0)
    }

    fn money_record() -> serde_json::Value {
        json!({"kind":"money","day":"2026-11-18","meal":null,
        "slot":null,"weight_kg":null,"trade":null,"balance":null,"price":null,"note":null,"evidence":[],"money":{
            "kind":"expense","amount":"32.00","currency":"CNY",
            "account":"资产:现金","other_account":null,
            "category":"支出:餐饮","time":null,"payee":"","note":"午饭"
        }})
    }

    #[test]
    fn native_anthropic_prompt_contains_the_exact_final_schema() {
        let account = test_account(Provider::Anthropic);
        let request = capture_request(
            &account,
            &super::super::capture::new(),
            &[],
            Lang::Zh,
            &json!({}),
        )
        .unwrap();
        let wire = llm_protocol::encode(
            &endpoint(&account).unwrap(),
            &request,
            false,
            llm_protocol::StructuredMode::Native,
        )
        .unwrap();
        let body: serde_json::Value = serde_json::from_slice(&wire.body).unwrap();
        assert!(body["output_config"]["format"]["schema"].is_object());
        let schema = body["system"]
            .as_str()
            .unwrap()
            .lines()
            .find_map(|line| line.strip_prefix("FINAL_RECORD_JSON_SCHEMA: "))
            .expect(
                "compatible providers may ignore output_config; the prompt must carry the schema",
            );
        let schema: serde_json::Value = serde_json::from_str(schema).unwrap();
        assert_eq!(schema, crate::domain::capture::result_schema());
        let money = &schema["properties"]["records"]["items"]["properties"]["money"]["anyOf"][0];
        for field in ["kind", "other_account", "payee"] {
            assert!(
                money["properties"].get(field).is_some(),
                "missing money.{field}"
            );
            assert!(
                money["required"]
                    .as_array()
                    .unwrap()
                    .contains(&json!(field))
            );
        }
    }

    #[test]
    fn anthropic_tool_answer_continues_to_a_schema_valid_money_draft() {
        use crate::domain::capture::AskAnswer;
        let call = json!({"type":"tool_use","id":"ask-account",
        "name":"ask_user","input":{"questions":[{
            "id":"account","text":"使用哪个账户？","reason":"付款账户必须明确。",
            "required":true,"options":[{
                "id":"cash","label":"资产:现金","description":"使用现金支付"}]
        }]}});
        let CaptureResponse::AskUser { request: ask, .. } =
            decoded_call(Provider::Anthropic, json!([call])).unwrap()
        else {
            panic!("ask_user must suspend");
        };
        let mut draft = super::super::capture::new();
        draft.transcript = vec![
            Turn::Owner {
                text: "记录午饭支出32元".into(),
                photo: false,
                images: vec![],
            },
            Turn::AskUser { request: ask },
            Turn::ToolAnswer {
                call_id: "ask-account".into(),
                answers: vec![AskAnswer {
                    question_id: "account".into(),
                    option_id: Some("cash".into()),
                    text: String::new(),
                }],
                text: "使用现金，餐饮支出".into(),
                images: vec![],
            },
        ];
        let account = test_account(Provider::Anthropic);
        let request = capture_request(&account, &draft, &[], Lang::Zh, &json!({})).unwrap();
        let ep = endpoint(&account).unwrap();
        let wire = llm_protocol::encode(&ep, &request, false, llm_protocol::StructuredMode::Native)
            .unwrap();
        let body: serde_json::Value = serde_json::from_slice(&wire.body).unwrap();
        assert_eq!(body["messages"][1]["content"][0]["id"], "ask-account");
        assert_eq!(
            body["messages"][2]["content"][0]["tool_use_id"],
            "ask-account"
        );
        let final_body = json!({"model":"test-model","stop_reason":"end_turn",
            "content":[{"type":"text","text":json!({"destination":null,"records":[money_record()]}).to_string()}]});
        let decoded = llm_protocol::decode(
            &ep,
            &request,
            200,
            &[],
            &serde_json::to_vec(&final_body).unwrap(),
        )
        .unwrap();
        let CaptureResponse::Records {
            records, questions, ..
        } = capture_response(decoded, 0).unwrap()
        else {
            panic!("final reply must produce records");
        };
        assert!(questions.is_empty());
        let [crate::domain::capture::Record::Money { draft, .. }] = records.as_slice() else {
            panic!("one money record expected");
        };
        assert_eq!(draft.amount.as_deref(), Some("32.00"));
        assert!(draft.valid());
        assert_eq!(draft.account.as_ref().unwrap().to_string(), "资产:现金");
        assert_eq!(draft.category.as_ref().unwrap().to_string(), "支出:餐饮");
    }

    #[test]
    fn anthropic_final_rejects_fences_and_incorrect_accounting_field_names() {
        let account = test_account(Provider::Anthropic);
        let request = capture_request(
            &account,
            &super::super::capture::new(),
            &[],
            Lang::Zh,
            &json!({}),
        )
        .unwrap();
        let valid = json!({"destination":null,"records":[money_record()]}).to_string();
        let mut wrong_shape = money_record();
        wrong_shape["money"]["type"] = wrong_shape["money"]["kind"].take();
        let money = wrong_shape["money"].as_object_mut().unwrap();
        for field in ["kind", "other_account", "payee"] {
            money.remove(field);
        }
        for (text, expected_code) in [
            (
                format!("```json\n{valid}\n```"),
                "structured_output_parse_failed",
            ),
            (
                json!({"destination":null,"records":[wrong_shape]}).to_string(),
                "structured_output_schema_validation_failed",
            ),
        ] {
            let body = json!({"model":"test-model","stop_reason":"end_turn",
                "content":[{"type":"text","text":text}]});
            let error = llm_protocol::decode(
                &endpoint(&account).unwrap(),
                &request,
                200,
                &[],
                &serde_json::to_vec(&body).unwrap(),
            )
            .unwrap_err();
            assert_eq!(error.record.code, expected_code);
        }
    }

    #[test]
    fn all_provider_wire_formats_suspend_on_a_pure_ask_user_call() {
        for provider in Provider::ALL {
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
    fn correction_replays_meal_image_number_and_rejects_a_staged_image_in_the_final_reply() {
        let mut draft = super::super::capture::new();
        let mut meal = money_record();
        meal["kind"] = json!("meal");
        meal["money"] = serde_json::Value::Null;
        meal["slot"] = json!("lunch");
        meal["meal"] = json!({"title":"Rice","source_image":2,"foods":[{"name":"rice","grams":100,"catalog_id":null,"confidence":"high","per_100g":{"kcal":100,"protein":2,"carbs":22,"fat":0,"fiber":null,"sugars":null,"sat_fat":null,"sodium_mg":null}}]});
        let reply = json!({"records":[meal.clone()],"destination":null}).to_string();
        draft.records = crate::domain::capture::parse(&reply).unwrap().0;
        draft.transcript = vec![
            Turn::Owner {
                text: "Weight and lunch".into(),
                photo: true,
                images: vec!["scale.jpg".into(), "lunch.jpg".into()],
            },
            Turn::Assistant {
                reply,
                records: 1,
                questions: vec![],
                provider_output: None,
            },
            Turn::Owner {
                text: "Only half that portion".into(),
                photo: false,
                images: vec![],
            },
        ];
        draft.attachments.push("staged.jpg".into());
        let account = test_account(Provider::Anthropic);
        let images = vec![
            ("scale.jpg".into(), vec![1]),
            ("lunch.jpg".into(), vec![2]),
            ("staged.jpg".into(), vec![3]),
        ];
        let request = capture_request(&account, &draft, &images, Lang::En, &json!({})).unwrap();
        let correction = request.messages.last().unwrap().content.blocks().unwrap();
        let ContentBlock::Text { text } = &correction[0] else {
            panic!("owner continuation")
        };
        let current: serde_json::Value = serde_json::from_str(text).unwrap();
        assert_eq!(current["current_records"][0]["meal"]["source_image"], 2);
        let decode = |number: serde_json::Value| {
            let mut proposed = meal.clone();
            proposed["meal"]["source_image"] = number;
            let final_body = json!({"model":"test-model","stop_reason":"end_turn","content":[{"type":"text","text":json!({"destination":null,"records":[proposed]}).to_string()}]});
            let decoded = llm_protocol::decode(
                &endpoint(&account).unwrap(),
                &request,
                200,
                &[],
                &serde_json::to_vec(&final_body).unwrap(),
            )
            .unwrap();
            capture_response(decoded, draft.sent_images().len())
        };
        assert!(matches!(decode(json!(3)), Err(VisionFailure::Unreadable)));
        for (number, expected) in [
            (json!(2), Some("lunch.jpg")),
            (serde_json::Value::Null, None),
        ] {
            let CaptureResponse::Records { records, .. } = decode(number).unwrap() else {
                panic!("meal result")
            };
            let [crate::domain::capture::Record::Meal { source_image, .. }] = records.as_slice()
            else {
                panic!("meal")
            };
            assert_eq!(
                draft.meal_photo(*source_image).unwrap().as_deref(),
                expected
            );
        }
    }

    #[test]
    fn only_latest_continuation_carries_the_owners_current_record_selection() {
        let mut draft = super::super::capture::new();
        let original = json!({"records":[money_record()],"destination":null}).to_string();
        draft.records = crate::domain::capture::parse(&original).unwrap().0;
        draft.transcript = vec![
            Turn::Owner {
                text: "lunch".into(),
                photo: false,
                images: vec![],
            },
            Turn::Assistant {
                reply: original.clone(),
                records: 1,
                questions: vec![],
                provider_output: None,
            },
            Turn::Owner {
                text: "use cash".into(),
                photo: false,
                images: vec![],
            },
        ];
        let crate::domain::capture::Record::Money { draft: changed, .. } = &mut draft.records[0]
        else {
            unreachable!()
        };
        changed.amount = Some("14.75".into());
        let sent = |draft: &crate::domain::capture::Draft| {
            let messages = capture_messages(draft, &[], Lang::En, &json!({})).unwrap();
            assert_eq!(messages[2].content.to_value(), json!(original));
            let content = messages.last().unwrap().content.blocks().unwrap();
            let ContentBlock::Text { text } = &content[0] else {
                unreachable!()
            };
            serde_json::from_str::<serde_json::Value>(text).unwrap()
        };
        assert_eq!(
            sent(&draft)["current_records"][0]["money"]["amount"],
            "14.75"
        );
        draft.records.clear();
        assert_eq!(sent(&draft)["current_records"], json!([]));
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
        for provider in Provider::ALL {
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
                provider_output: None,
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
    #[test]
    fn responses_native_reasoning_and_call_id_survive_persisted_resume() {
        use crate::domain::capture::{AskAnswer, Draft};
        let account = test_account(Provider::OpenAiResponses);
        let ep = endpoint(&account).unwrap();
        assert_eq!(upload_target(&account).provider, "openai_responses");
        let initial = super::super::capture::new();
        let request = capture_request(&account, &initial, &[], Lang::En, &json!({})).unwrap();
        let output = json!([
            {"type":"reasoning","id":"rs_1","summary":[],"encrypted_content":"opaque-reasoning"},
            {"type":"function_call","id":"fc_1","call_id":"call_portion","name":"ask_user",
                "arguments":ask_input().to_string(),"status":"completed"}
        ]);
        let response =
            json!({"id":"resp_1","model":"test-model","status":"completed","output":output});
        let decoded = llm_protocol::decode(
            &ep,
            &request,
            200,
            &[],
            &serde_json::to_vec(&response).unwrap(),
        )
        .unwrap();
        let CaptureResponse::AskUser { request: ask, .. } = capture_response(decoded, 0).unwrap()
        else {
            panic!("Responses tool call must suspend capture");
        };
        assert_eq!(ask.call_id, "call_portion");
        assert_eq!(ask.provider_output.as_ref(), Some(&output));
        let mut draft = initial;
        draft.transcript = vec![
            Turn::Owner {
                text: "Lunch".into(),
                photo: false,
                images: vec![],
            },
            Turn::AskUser { request: ask },
            Turn::ToolAnswer {
                call_id: "call_portion".into(),
                answers: vec![AskAnswer {
                    question_id: "portion".into(),
                    option_id: Some("half".into()),
                    text: String::new(),
                }],
                text: "Half".into(),
                images: vec!["private-label.png".into()],
            },
        ];
        let restored: Draft =
            serde_json::from_str(&serde_json::to_string(&draft).unwrap()).unwrap();
        let images = vec![("private-label.png".into(), b"\x89PNG\r\n\x1a\n".to_vec())];
        let resumed = capture_request(&account, &restored, &images, Lang::En, &json!({})).unwrap();
        let wire = llm_protocol::encode(&ep, &resumed, false, llm_protocol::StructuredMode::Native)
            .unwrap();
        assert_eq!(wire.url, "https://api.openai.com/v1/responses");
        let body: serde_json::Value = serde_json::from_slice(&wire.body).unwrap();
        assert_eq!(body["store"], false);
        assert!(body.get("previous_response_id").is_none());
        assert_eq!(body["tools"][0]["name"], "ask_user");
        assert!(body["text"]["format"]["schema"].is_object());
        let input = body["input"].as_array().unwrap();
        let reasoning = input
            .iter()
            .position(|item| item["type"] == "reasoning")
            .unwrap();
        assert_eq!(input[reasoning], output[0]);
        assert_eq!(input[reasoning + 1], output[1]);
        assert_eq!(input[reasoning + 2]["type"], "function_call_output");
        assert_eq!(input[reasoning + 2]["call_id"], "call_portion");
        let answer: serde_json::Value =
            serde_json::from_str(input[reasoning + 2]["output"].as_str().unwrap()).unwrap();
        assert_eq!(answer["answers"][0]["option_id"], "half");
        assert_eq!(input[reasoning + 3]["content"][0]["type"], "input_image");
        assert!(
            input[reasoning + 3]["content"][0]["image_url"]
                .as_str()
                .unwrap()
                .starts_with("data:image/png;base64,")
        );
        assert!(!body.to_string().contains("private-label"));
    }

    #[test]
    fn responses_final_native_output_is_retained_for_later_corrections() {
        let account = test_account(Provider::OpenAiResponses);
        let mut draft = super::super::capture::new();
        let request = capture_request(&account, &draft, &[], Lang::En, &json!({})).unwrap();
        let reply = json!({"destination":null,"records":[money_record()]}).to_string();
        let output = json!([
            {"type":"reasoning","id":"rs_final","summary":[],"encrypted_content":"opaque-final"},
            {"type":"message","id":"msg_final","role":"assistant","status":"completed",
                "content":[{"type":"output_text","text":reply,"annotations":[]}]}
        ]);
        let response =
            json!({"id":"resp_final","model":"test-model","status":"completed","output":output});
        let decoded = llm_protocol::decode(
            &endpoint(&account).unwrap(),
            &request,
            200,
            &[],
            &serde_json::to_vec(&response).unwrap(),
        )
        .unwrap();
        let CaptureResponse::Records {
            reply,
            provider_output,
            ..
        } = capture_response(decoded, 0).unwrap()
        else {
            panic!("final response must produce records");
        };
        assert_eq!(provider_output.as_ref(), Some(&output));
        draft.transcript.push(Turn::Assistant {
            reply,
            records: 1,
            questions: vec![],
            provider_output,
        });
        let restored = serde_json::from_str(&serde_json::to_string(&draft).unwrap()).unwrap();
        let messages = capture_messages(&restored, &[], Lang::En, &json!({})).unwrap();
        assert_eq!(messages[1].metadata["responses_output"], output);
    }
}
