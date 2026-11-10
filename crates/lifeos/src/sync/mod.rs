//! Sync v3 client: row-state, LWW, accepted acknowledgements and
//! per-domain reset generations. The backend (`apps/backend`) implements
//! the server half of this exact contract; see `docs/sync/sync-v3.md`.

pub mod adapter;
pub mod auth;
pub mod engine;
pub mod outbox;
pub mod registry;
pub mod stamp;
pub mod transport;
pub mod types;

pub use adapter::{SqlTableAdapter, TableAdapter};
pub use engine::{
    AuthTokenProvider, DomainResetHandler, MAX_CHANGES, SettingsTokenProvider, SyncEngine,
    SyncOutcome, ensure_identity,
};
pub use registry::SyncRegistry;
pub use stamp::{MutationStamper, Stamp};
pub use transport::{SYNC_PROTOCOL_VERSION, SyncTransport};
pub use types::{Domain, RowAck, RowChange, SyncRequest, SyncResponse};

/// Sync metadata carried by every syncable row (mirrors the Flutter
/// `SyncMeta`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SyncMeta {
    pub owner_user_id: String,
    pub updated_at: i64,
    pub updated_by_device: String,
    pub hlc: String,
    pub deleted_at: Option<i64>,
}

impl SyncMeta {
    pub fn from_stamp(stamp: &Stamp) -> Self {
        Self {
            owner_user_id: stamp.owner_user_id.clone(),
            updated_at: stamp.now.div_euclid(1000),
            updated_by_device: stamp.device_id.clone(),
            hlc: stamp.hlc.clone(),
            deleted_at: None,
        }
    }

    pub fn deleted(mut self, deleted_at: i64) -> Self {
        self.deleted_at = Some(deleted_at);
        self
    }
}
