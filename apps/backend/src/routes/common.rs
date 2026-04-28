use worker::Headers;

use crate::error::AppError;

pub const SUPPORTED_PROTOCOL_VERSION: &str = "1";

/// Enforce `Sync-Protocol-Version: 1` on sync-domain endpoints. Missing
/// header is allowed (back-compat with `/health`); only an explicit mismatch
/// triggers 426 — see docs/sync-protocol.md §10.
pub fn check_protocol_version(headers: &Headers) -> Result<(), AppError> {
    if let Ok(Some(v)) = headers.get("Sync-Protocol-Version") {
        if v != SUPPORTED_PROTOCOL_VERSION {
            return Err(AppError::protocol_version());
        }
    }
    Ok(())
}
