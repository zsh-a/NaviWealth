use worker::Headers;

use crate::error::AppError;

pub const SUPPORTED_PROTOCOL_VERSION: &str = "3";

/// Enforce `Sync-Protocol-Version: 2` on sync-domain endpoints. A missing
/// header is allowed (back-compat with `/health`); only an explicit mismatch
/// triggers 426 — see docs/sync/sync-v3.md.
pub fn check_protocol_version(headers: &Headers) -> Result<(), AppError> {
    if let Ok(Some(v)) = headers.get("Sync-Protocol-Version") {
        if v != SUPPORTED_PROTOCOL_VERSION {
            return Err(AppError::protocol_version());
        }
    }
    Ok(())
}
