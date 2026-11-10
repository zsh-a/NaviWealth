//! Write-side stamping: every local mutation gets one HLC tick, an owner
//! and a device id, committed atomically with the write itself.

use rusqlite::Connection;

use crate::error::Result;
use crate::hlc::{Hlc, HlcClock};
use crate::ids;

use crate::db::settings;

/// The KV key holding the device's running HLC clock.
pub const HLC_KEY: &str = "sync.hlc";
/// The KV key holding the owner user id.
pub const OWNER_KEY: &str = "sync.owner_user_id";
/// The KV key holding this device's id.
pub const DEVICE_KEY: &str = "sync.device_id";

/// One stamped mutation.
#[derive(Debug, Clone)]
pub struct Stamp {
    pub owner_user_id: String,
    pub device_id: String,
    pub hlc: String,
    pub now: i64,
}

/// Issues stamps for one owner + device. Methods run on the DB thread so
/// the tick, the write and the outbox pointers share one transaction.
#[derive(Debug, Clone)]
pub struct MutationStamper {
    pub owner_user_id: String,
    pub device_id: String,
}

impl MutationStamper {
    pub fn new(owner_user_id: impl Into<String>, device_id: impl Into<String>) -> Self {
        Self {
            owner_user_id: owner_user_id.into(),
            device_id: device_id.into(),
        }
    }

    /// Produce the next stamp. Call once per mutation, inside the same
    /// transaction that writes the rows.
    pub fn stamp(&self, conn: &Connection) -> Result<Stamp> {
        let now = ids::now_millis();
        let last = read_clock(conn, &self.device_id)?;
        let mut clock = HlcClock::new(last);
        let next = clock.tick(now);
        settings::set_setting(conn, HLC_KEY, &next.to_string())?;
        Ok(Stamp {
            owner_user_id: self.owner_user_id.clone(),
            device_id: self.device_id.clone(),
            hlc: next.to_string(),
            now,
        })
    }

    /// Fold a remote version into the local clock (sync apply, restore).
    pub fn merge_remote(&self, conn: &Connection, version: &str) -> Result<()> {
        let remote = Hlc::parse(version)?;
        let now = ids::now_millis();
        let last = read_clock(conn, &self.device_id)?;
        let mut clock = HlcClock::new(last);
        let merged = clock.merge(&remote, now);
        settings::set_setting(conn, HLC_KEY, &merged.to_string())?;
        Ok(())
    }
}

fn read_clock(conn: &Connection, device_id: &str) -> Result<Hlc> {
    match settings::get_setting(conn, HLC_KEY)? {
        Some(packed) => Ok(Hlc::parse(&packed)?),
        None => Ok(Hlc::zero(device_id)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::Db;

    #[tokio::test]
    async fn stamps_increase_strictly() {
        let db = Db::open_in_memory().unwrap();
        let stamper = MutationStamper::new("user-1", "device-1");
        db.call_sync(move |conn| {
            let a = stamper.stamp(conn)?;
            let b = stamper.stamp(conn)?;
            assert_ne!(a.hlc, b.hlc);
            assert!(b.hlc.as_str() > a.hlc.as_str());
            assert_eq!(a.owner_user_id, "user-1");
            assert_eq!(a.device_id, "device-1");
            Ok(())
        })
        .unwrap();
    }
}
