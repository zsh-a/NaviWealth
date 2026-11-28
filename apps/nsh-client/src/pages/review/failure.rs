//! Localized recovery copy and allowlisted diagnostic codes only.
use crate::{
    domain::{ProviderError, ResponseFailure, VisionFailure, recognition::Lang},
    i18n::Strings,
};

type Copy = (&'static str, &'static str);
fn localized(strings: &Strings, en: Copy, zh: Copy) -> Copy {
    if strings.lang == Lang::Zh { zh } else { en }
}

/// The title and copy that explain `failure`.
pub fn failure_copy(strings: &'static Strings, failure: &VisionFailure) -> (&'static str, String) {
    let pair = |(title, body): (&'static str, &'static str)| (title, body.to_owned());
    let (title, body) = match failure {
        VisionFailure::Offline(_) => pair(strings.failure_offline),
        VisionFailure::Timeout => pair(strings.failure_timeout),
        VisionFailure::Truncated => pair(localized(
            strings,
            (
                "The model stopped before finishing",
                "The reply reached the model's output limit. Retry with fewer records or images, or use another model.",
            ),
            (
                "模型未能完整输出",
                "接收结果时，模型达到输出长度上限。请减少单次记录或图片数量后重试，或更换模型。",
            ),
        )),
        VisionFailure::Unreadable => pair(strings.failure_unreadable),
        VisionFailure::Response(detail) => pair(response_copy(strings, *detail)),
        VisionFailure::Refused => pair(strings.failure_refused),
        VisionFailure::Photo => pair(strings.failure_photo),
        VisionFailure::Storage => (
            strings.storage_unavailable,
            strings.error_transaction_storage.to_owned(),
        ),
        VisionFailure::Provider(error) => match error {
            ProviderError::Unauthorized => pair(strings.failure_unauthorized),
            ProviderError::Forbidden => pair(strings.failure_forbidden),
            ProviderError::NotFound => pair(strings.failure_not_found),
            ProviderError::RateLimited => pair(strings.failure_rate_limited),
            ProviderError::Overloaded | ProviderError::Server(_) => pair(strings.failure_busy),
            ProviderError::Decode => pair(strings.failure_unreadable),
            // Provider messages may echo credentials or submitted content.
            ProviderError::Rejected { .. } => pair(strings.failure_rejected),
        },
    };
    let code = diagnostic_code(failure);
    let label = if strings.lang == Lang::Zh {
        "诊断码"
    } else {
        "Diagnostic code"
    };
    (
        title,
        format!("{body}\n{label}: {code} · v{}", env!("CARGO_PKG_VERSION")),
    )
}

