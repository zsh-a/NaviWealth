//! Versioned JSON keeps provider DTOs outside the generated FFI surface.
use anyhow::Result;

pub async fn market_request(request_id: String, request_json: String) -> Result<String> {
    crate::market::request(request_id, request_json).await
}

pub async fn market_cancel(request_id: String) {
    crate::market::cancel(&request_id);
}
