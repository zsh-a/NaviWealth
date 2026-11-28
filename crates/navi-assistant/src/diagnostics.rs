//! Only fixed, localizable codes may cross the provider boundary. Never retain
//! response text, credentials, model input, or URLs in diagnostic history.
use rpi_ai::types::{AssistantMessage, StopReason};

pub(crate) const CODES: &[&str] = &[
    "assistant_provider",
    "assistant_authentication",
    "assistant_permission",
    "assistant_quota",
    "assistant_rate_limit",
    "assistant_http_client",
    "assistant_http_server",
    "assistant_network",
    "assistant_tls",
    "assistant_image_unsupported",
    "assistant_stream_incomplete",
    "assistant_empty_response",
    "assistant_output_truncated",
    "assistant_refusal",
    "assistant_protocol",
    "assistant_timeout",
    "assistant_cancelled",
];

pub(crate) fn index(code: &str) -> usize {
    CODES.iter().position(|known| *known == code).unwrap_or(0) + 10
}
pub(crate) fn from_index(index: usize) -> Option<&'static str> {
    index
        .checked_sub(10)
        .and_then(|index| CODES.get(index).copied())
}
pub(crate) fn sanitize(code: Option<&str>) -> &'static str {
    code.and_then(|code| CODES.iter().find(|known| **known == code).copied())
        .unwrap_or("assistant_provider")
}

pub(crate) fn classify(message: &AssistantMessage) -> &'static str {
    if message.stop_reason == StopReason::Aborted {
        return "assistant_cancelled";
    }
    if message.stop_reason == StopReason::Length {
        return "assistant_output_truncated";
    }
    let raw = message
        .error_message
        .as_deref()
        .unwrap_or_default()
        .to_ascii_lowercase();
    if CODES.contains(&raw.as_str()) {
        return sanitize(Some(&raw));
    }
    let http = raw
        .strip_prefix("http error ")
        .and_then(|rest| rest.split_once(':'))
        .and_then(|(status, body)| status.parse::<u16>().ok().map(|status| (status, body)))
        .filter(|(status, _)| (300..600).contains(status));
    if let Some((status, _)) = http {
        match status {
            401 => return "assistant_authentication",
            403 => return "assistant_permission",
            402 => return "assistant_quota",
            408 | 504 => return "assistant_timeout",
            500..=599 => return "assistant_http_server",
            _ => {}
        }
    }
    // Structured provider codes are stronger evidence than arbitrary prose.
    let body =
        http.and_then(|(_, body)| serde_json::from_str::<serde_json::Value>(body.trim()).ok());
    let code = body
        .as_ref()
        .and_then(|body| {
            body.pointer("/error/code")
                .or_else(|| body.pointer("/error/type"))
        })
        .and_then(serde_json::Value::as_str)
        .or_else(|| {
            raw.strip_prefix("provider error [")
                .and_then(|s| s.split_once("]:").map(|(code, _)| code))
        });
    match code {
        Some(
            "insufficient_quota"
            | "quota_exceeded"
            | "insufficient_balance"
            | "credit_balance_too_low",
        ) => return "assistant_quota",
        Some("rate_limit_exceeded" | "rate_limit_error") => return "assistant_rate_limit",
        Some("authentication_error" | "invalid_api_key") => return "assistant_authentication",
        Some("permission_error" | "permission_denied") => return "assistant_permission",
        Some("unsupported_image" | "image_not_supported" | "unsupported_image_input") => {
            return "assistant_image_unsupported";
        }
        Some("content_filter" | "content_policy_violation") => return "assistant_refusal",
        _ => {}
    }
    if http.is_some_and(|(status, _)| status == 429) {
        return "assistant_rate_limit";
    }
    // Restrict capability prose matching to provider errors: a user/model quote
    // or an arbitrary numeric fragment must not be treated as an HTTP status.
    if (http.is_some_and(|(status, _)| matches!(status, 400 | 422))
        || raw.starts_with("provider error ["))
        && [
            "does not support image",
            "doesn't support image",
            "does not support vision",
            "image input is not supported",
            "image inputs are not supported",
            "image_url is not supported",
            "only supports text input",
        ]
        .iter()
        .any(|needle| raw.contains(needle))
    {
        return "assistant_image_unsupported";
    }
    if http.is_some() {
        return "assistant_http_client";
    }
    if raw.starts_with("auth error:") {
        return "assistant_authentication";
    }
    if message.raw_stop_reason.as_deref() == Some("refusal") {
        return "assistant_refusal";
    }
    if raw.contains("timed out") || raw.contains("timeout") {
        return "assistant_timeout";
    }
    if raw.contains("certificate") || raw.contains("tls handshake") || raw.contains("ssl error") {
        return "assistant_tls";
    }
    if [
        "without finish",
        "without message_stop",
        "unexpected eof",
        "before terminal",
        "before a terminal",
        "without a terminal",
        "incomplete stream",
    ]
    .iter()
    .any(|s| raw.contains(s))
    {
        return "assistant_stream_incomplete";
    }
    if raw.starts_with("http error:")
        || raw.contains("error sending request")
        || raw.contains("connection refused")
    {
        return "assistant_network";
    }
    if raw.starts_with("sse error:")
        || raw.contains("failed to parse")
        || raw.contains("invalid json")
    {
        return "assistant_protocol";
    }
    "assistant_provider"
}

#[cfg(test)]
mod tests {
    use super::*;
    use rpi_ai::types::Api;
    #[test]
    fn only_allowlisted_codes_escape_untrusted_diagnostics() {
        for (raw, expected) in [
            ("http error 401: secret-key 503", "assistant_authentication"),
            ("http error 403: secret-key", "assistant_permission"),
            (
                "http error 429: {\"error\":{\"code\":\"insufficient_quota\",\"message\":\"secret-key\"}}",
                "assistant_quota",
            ),
            ("http error 429: secret-key", "assistant_rate_limit"),
            (
                "http error 400: this model does not support image inputs secret-key",
                "assistant_image_unsupported",
            ),
            (
                "http error 400: invalid image secret-key",
                "assistant_http_client",
            ),
            ("http error 503: secret-key", "assistant_http_server"),
            (
                "http error: invalid peer certificate: secret-key",
                "assistant_tls",
            ),
            (
                "http error: connection refused secret-key",
                "assistant_network",
            ),
            (
                "http error: request timed out secret-key",
                "assistant_timeout",
            ),
            (
                "OpenAI Responses stream ended before a terminal response event secret-key",
                "assistant_stream_incomplete",
            ),
            ("sse error: invalid JSON secret-key", "assistant_protocol"),
            ("invalid result id 401 secret-key", "assistant_provider"),
        ] {
            let message = AssistantMessage::terminal(
                Api::OpenaiCompletions,
                "fixture",
                "fixture",
                StopReason::Error,
                raw,
                0,
            );
            assert_eq!(classify(&message), expected, "{raw}");
            assert_eq!(from_index(index(expected)), Some(expected));
            assert_eq!(sanitize(Some(expected)), expected);
        }
        assert_eq!(sanitize(Some("secret-key")), "assistant_provider");
    }
}
