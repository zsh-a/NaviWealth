use serde_json::Value;

use crate::types::{LlmRequest, LlmUsage};

pub(crate) fn estimate_usage(request: &LlmRequest, output: &str) -> LlmUsage {
    let input_tokens = request
        .messages
        .iter()
        .map(|message| rough_token_count(&content_for_usage(&message.content)))
        .sum::<u32>();
    let output_tokens = rough_token_count(output);
    LlmUsage {
        input_tokens,
        output_tokens,
        total_tokens: input_tokens + output_tokens,
    }
}

fn content_for_usage(content: &Value) -> String {
    content
        .as_str()
        .map(str::to_owned)
        .unwrap_or_else(|| content.to_string())
}

fn rough_token_count(text: &str) -> u32 {
    text.split_whitespace().count().max(1) as u32
}