fn response_copy(strings: &Strings, detail: ResponseFailure) -> Copy {
    match detail {
        ResponseFailure::Json => localized(
            strings,
            (
                "The reply was not readable",
                "Decoding failed: the model did not return valid JSON. Retry; if it recurs, try another model.",
            ),
            (
                "模型返回的内容无法解析",
                "解析结果失败：模型未返回有效的 JSON。可以重试；若反复出现，请更换模型。",
            ),
        ),
        ResponseFailure::Schema => localized(
            strings,
            (
                "The reply has missing or invalid fields",
                "Response validation failed: required fields were missing, had incorrect types, or unexpected fields were returned. Retry or use another model.",
            ),
            (
                "模型返回的字段不符合要求",
                "校验结果失败：必填字段缺失、类型错误或存在多余字段。可以重试；若反复出现，请更换模型。",
            ),
        ),
        ResponseFailure::Protocol => localized(
            strings,
            (
                "The service returned an inconsistent reply",
                "Protocol validation failed: completion status and result or tool calls did not match. Retry; if it recurs, check the API protocol and service compatibility.",
            ),
            (
                "服务返回的响应不一致",
                "校验响应失败：结束状态与结果或工具调用不匹配。可以重试；若反复出现，请检查 API 协议及服务兼容性。",
            ),
        ),
        ResponseFailure::Tool => localized(
            strings,
            (
                "The model returned an unsupported action",
                "The reply used an unexpected tool. No action was executed. Retry or use another model.",
            ),
            (
                "模型返回了不支持的操作",
                "校验结果时发现非预期的工具调用，未执行该操作。请重试或更换模型。",
            ),
        ),
        ResponseFailure::OutputLimit => localized(
            strings,
            (
                "The reply was too large",
                "Receiving stopped because the response exceeded the app limit. Reduce the number of records or images and retry.",
            ),
            (
                "模型返回的内容过大",
                "接收结果时，响应超过应用大小限制。请减少单次记录或图片数量后重试。",
            ),
        ),
        ResponseFailure::Stream => localized(
            strings,
            (
                "The reply ended before completion",
                "Receiving ended without a complete response. The connection or service may have interrupted the stream. Check the network and retry.",
            ),
            (
                "模型响应未接收完整",
                "接收结果时，响应流未正常结束。可能是连接或服务中断，请检查网络后重试。",
            ),
        ),
        ResponseFailure::Configuration => localized(
            strings,
            (
                "The recognition request could not be configured",
                "Request setup failed. Check the API protocol, URL and model; if they are correct, update the app.",
            ),
            (
                "无法配置识别请求",
                "准备请求失败。请检查 API 协议、地址和模型；配置无误时请更新应用。",
            ),
        ),
        ResponseFailure::Request => localized(
            strings,
            (
                "The recognition request could not be prepared",
                "The submitted content is invalid or too large. Reduce text or images and start a new draft.",
            ),
            (
                "无法准备识别请求",
                "发送前校验失败：内容无效或过大。请减少文字或图片后新建草稿。",
            ),
        ),
        ResponseFailure::History => localized(
            strings,
            (
                "This conversation could not be continued",
                "The saved tool conversation cannot be replayed with this service. Start a new draft; if it recurs, check API compatibility.",
            ),
            (
                "无法继续这条识别对话",
                "准备续传时，对话中的工具信息无法用于当前服务。请新建草稿；若反复出现，请检查 API 兼容性。",
            ),
        ),
        ResponseFailure::Records => localized(
            strings,
            (
                "The result contains invalid record values",
                "Record validation failed: some values or record combinations cannot be used. Retry or enter the record manually.",
            ),
            (
                "识别结果中的记录无效",
                "校验记录失败：部分数值或记录组合不符合要求。请重试，或手动录入。",
            ),
        ),
        ResponseFailure::Questions => localized(
            strings,
            (
                "The clarification could not be read",
                "The model returned invalid clarification fields or tool history. Retry; if it recurs, start a new draft.",
            ),
            (
                "无法读取模型的补充问题",
                "校验补充问题失败：问题字段或工具对话信息无效。请重试；若反复出现，请新建草稿。",
            ),
        ),
        ResponseFailure::ImageReference => localized(
            strings,
            (
                "The result refers to an unavailable image",
                "Record validation failed: a meal refers to an image outside this draft. Retry recognition.",
            ),
            (
                "识别结果引用了不存在的图片",
                "校验记录失败：餐食引用的图片编号不属于当前草稿。请重新识别。",
            ),
        ),
        ResponseFailure::Worker => localized(
            strings,
            (
                "Recognition was interrupted",
                "The local recognition task ended unexpectedly. Retry; if it recurs, restart the app.",
            ),
            (
                "本次识别意外中断",
                "本机识别任务意外结束。请重试；若反复出现，请重启应用。",
            ),
        ),
        ResponseFailure::Cancelled => localized(
            strings,
            (
                "Recognition was cancelled",
                "This recognition request was cancelled. Retry when ready.",
            ),
            ("识别已取消", "本次识别请求已取消，需要时可重新识别。"),
        ),
        ResponseFailure::Provider => localized(
            strings,
            (
                "The model service returned an error",
                "The service failed without a recognized error category. Retry later; if it recurs, check the model and API protocol.",
            ),
            (
                "模型服务返回错误",
                "调用服务失败，未能取得可分类的错误原因。请稍后重试；若反复出现，请检查模型和 API 协议。",
            ),
        ),
    }
}

fn diagnostic_code(failure: &VisionFailure) -> String {
    match failure {
        VisionFailure::Response(detail) => detail.code().into(),
        VisionFailure::Provider(error) => match error {
            ProviderError::Unauthorized => "HTTP 401".into(),
            ProviderError::Forbidden => "HTTP 403".into(),
            ProviderError::NotFound => "HTTP 404".into(),
            ProviderError::RateLimited => "HTTP 429".into(),
            ProviderError::Overloaded => "provider_overloaded".into(),
            ProviderError::Server(status) | ProviderError::Rejected { status, .. } => {
                format!("HTTP {status}")
            }
            ProviderError::Decode => "provider_decode".into(),
        },
        VisionFailure::Offline(_) => "provider_request_failed".into(),
        VisionFailure::Timeout => "recognition_timeout".into(),
        VisionFailure::Truncated => "provider_output_truncated".into(),
        VisionFailure::Unreadable => "recognition_unreadable".into(),
        VisionFailure::Refused => "recognition_refused".into(),
        VisionFailure::Photo => "photo_preparation_failed".into(),
        VisionFailure::Storage => "draft_storage_failed".into(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn localized_details_distinguish_failures_without_echoing_provider_text() {
        for lang in [Lang::En, Lang::Zh] {
            let strings = crate::i18n::strings(lang);
            let stream = failure_copy(strings, &VisionFailure::Response(ResponseFailure::Stream));
            let length = failure_copy(strings, &VisionFailure::Truncated);
            assert_ne!(stream.0, length.0);
            assert!(stream.1.contains("provider_stream_incomplete"));
            assert!(length.1.contains("provider_output_truncated"));
            assert!(stream.1.contains(env!("CARGO_PKG_VERSION")));
            for failure in [
                VisionFailure::Offline("private_token_and_photo".into()),
                VisionFailure::Provider(ProviderError::Rejected {
                    status: 413,
                    message: "private_token_and_photo".into(),
                }),
            ] {
                let (_, body) = failure_copy(strings, &failure);
                assert!(!body.contains("private_token_and_photo"));
            }
        }
    }
}
