use chrono::Utc;
use serde::Deserialize;
use worker::{D1Database, D1Type};

use crate::error::AppError;
use crate::hlc::{Hlc, SERVER_NODE_ID};

/// Persisted server-side HLC clock state for one user (single row in
/// `sync_state`). `node_id` is implicitly the server node id.
#[derive(Clone, Copy, Debug)]
pub struct ServerClock {
    pub phys_ms: u64,
    pub logical: u16,
}

impl ServerClock {
    pub const fn zero() -> Self {
        Self {
            phys_ms: 0,
            logical: 0,
        }
    }

    pub fn as_hlc(&self) -> Hlc {
        Hlc {
            phys_ms: self.phys_ms,
            logical: self.logical,
            node_id: SERVER_NODE_ID,
        }
    }
}

#[derive(Deserialize)]
struct ClockRow {
    server_phys_ms: String,
    server_logical: i64,
}

pub async fn load(db: &D1Database, user_id: &str) -> Result<ServerClock, AppError> {
    let row: Option<ClockRow> = db
        .prepare("SELECT server_phys_ms, server_logical FROM sync_state WHERE user_id = ?1")
        .bind_refs([&D1Type::Text(user_id)])
        .map_err(|e| AppError::Internal(format!("bind: {e}")))?
        .first(None)
        .await
        .map_err(|e| AppError::Internal(format!("d1 first: {e}")))?;
    Ok(match row {
        Some(r) => ServerClock {
            phys_ms: r.server_phys_ms.parse::<u64>().unwrap_or(0),
            logical: r.server_logical.clamp(0, u16::MAX as i64) as u16,
        },
        None => ServerClock::zero(),
    })
}

pub async fn save(db: &D1Database, user_id: &str, clock: ServerClock) -> Result<(), AppError> {
    let now = Utc::now().to_rfc3339();
    let phys = clock.phys_ms.to_string();
    let logical: i32 = clock.logical as i32;
    db.prepare(
        "INSERT INTO sync_state (user_id, server_phys_ms, server_logical, updated_at)
         VALUES (?1, ?2, ?3, ?4)
         ON CONFLICT(user_id) DO UPDATE SET
            server_phys_ms = excluded.server_phys_ms,
            server_logical = excluded.server_logical,
            updated_at     = excluded.updated_at",
    )
    .bind_refs([
        &D1Type::Text(user_id),
        &D1Type::Text(&phys),
        &D1Type::Integer(logical),
        &D1Type::Text(&now),
    ])
    .map_err(|e| AppError::Internal(format!("bind: {e}")))?
    .run()
    .await
    .map_err(|e| AppError::Internal(format!("d1 run: {e}")))?;
    Ok(())
}

/// Compute the next server-stamped HLC, advancing local state.
/// Equivalent to `next(state, max(client_phys, server_now))` per
/// docs/sync-protocol.md §3.4.
pub fn stamp(state: &mut ServerClock, client_phys_ms: u64, server_now_ms: i64) -> Hlc {
    let basis = client_phys_ms.max(server_now_ms.max(0) as u64);
    let local = Hlc {
        phys_ms: state.phys_ms,
        logical: state.logical,
        node_id: SERVER_NODE_ID,
    };
    let next = Hlc::next(local, basis as i64, SERVER_NODE_ID);
    state.phys_ms = next.phys_ms;
    state.logical = next.logical;
    next
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stamp_advances_logical_when_basis_equals_state() {
        let mut state = ServerClock {
            phys_ms: 1000,
            logical: 5,
        };
        let h = stamp(&mut state, 800, 1000);
        assert_eq!(h.phys_ms, 1000);
        assert_eq!(h.logical, 6);
        assert_eq!(state.phys_ms, 1000);
        assert_eq!(state.logical, 6);
    }

    #[test]
    fn stamp_lifts_phys_when_basis_higher() {
        let mut state = ServerClock {
            phys_ms: 1000,
            logical: 5,
        };
        let h = stamp(&mut state, 100, 5000);
        assert_eq!(h.phys_ms, 5000);
        assert_eq!(h.logical, 0);
    }
}
