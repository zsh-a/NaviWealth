//! Vision parse tool schema + prompt + structured extraction.

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::ai::adapters::anthropic::{AnthropicMessage, ChatMessage, ToolSchema};
use crate::error::AppError;

/// The single tool the model is forced to call. Naming it explicitly
/// (vs free text) is what makes extraction deterministic.
pub const EMIT_TOOL: &str = "emit_parsed_transactions";

/// Hard cap on rows accepted from one parse — bounds a hostile/confused
/// model and the response size. Extra rows are truncated, not errored.
pub const MAX_PARSED_DRAFTS: usize = 200;

/// One parsed row, mirrored on the mobile side as `ParsedTransaction`.
/// `amount_minor` is signed minor units, expense-negative (the model is
/// instructed to follow the same convention the device parser uses).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ParsedDraftWire {
    pub description: String,
    pub amount_minor: i64,
    pub currency: String,
    pub occurred_at: String,
    #[serde(default)]
    pub category_hint: Option<String>,
    #[serde(default = "default_confidence")]
    pub confidence: f64,
}

fn default_confidence() -> f64 {
    0.6
}

/// JSON-schema for [`EMIT_TOOL`]. Kept strict so the model returns
/// machine-usable rows, not prose.
pub fn parse_tool_schema() -> ToolSchema {
    ToolSchema {
        name: EMIT_TOOL.to_string(),
        description: "Emit every transaction found in the document. Call exactly \
             once. amount_minor is signed integer minor units (cents); \
             expenses are negative. occurred_at is YYYY-MM-DD. currency is \
             an ISO-4217 code. If the document is unreadable, emit an empty \
             list — never invent rows."
            .to_string(),
        input_schema: json!({
            "type": "object",
            "properties": {
                "transactions": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "description": { "type": "string" },
                            "amount_minor": { "type": "integer" },
                            "currency": { "type": "string" },
                            "occurred_at": { "type": "string" },
                            "category_hint": { "type": ["string", "null"] },
                            "confidence": { "type": "number" }
                        },
                        "required": [
                            "description", "amount_minor", "currency", "occurred_at"
                        ]
                    }
                }
            },
            "required": ["transactions"]
        }),
    }
}

pub fn system_prompt() -> &'static str {
    "You are a precise financial-statement parser. Read the attached \
     receipt or bank/credit-card statement and extract every individual \
     transaction. Respond ONLY by calling the emit_parsed_transactions \
     tool exactly once. Rules: amount_minor is a signed integer in the \
     currency's minor unit (e.g. cents); money the user spent is \
     negative; refunds/credits are positive. occurred_at is the \
     transaction date as YYYY-MM-DD. currency is the ISO-4217 code you \
     see on the document (fall back to the provided hint). Never \
     fabricate values you cannot read — omit an uncertain row rather \
     than guess. If nothing is readable, call the tool with an empty \
     transactions list."
}

/// Build the user turn: the binary as a base64 content block + a short
/// instruction. PDF rides a `document` block; everything else an
/// `image` block (the model decides if it can actually read it).
pub fn build_messages(
    mime: &str,
    content_b64: &str,
    currency_hint: Option<&str>,
) -> Vec<ChatMessage> {
    let media_type = if mime.trim().is_empty() {
        "application/octet-stream"
    } else {
        mime.trim()
    };
    let source = json!({
        "type": "base64",
        "media_type": media_type,
        "data": content_b64,
    });
    let doc_block = if media_type == "application/pdf" {
        json!({ "type": "document", "source": source })
    } else {
        json!({ "type": "image", "source": source })
    };
    let hint = currency_hint
        .map(|c| format!(" The user's primary currency is {c}; prefer it when ambiguous."))
        .unwrap_or_default();
    let text = format!(
        "Extract every transaction from this document and call \
         emit_parsed_transactions.{hint}"
    );
    vec![ChatMessage {
        role: "user".to_string(),
        content: json!([doc_block, { "type": "text", "text": text }]),
    }]
}

