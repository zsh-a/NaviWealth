//! Identifier and clock helpers.

/// A fresh opaque row id (UUID v4).
pub fn new_id() -> String {
    uuid::Uuid::new_v4().to_string()
}

/// Current wall-clock milliseconds since the Unix epoch.
pub fn now_millis() -> i64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64
}

/// Current wall-clock seconds since the Unix epoch (row timestamp columns).
pub fn now_secs() -> i64 {
    now_millis().div_euclid(1000)
}
