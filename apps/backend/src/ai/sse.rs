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