/// Pull the forced tool call out of the model's reply. Errors only when
/// the model returned no `emit_parsed_transactions` block at all; an
/// empty list is a valid "nothing readable" answer.
pub fn extract_drafts(msg: &AnthropicMessage) -> Result<Vec<ParsedDraftWire>, AppError> {
    let tool_input = msg.content.iter().find_map(|block| {
        let obj = block.as_object()?;
        if obj.get("type").and_then(Value::as_str) != Some("tool_use") {
            return None;
        }
        if obj.get("name").and_then(Value::as_str) != Some(EMIT_TOOL) {
            return None;
        }
        obj.get("input").cloned()
    });

    let Some(input) = tool_input else {
        return Err(AppError::coded(
            422,
            "vision_no_extraction",
            "model did not return a parsed-transactions tool call",
        ));
    };

    let rows = input
        .get("transactions")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();

    let mut out = Vec::with_capacity(rows.len().min(MAX_PARSED_DRAFTS));
    for row in rows.into_iter().take(MAX_PARSED_DRAFTS) {
        // Skip individually malformed rows rather than failing the whole
        // batch — a partial parse still beats forcing manual entry.
        if let Ok(draft) = serde_json::from_value::<ParsedDraftWire>(row) {
            if !draft.currency.trim().is_empty() && !draft.occurred_at.trim().is_empty() {
                out.push(draft);
            }
        }
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tool_schema_requires_the_core_fields() {
        let schema = parse_tool_schema();
        assert_eq!(schema.name, EMIT_TOOL);
        let req = &schema.input_schema["properties"]["transactions"]["items"]["required"];
        let req: Vec<&str> = req
            .as_array()
            .unwrap()
            .iter()
            .map(|v| v.as_str().unwrap())
            .collect();
        assert!(req.contains(&"amount_minor"));
        assert!(req.contains(&"occurred_at"));
        assert!(req.contains(&"currency"));
    }

    #[test]
    fn pdf_uses_document_block_image_otherwise() {
        let pdf = build_messages("application/pdf", "Qkk=", Some("CNY"));
        assert_eq!(pdf[0].content[0]["type"], "document");
        assert!(pdf[0].content[1]["text"].as_str().unwrap().contains("CNY"));

        let img = build_messages("image/png", "Qkk=", None);
        assert_eq!(img[0].content[0]["type"], "image");
        assert_eq!(img[0].content[0]["source"]["media_type"], "image/png");
    }

    fn msg_with(content: Value) -> AnthropicMessage {
        serde_json::from_value(json!({ "content": content, "stop_reason": "tool_use" })).unwrap()
    }

    #[test]
    fn extracts_rows_from_the_forced_tool_call() {
        let msg = msg_with(json!([
            { "type": "text", "text": "ignored" },
            {
                "type": "tool_use",
                "name": EMIT_TOOL,
                "input": { "transactions": [
                    { "description": "Starbucks", "amount_minor": -3800,
                      "currency": "CNY", "occurred_at": "2026-05-10",
                      "category_hint": "coffee", "confidence": 0.9 },
                    { "description": "Refund", "amount_minor": 1200,
                      "currency": "CNY", "occurred_at": "2026-05-11" }
                ]}
            }
        ]));
        let drafts = extract_drafts(&msg).unwrap();
        assert_eq!(drafts.len(), 2);
        assert_eq!(drafts[0].amount_minor, -3800);
        assert_eq!(drafts[0].category_hint.as_deref(), Some("coffee"));
        // default confidence fills in when the model omits it
        assert!((drafts[1].confidence - default_confidence()).abs() < 1e-9);
    }

    #[test]
    fn empty_list_is_valid_but_missing_tool_is_an_error() {
        let empty = msg_with(json!([
            { "type": "tool_use", "name": EMIT_TOOL, "input": { "transactions": [] } }
        ]));
        assert!(extract_drafts(&empty).unwrap().is_empty());

        let no_tool = msg_with(json!([{ "type": "text", "text": "I cannot read this" }]));
        let err = extract_drafts(&no_tool).unwrap_err();
        assert_eq!(err.code(), "vision_no_extraction");
    }

    #[test]
    fn malformed_rows_are_skipped_not_fatal() {
        let msg = msg_with(json!([{
            "type": "tool_use", "name": EMIT_TOOL,
            "input": { "transactions": [
                { "description": "ok", "amount_minor": -100, "currency": "USD",
                  "occurred_at": "2026-01-02" },
                { "description": "bad — amount is a string", "amount_minor": "oops",
                  "currency": "USD", "occurred_at": "2026-01-03" },
                { "description": "no currency", "amount_minor": -1, "currency": "",
                  "occurred_at": "2026-01-04" }
            ]}
        }]));
        let drafts = extract_drafts(&msg).unwrap();
        assert_eq!(drafts.len(), 1);
        assert_eq!(drafts[0].description, "ok");
    }
}
