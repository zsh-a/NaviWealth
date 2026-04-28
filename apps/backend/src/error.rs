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
}

impl AppError {
    pub fn status(&self) -> u16 {
        match self {
            Self::NotFound => 404,
            Self::Unauthorized => 401,
            Self::BadRequest(_) => 400,
            Self::Internal(_) => 500,
        }
    }

    pub fn code(&self) -> &'static str {
        match self {
            Self::NotFound => "not_found",
            Self::Unauthorized => "unauthorized",
            Self::BadRequest(_) => "bad_request",
            Self::Internal(_) => "internal",
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
