//! Server-Sent Events helpers used by the AI relay.
//!
//! We only need to *emit* SSE here, not parse it. Frames produced by this
//! module follow the format `event: <name>\ndata: <payload>\n\n`. Payloads
//! are always JSON so the client doesn't need to disambiguate framing
//! conventions per event.

/// Encode a single SSE frame. The payload is sent as one `data:` line; the
/// AI events we emit never contain newlines (JSON without whitespace), so we
/// don't need to split across multiple `data:` lines.
pub fn encode_event(event: &str, payload: &str) -> Vec<u8> {
    let mut buf = String::with_capacity(event.len() + payload.len() + 16);
    buf.push_str("event: ");
    buf.push_str(event);
    buf.push('\n');
    buf.push_str("data: ");
    buf.push_str(payload);
    buf.push_str("\n\n");
    buf.into_bytes()
}

/// Encode an SSE comment frame. Per the SSE spec a line starting with `:` is
/// a comment and silently discarded by the EventSource parser, but it still
/// counts as activity on the connection — proxies / load balancers won't
/// drop the long-poll for being idle, and the client's idle-timeout watchdog
/// resets each time one of these arrives.
///
/// Used by the AI relay's keepalive ticker (every 10s) so a slow tool
/// dispatch doesn't look like a dropped connection.
pub fn encode_comment(text: &str) -> Vec<u8> {
    let mut buf = String::with_capacity(text.len() + 4);
    buf.push_str(": ");
    buf.push_str(text);
    buf.push_str("\n\n");
    buf.into_bytes()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encode_event_writes_sse_frame() {
        let frame = encode_event("text", r#"{"text":"你好"}"#);
        assert_eq!(
            String::from_utf8(frame).unwrap(),
            "event: text\ndata: {\"text\":\"你好\"}\n\n"
        );
    }
}
