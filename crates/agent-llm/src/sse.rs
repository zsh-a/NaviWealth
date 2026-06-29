use serde_json::{Value, json};

pub(crate) fn decode_json_value_or_null(input: &str) -> Option<Value> {
    if input.trim().is_empty() {
        return Some(json!({}));
    }
    Some(serde_json::from_str::<Value>(input).unwrap_or(Value::Null))
}

pub(crate) fn take_next_sse_frame(buffer: &mut String) -> Option<String> {
    let lf = buffer.find("\n\n").map(|idx| (idx, 2));
    let crlf = buffer.find("\r\n\r\n").map(|idx| (idx, 4));
    let (idx, len) = match (lf, crlf) {
        (Some(a), Some(b)) => {
            if a.0 <= b.0 {
                a
            } else {
                b
            }
        }
        (Some(a), None) => a,
        (None, Some(b)) => b,
        (None, None) => return None,
    };
    let frame = buffer[..idx].to_owned();
    buffer.drain(..idx + len);
    Some(frame)
}

pub(crate) fn take_remaining_sse_frame(buffer: &mut String) -> Option<String> {
    let frame = buffer.trim().to_owned();
    buffer.clear();
    if frame.is_empty() { None } else { Some(frame) }
}

pub(crate) fn sse_data(frame: &str) -> String {
    let mut data = String::new();
    for line in frame.lines() {
        let line = line.trim_end_matches('\r');
        if line.starts_with(':') {
            continue;
        }
        if let Some(piece) = line.strip_prefix("data:") {
            if !data.is_empty() {
                data.push('\n');
            }
            data.push_str(piece.trim_start());
        }
    }
    data
}
