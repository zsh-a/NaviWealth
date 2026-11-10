//! Sync v3 wire types. These mirror `apps/backend/src/routes/sync.rs` and
//! `apps/backend/src/sync/store.rs` field for field — the client and the
//! backend are delivered on the same new contract.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

pub use crate::error::Domain;

/// One row-state change. Pushes carry the full row payload (or `None` for
/// a bare delete); pulls return stored rows, with tombstones as `{}` +
/// `deleted = true`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RowChange {
    pub table: String,
    pub id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub payload: Option<serde_json::Value>,
    /// Opaque, lexicographically-ordered LWW token (the row's HLC).
    pub version: String,
    #[serde(default)]
    pub deleted: bool,
    /// Author device. Server-set on outbound rows; ignored on inbound.
    #[serde(default)]
    pub device_id: String,
    /// Server-assigned cursor. Meaningful on outbound rows only.
    #[serde(default)]
    pub seq: i64,
    /// Domain reset generation. A stale generation is never accepted.
    #[serde(default)]
    pub generation: i64,
}

/// Protocol/domain acceptance for a pushed row. The client only clears
/// matching outbox pointers, so rejected rows cannot be silently lost.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RowAck {
    pub table: String,
    pub id: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct SyncRequest {
    pub device_id: String,
    #[serde(default)]
    pub since: i64,
    #[serde(default)]
    pub changes: Vec<RowChange>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct SyncResponse {
    /// Cursor the client adopts after applying this page.
    pub seq: i64,
    #[serde(default)]
    pub changes: Vec<RowChange>,
    #[serde(default)]
    pub more: bool,
    #[serde(default)]
    pub accepted: Vec<RowAck>,
    /// Authoritative reset generation for every domain in the JWT claim.
    #[serde(default)]
    pub domain_generations: BTreeMap<String, i64>,
}

/// `POST /sync/reset-domain` response.
#[derive(Debug, Clone, Deserialize)]
pub struct ResetDomainResponse {
    pub domain: String,
    pub generation: i64,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn row_change_roundtrip_matches_backend_field_names() {
        let change = RowChange {
            table: "fin:accounts".into(),
            id: "a1".into(),
            payload: Some(serde_json::json!({"id": "a1", "name": "Cash"})),
            version: "123.0000-dev".into(),
            deleted: false,
            device_id: "d1".into(),
            seq: 0,
            generation: 1,
        };
        let json = serde_json::to_value(&change).unwrap();
        assert_eq!(json["table"], "fin:accounts");
        assert_eq!(json["version"], "123.0000-dev");
        assert_eq!(json["generation"], 1);
        // seq is 0 (default) but still serialized — matches the backend
        // struct which always writes the field.
        assert!(json.get("seq").is_some());

        let back: RowChange = serde_json::from_value(json).unwrap();
        assert_eq!(back, change);
    }
}
