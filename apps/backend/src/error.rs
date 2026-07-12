#![allow(dead_code)]

use serde::Serialize;
use worker::{Response, Result as WorkerResult};

#[derive(Debug, thiserror::Error)]
pub enum AppError {
    #[error("not found")]
    NotFound,
    #[error("unauthorized")]
    Unauthorized,
    #[error("bad request: {0}")]
    BadRequest(String),
    #[error("internal: {0}")]
    Internal(String),
    /// Per-field error code mapping straight onto the wire.
    /// Pre-baked so handlers don't have to duplicate the protocol literals.
    #[error("{message}")]
    Coded {
        status: u16,
        code: &'static str,
        message: String,
    },
}

impl AppError {
    pub fn coded(status: u16, code: &'static str, message: impl Into<String>) -> Self {
        Self::Coded {
            status,
            code,
            message: message.into(),
        }
    }

    /// Push body, batch size or per-row payload over the cap (docs/sync/sync-v3.md).
    pub fn payload_too_large() -> Self {
        Self::coded(
            413,
            "payload_too_large",
            "request payload exceeds the limit",
        )
    }

    /// The batch's `device_id` does not match the JWT-bound device.
    pub fn device_mismatch() -> Self {
        Self::coded(
            400,
            "device_mismatch",
            "device_id does not match the authenticated device",
        )
    }

    pub fn rate_limited() -> Self {
        Self::coded(429, "rate_limited", "rate limit exceeded")
    }

    pub fn protocol_version() -> Self {
        Self::coded(426, "protocol_version", "unsupported sync protocol version")
    }

    pub fn status(&self) -> u16 {
        match self {
            Self::NotFound => 404,
            Self::Unauthorized => 401,
            Self::BadRequest(_) => 400,
            Self::Internal(_) => 500,
            Self::Coded { status, .. } => *status,
        }
    }

    pub fn code(&self) -> &'static str {
        match self {
            Self::NotFound => "not_found",
            Self::Unauthorized => "unauthorized",
            Self::BadRequest(_) => "bad_request",
            Self::Internal(_) => "internal",
            Self::Coded { code, .. } => code,
        }
    }

    pub fn log(&self) {
        if let Self::Internal(msg) = self {
            worker::console_log!("internal error: {msg}");
        }
    }

    pub fn into_response(self) -> WorkerResult<Response> {
        let body = ErrorBody {
            code: self.code(),
            message: self.to_string(),
        };
        Response::from_json(&body).map(|r| r.with_status(self.status()))
    }
}

impl From<worker::Error> for AppError {
    fn from(e: worker::Error) -> Self {
        Self::Internal(e.to_string())
    }
}

#[derive(Serialize)]
struct ErrorBody {
    code: &'static str,
    message: String,
}
