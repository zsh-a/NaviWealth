//! Owner-authorized recognition through the shared pi-rust runtime.

mod streaming;

use std::{rc::Rc, sync::OnceLock, time::Duration};

use navi_assistant::recognition::{self as runtime, LlmError, LlmRequest};
use navi_health::{
    consent::{Consent, UploadTarget},
    photo::{MealPhoto, PhotoRole},
    recognition::{self, Lang, MealEstimate, RecognitionError},
};
use serde_json::json;

use super::meals::new_food_id;
use crate::domain::{
    ProviderError, ResponseFailure, VisionFailure,
    account::{ModelAccount, Provider},
};

pub const RECOGNIZE_TIMEOUT: Duration = Duration::from_secs(150);
pub const PING_TIMEOUT: Duration = Duration::from_secs(60);

fn configuration(account: &ModelAccount, timeout: Duration) -> navi_assistant::Config {
    navi_assistant::Config {
        provider: match account.provider {
            Provider::Anthropic => navi_assistant::Provider::Anthropic,
            Provider::OpenAiCompatible => navi_assistant::Provider::OpenAiCompatible,
            Provider::OpenAiResponses => navi_assistant::Provider::OpenAiResponses,
        },
        base_url: account.normalized_base_url(),
        api_key: account.api_key.clone(),
        model: account.model.trim().to_owned(),
        system_prompt: String::new(),
        limits: navi_assistant::Limits {
            timeout,
            output_tokens: 8000,
            ..Default::default()
        },
        context_summary: None,
    }
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
    use runtime::{ContentBlock, LlmMessage, LlmRole};
    let photos = [MealPhoto::new((*jpeg).clone(), PhotoRole::Overview, None)];
    let prepared = recognition::prepare_meal(&upload_target(&account), &photos, &consent, lang, "")
        .map_err(recognition_failure)?;
    let mut content = Vec::new();
    for view in prepared.views {
        content.push(ContentBlock::Text {
            text: view.description,
        });
        content.push(ContentBlock::image("image/jpeg", view.jpeg));
    }
    content.push(ContentBlock::Text {
        text: prepared.user_text,
    });
    let request = LlmRequest {
        provider: upload_target(&account).provider,
        model: account.model.trim().to_owned(),
        messages: vec![
            LlmMessage {
                role: LlmRole::System,
                content: prepared.system_prompt.into(),
                metadata: json!({}),
            },
            LlmMessage {
                role: LlmRole::User,
                content: content.into(),
                metadata: json!({}),
            },
        ],
        temperature: None,
        max_output_tokens: Some(6000),
        tools: Vec::new(),
        response_schema: Some(recognition::response_schema()),
    };
    let response = streaming::complete(account, request, RECOGNIZE_TIMEOUT, |_| {}).await?;
    match response.finish_reason {
        runtime::LlmFinishReason::Stop => {}
        runtime::LlmFinishReason::Length => return Err(VisionFailure::Truncated),
        runtime::LlmFinishReason::ContentFilter => return Err(VisionFailure::Refused),
        _ => return Err(VisionFailure::Unreadable),
    }
    let diagnostics = json!({"provider":response.provider,"usage":response.usage,"finish_reason":response.finish_reason});
    let recognition = recognition::parse_recognition(&response.content, &mut new_food_id)
        .map_err(recognition_failure)?;
    Ok(MealEstimate {
        recognition,
        model: response.model.chars().take(200).collect(),
        prompt_version: recognition::PROMPT_VERSION.into(),
        diagnostics,
    })
}

pub async fn ping(account: ModelAccount) -> Result<(String, f64), VisionFailure> {
    let started = nsh_core::time::now();
    let request: LlmRequest = serde_json::from_value(json!({
        "provider":upload_target(&account).provider,
        "model":account.model.trim(),
        "messages":[{"role":"user","content":"Reply with OK."}], "max_output_tokens":32
    }))
    .map_err(|_| VisionFailure::Unreadable)?;
    let response = streaming::complete(account, request, PING_TIMEOUT, |_| {}).await?;
    Ok((response.model, started.elapsed().as_secs_f64()))
}

