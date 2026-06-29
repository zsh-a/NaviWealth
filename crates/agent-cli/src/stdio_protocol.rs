use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Deserialize)]
pub(crate) struct StdioRequest {
    #[serde(default)]
    pub(crate) jsonrpc: Option<String>,
    #[serde(default)]
    pub(crate) id: Option<Value>,
    pub(crate) method: String,
    #[serde(default)]
    pub(crate) params: Value,
}

#[derive(Debug, Serialize)]
pub(crate) struct StdioResponse {
    pub(crate) jsonrpc: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(crate) id: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(crate) result: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(crate) error: Option<StdioError>,
}

#[derive(Debug, Serialize)]
pub(crate) struct StdioError {
    code: i32,
    message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    data: Option<Value>,
}

pub(crate) fn stdio_result(id: Option<Value>, result: Value) -> StdioResponse {
    StdioResponse {
        jsonrpc: "2.0",
        id,
        result: Some(result),
        error: None,
    }
}

pub(crate) fn stdio_error(
    id: Option<Value>,
    code: i32,
    message: impl Into<String>,
) -> StdioResponse {
    StdioResponse {
        jsonrpc: "2.0",
        id,
        result: None,
        error: Some(StdioError {
            code,
            message: message.into(),
            data: None,
        }),
    }
}

pub(crate) fn stdio_error_with_data(
    id: Option<Value>,
    code: i32,
    message: impl Into<String>,
    data: Value,
) -> StdioResponse {
    StdioResponse {
        jsonrpc: "2.0",
        id,
        result: None,
        error: Some(StdioError {
            code,
            message: message.into(),
            data: Some(data),
        }),
    }
}
