//! Recognition inputs and results. Content blocks retain saved-draft compatibility.
use base64::{Engine, engine::general_purpose::STANDARD};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(untagged)]
pub enum MessageContent {
    Text(String),
    Blocks(Vec<ContentBlock>),
}
impl From<String> for MessageContent {
    fn from(s: String) -> Self {
        Self::Text(s)
    }
}
impl From<&str> for MessageContent {
    fn from(s: &str) -> Self {
        Self::Text(s.into())
    }
}
impl From<Vec<ContentBlock>> for MessageContent {
    fn from(v: Vec<ContentBlock>) -> Self {
        Self::Blocks(v)
    }
}
impl MessageContent {
    pub fn blocks(&self) -> Option<&[ContentBlock]> {
        match self {
            Self::Blocks(v) => Some(v),
            _ => None,
        }
    }
    pub fn as_str(&self) -> Option<&str> {
        match self {
            Self::Text(v) => Some(v),
            _ => None,
        }
    }
    pub fn to_value(&self) -> Value {
        serde_json::to_value(self).expect("capture content serializes")
    }
    pub fn as_array(&self) -> Option<Vec<Value>> {
        self.to_value().as_array().cloned()
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ContentBlock {
    Text {
        text: String,
    },
    Image {
        source: ImageSource,
    },
    ToolUse {
        id: String,
        name: String,
        input: Value,
    },
    ToolResult {
        tool_use_id: String,
        content: Value,
        #[serde(default)]
        is_error: Option<bool>,
    },
    Thinking {
        thinking: String,
        #[serde(default)]
        signature: String,
    },
    RedactedThinking {
        data: String,
    },
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ImageSource {
    Base64 {
        media_type: String,
        #[serde(with = "image_bytes")]
        data: Vec<u8>,
    },
}
impl ContentBlock {
    pub fn image(media_type: impl Into<String>, data: Vec<u8>) -> Self {
        Self::Image {
            source: ImageSource::Base64 {
                media_type: media_type.into(),
                data,
            },
        }
    }
    pub fn validate(&self) -> Result<(), LlmError> {
        let valid = match self {
            Self::Image {
                source: ImageSource::Base64 { media_type, data },
            } => {
                !data.is_empty()
                    && data.len() <= 20_000_000
                    && matches!(
                        media_type.as_str(),
                        "image/jpeg" | "image/png" | "image/gif" | "image/webp"
                    )
            }
            Self::ToolUse { id, name, input } => {
                !id.is_empty() && !name.is_empty() && input.is_object()
            }
            Self::ToolResult { tool_use_id, .. } => !tool_use_id.is_empty(),
            _ => true,
        };
        if valid {
            Ok(())
        } else {
            Err(LlmError::new("recognition_invalid_content"))
        }
    }
}
mod image_bytes {
    use super::*;
    pub fn serialize<S: serde::Serializer>(bytes: &[u8], s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&STANDARD.encode(bytes))
    }
    pub fn deserialize<'de, D: serde::Deserializer<'de>>(d: D) -> Result<Vec<u8>, D::Error> {
        STANDARD
            .decode(String::deserialize(d)?)
            .map_err(serde::de::Error::custom)
    }
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LlmRole {
    System,
    User,
    Assistant,
    Tool,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LlmMessage {
    pub role: LlmRole,
    pub content: MessageContent,
    #[serde(default)]
    pub metadata: Value,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LlmRequest {
    pub provider: String,
    pub model: String,
    pub messages: Vec<LlmMessage>,
    #[serde(default)]
    pub temperature: Option<f32>,
    #[serde(default)]
    pub max_output_tokens: Option<u32>,
    #[serde(default)]
    pub tools: Vec<RecognitionTool>,
    #[serde(default)]
    pub response_schema: Option<Value>,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecognitionTool {
    pub name: String,
    pub description: String,
    pub input_schema: Value,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LlmFinishReason {
    Stop,
    Length,
    ToolCall,
    ContentFilter,
    Error,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LlmUsage {
    pub input_tokens: u32,
    pub output_tokens: u32,
    pub total_tokens: u32,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LlmResponse {
    pub provider: String,
    pub model: String,
    pub content: String,
    pub finish_reason: LlmFinishReason,
    pub object: Option<Value>,
    pub usage: Option<LlmUsage>,
    pub metadata: Value,
}
#[derive(Debug, Clone)]
pub struct LlmErrorRecord {
    pub code: String,
    pub details: Value,
}
#[derive(Debug, Clone)]
pub struct LlmError {
    pub record: LlmErrorRecord,
}
impl LlmError {
    pub fn new(code: &str) -> Self {
        Self {
            record: LlmErrorRecord {
                code: code.into(),
                details: json!({}),
            },
        }
    }
}
impl std::fmt::Display for LlmError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.record.code)
    }
}
impl std::error::Error for LlmError {}