fn recognition_failure(error: RecognitionError) -> VisionFailure {
    match error {
        RecognitionError::Truncated => VisionFailure::Truncated,
        RecognitionError::Refused => VisionFailure::Refused,
        RecognitionError::Photo(_) => VisionFailure::Photo,
        RecognitionError::Consent(_) => VisionFailure::Refused,
        RecognitionError::NoJson => VisionFailure::Response(ResponseFailure::Json),
        RecognitionError::Context => VisionFailure::Response(ResponseFailure::Request),
        _ => VisionFailure::Response(ResponseFailure::Records),
    }
}

fn llm_failure(error: LlmError) -> VisionFailure {
    let code = error.record.code.as_str();
    // Only allowlisted classifications and a validated HTTP status reach UI/logs.
    let status = error
        .record
        .details
        .get("status")
        .and_then(serde_json::Value::as_u64)
        .filter(|status| (400..600).contains(status))
        .unwrap_or(0) as u16;
    let detail = match code {
        "recognition_invalid_json" => Some(ResponseFailure::Json),
        "recognition_schema_mismatch" => Some(ResponseFailure::Schema),
        "recognition_invalid_response" => Some(ResponseFailure::Protocol),
        "recognition_invalid_tool" => Some(ResponseFailure::Tool),
        "recognition_output_limit" => Some(ResponseFailure::OutputLimit),
        "provider_stream_incomplete" => Some(ResponseFailure::Stream),
        "recognition_configuration" | "recognition_invalid_schema" => {
            Some(ResponseFailure::Configuration)
        }
        "recognition_invalid_request" | "recognition_invalid_content" => {
            Some(ResponseFailure::Request)
        }
        "recognition_unsupported_call_id"
        | "recognition_invalid_history"
        | "recognition_unanswered_tool" => Some(ResponseFailure::History),
        "recognition_cancelled" => Some(ResponseFailure::Cancelled),
        _ => None,
    };
    if let Some(detail) = detail {
        log::warn!("vision: model request failed (code={})", detail.code());
        return VisionFailure::Response(detail);
    }
    if code.contains("timeout") {
        return VisionFailure::Timeout;
    }
    if code.contains("refusal") || code.contains("content_filter") {
        return VisionFailure::Refused;
    }
    if code == "provider_output_truncated" {
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
        500..=599 => ProviderError::Server(status),
        400..=499 => ProviderError::Rejected {
            status,
            message: "The model rejected the request. Check the account and image support.".into(),
        },
        _ if code.contains("rate_limit") => ProviderError::RateLimited,
        _ => return VisionFailure::Response(ResponseFailure::Provider),
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
    Ok(LlmRequest {
        provider: upload_target(account).provider,
        model: account.model.trim().to_owned(),
        messages: capture_messages(draft, images, lang, context)?,
        temperature: None,
        max_output_tokens: Some(8000),
        tools: vec![runtime::RecognitionTool {
            name: "ask_user".into(),
            description: "Ask the owner to resolve a capture decision. Pause until the owner submits answers; this tool never writes records.".into(),
            input_schema: capture::ask_user_schema(),
        }],
        response_schema: Some(capture::result_schema()),
    })
}

fn capture_response(
    response: runtime::LlmResponse,
    image_count: usize,
) -> Result<CaptureResponse, VisionFailure> {
    use crate::domain::capture;
    use runtime::{ContentBlock, LlmFinishReason};
    let model = response.model.chars().take(200).collect();
    let provider_output = response.metadata.get("responses_output").cloned();
    match response.finish_reason {
        LlmFinishReason::ToolCall => {
            let original = response
                .metadata
                .get("anthropic_content")
                .cloned()
                .ok_or(VisionFailure::Response(ResponseFailure::Protocol))?;
            let blocks: Vec<ContentBlock> = serde_json::from_value(original.clone())
                .map_err(|_| VisionFailure::Response(ResponseFailure::Protocol))?;
            let mut call = None;
            for block in &blocks {
                block
                    .validate()
                    .map_err(|_| VisionFailure::Response(ResponseFailure::Protocol))?;
                match block {
                    ContentBlock::ToolUse { id, name, input }
                        if name == "ask_user" && call.is_none() =>
                    {
                        call = Some((id, input));
                    }
                    ContentBlock::Text { .. }
                    | ContentBlock::Thinking { .. }
                    | ContentBlock::RedactedThinking { .. } => {}
                    _ => return Err(VisionFailure::Response(ResponseFailure::Protocol)),
                }
            }
            let (id, input) = call.ok_or(VisionFailure::Response(ResponseFailure::Protocol))?;
            let mut request = capture::AskUser::parse(id, input, original)
                .map_err(|_| VisionFailure::Response(ResponseFailure::Questions))?;
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
                return Err(VisionFailure::Response(ResponseFailure::Protocol));
            }
            let reply = response
                .object
                .map(|v| v.to_string())
                .unwrap_or(response.content);
            let (records, questions) = capture::parse(&reply)
                .map_err(|_| VisionFailure::Response(ResponseFailure::Records))?;
            if !capture::valid_meal_image_numbers(&records, image_count) {
                return Err(VisionFailure::Response(ResponseFailure::ImageReference));
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
        _ => Err(VisionFailure::Response(ResponseFailure::Protocol)),
    }
}

/// Rebuild the conversation with each image attached to its original owner
/// message. File names are local references and never sent to the provider.
fn capture_messages(
    draft: &crate::domain::capture::Draft,
    images: &[(String, Vec<u8>)],
    lang: Lang,
    context: &serde_json::Value,
) -> Result<Vec<runtime::LlmMessage>, VisionFailure> {
    use crate::domain::capture::{self, Turn};
    use runtime::{ContentBlock, LlmMessage, LlmRole};
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
                    metadata: json!({}),
                }
            }
            Turn::AskUser { request } => {
                let blocks: Vec<ContentBlock> = serde_json::from_value(request.blocks.clone())
                    .map_err(|_| VisionFailure::Unreadable)?;
                LlmMessage {
                    role: LlmRole::Assistant,
                    content: blocks.into(),
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
    use crate::domain::capture::Turn;
    if index + 1 != draft.transcript.len()
        || !draft.transcript[..index]
            .iter()
            .any(|turn| matches!(turn, Turn::Assistant { records, .. } if *records > 0))
    {
        return;
    }
    record_context(payload, draft);
}

pub(super) fn record_context(
    payload: &mut serde_json::Value,
    draft: &crate::domain::capture::Draft,
) {
    use crate::domain::capture::Record;
    use navi_finance::{assets, holdings::format_units, money::format};
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
    use crate::domain::capture::{AskAnswer, Draft, Turn};
    use runtime::{ContentBlock, ImageSource};

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
    fn result(
        content: String,
        blocks: serde_json::Value,
        tool: bool,
        output: Option<serde_json::Value>,
    ) -> runtime::LlmResponse {
        let mut metadata = json!({"anthropic_content":blocks});
        if let Some(output) = output {
            metadata["responses_output"] = output;
        }
        runtime::LlmResponse {
            provider: "test".into(),
            model: "test-model".into(),
            content,
            finish_reason: if tool {
                runtime::LlmFinishReason::ToolCall
            } else {
                runtime::LlmFinishReason::Stop
            },
            object: None,
            usage: None,
            metadata,
        }
    }
    fn suspend_blocks(blocks: serde_json::Value) -> Result<CaptureResponse, VisionFailure> {
        capture_response(result(String::new(), blocks, true, None), 0)
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
    fn failures_keep_classification_and_reject_untrusted_diagnostics() {
        for (code, expected) in [
            (
                "recognition_invalid_json",
                VisionFailure::Response(ResponseFailure::Json),
            ),
            (
                "recognition_schema_mismatch",
                VisionFailure::Response(ResponseFailure::Schema),
            ),
            (
                "provider_stream_incomplete",
                VisionFailure::Response(ResponseFailure::Stream),
            ),
            ("provider_output_truncated", VisionFailure::Truncated),
            (
                "recognition_invalid_history",
                VisionFailure::Response(ResponseFailure::History),
            ),
            (
                "secret_response_contents",
                VisionFailure::Response(ResponseFailure::Provider),
            ),
        ] {
            let mut error = LlmError::new(code);
            error.record.details =
                json!({"body":"secret_response_contents", "status": 65536 + 401});
            assert_eq!(llm_failure(error), expected);
        }
        for status in [400, 401, 413, 429, 503, 529] {
            let mut error = LlmError::new("provider_http_error");
            error.record.details = json!({"status":status,"body":"secret_response_contents"});
            let failure = llm_failure(error);
            let (_, body) =
                crate::pages::review_failure_copy(crate::i18n::strings(Lang::Zh), &failure);
            assert!(body.contains(&format!("HTTP {status}")));
            assert!(!body.contains("secret_response_contents"));
        }
    }

    #[test]
    fn capture_contract_carries_the_exact_schema_and_only_owner_question_tool() {
        let request = capture_request(
            &test_account(Provider::Anthropic),
            &super::super::capture::new(),
            &[],
            Lang::Zh,
            &json!({}),
        )
        .unwrap();
        let schema = request.response_schema.unwrap();
        assert_eq!(schema, crate::domain::capture::result_schema());
        let prompt = request.messages[0].content.as_str().unwrap();
        let embedded = prompt
            .lines()
            .find_map(|line| line.strip_prefix("FINAL_RECORD_JSON_SCHEMA: "))
            .unwrap();
        assert_eq!(
            serde_json::from_str::<serde_json::Value>(embedded).unwrap(),
            schema
        );
        assert_eq!(request.tools.len(), 1);
        assert_eq!(request.tools[0].name, "ask_user");
        assert_eq!(
            request.tools[0].input_schema,
            crate::domain::capture::ask_user_schema()
        );
    }
    #[test]
    fn final_schema_rejects_fences_and_incorrect_accounting_fields() {
        let format = Some(crate::domain::capture::result_schema());
        let valid = json!({"destination":null,"records":[money_record()]}).to_string();
        assert!(runtime::structured_output_from_content(&format, &valid).is_ok());
        assert!(
            runtime::structured_output_from_content(&format, &format!("```json\n{valid}\n```"))
                .is_err()
        );
        let mut wrong = money_record();
        wrong["money"].as_object_mut().unwrap().remove("kind");
        assert!(
            runtime::structured_output_from_content(
                &format,
                &json!({"destination":null,"records":[wrong]}).to_string()
            )
            .is_err()
        );
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
            let decoded = result(
                json!({"destination":null,"records":[proposed]}).to_string(),
                json!([]),
                false,
                None,
            );
            capture_response(decoded, draft.sent_images().len())
        };
        assert!(matches!(
            decode(json!(3)),
            Err(VisionFailure::Response(ResponseFailure::ImageReference))
        ));
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
        let CaptureResponse::AskUser { request, .. } = suspend_blocks(blocks.clone()).unwrap()
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
        let call = json!({"type":"tool_use","id":"ask-1","name":"ask_user","input":ask_input()});
        assert!(suspend_blocks(json!([call.clone(), call.clone()])).is_err());
        let mut unknown = call.clone();
        unknown["name"] = json!("save_records");
        assert!(suspend_blocks(json!([unknown])).is_err());
        let mut invalid = call;
        invalid["input"]["questions"] = json!([]);
        assert!(suspend_blocks(json!([invalid])).is_err());
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
    fn saved_native_history_and_explicit_answers_survive_restore() {
        let call = json!({"type":"tool_use","id":"ask-1","name":"ask_user","input":ask_input()});
        let output = json!([{"type":"reasoning","id":"rs_1","summary":[],"encrypted_content":"opaque"},
            {"type":"function_call","id":"fc_1","call_id":"ask-1","name":"ask_user","arguments":ask_input().to_string(),"status":"completed"}]);
        // Arrays were written by the retired runtime; objects contain the new
        // native pi message. Both must remain intact in the saved draft.
        for output in [
            output,
            json!({"pi_message":{"role":"assistant","content":[]}}),
        ] {
            let CaptureResponse::AskUser { request, .. } = capture_response(
                result(String::new(), json!([call]), true, Some(output.clone())),
                0,
            )
            .unwrap() else {
                panic!("question")
            };
            let mut draft = super::super::capture::new();
            draft.transcript = vec![
                Turn::Owner {
                    text: "Lunch".into(),
                    photo: false,
                    images: vec![],
                },
                Turn::AskUser { request },
                Turn::ToolAnswer {
                    call_id: "ask-1".into(),
                    answers: vec![AskAnswer {
                        question_id: "portion".into(),
                        option_id: Some("half".into()),
                        text: String::new(),
                    }],
                    text: "Half the package".into(),
                    images: vec!["private-label.png".into()],
                },
            ];
            let restored: Draft =
                serde_json::from_str(&serde_json::to_string(&draft).unwrap()).unwrap();
            let messages = capture_messages(
                &restored,
                &[("private-label.png".into(), b"\x89PNG\r\n\x1a\n".to_vec())],
                Lang::En,
                &json!({}),
            )
            .unwrap();
            assert_eq!(messages[2].metadata["responses_output"], output);
            let blocks = messages[3].content.blocks().unwrap();
            let [
                ContentBlock::ToolResult {
                    tool_use_id,
                    content,
                    ..
                },
            ] = blocks
            else {
                panic!("answer before images")
            };
            assert_eq!(tool_use_id, "ask-1");
            let answer: serde_json::Value =
                serde_json::from_str(content.as_str().unwrap()).unwrap();
            assert_eq!(answer["answers"][0]["option_id"], "half");
            assert!(matches!(
                messages[4].content.blocks().unwrap()[0],
                ContentBlock::Image { .. }
            ));
            assert!(
                !serde_json::to_string(&messages)
                    .unwrap()
                    .contains("private-label")
            );
        }
    }

    #[test]
    fn final_records_retain_native_history_and_reject_unexpected_tools() {
        let output = json!({"pi_message":{"role":"assistant","content":[]}});
        let reply = json!({"destination":null,"records":[money_record()]}).to_string();
        let CaptureResponse::Records {
            reply,
            provider_output,
            records,
            ..
        } = capture_response(result(reply, json!([]), false, Some(output.clone())), 0).unwrap()
        else {
            panic!("records")
        };
        assert_eq!(records.len(), 1);
        let mut draft = super::super::capture::new();
        draft.transcript.push(Turn::Assistant {
            reply,
            records: 1,
            questions: vec![],
            provider_output,
        });
        let restored = serde_json::from_str(&serde_json::to_string(&draft).unwrap()).unwrap();
        assert_eq!(
            capture_messages(&restored, &[], Lang::En, &json!({})).unwrap()[1].metadata["responses_output"],
            output
        );
        assert!(
            capture_response(
                result(
                    String::new(),
                    json!([{"type":"tool_use","id":"bad","name":"save_records","input":{}}]),
                    false,
                    None
                ),
                0
            )
            .is_err()
        );
    }
}
