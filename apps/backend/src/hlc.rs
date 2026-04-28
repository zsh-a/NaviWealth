#![allow(dead_code)]

use std::cmp::Ordering;
use std::fmt;

use serde::{Deserialize, Deserializer, Serialize, Serializer};
use uuid::Uuid;

/// Server stamps its own HLCs with a fixed nil UUID node id, per
/// docs/sync-protocol.md §3.1.
pub const SERVER_NODE_ID: Uuid = Uuid::nil();

/// Hard cap on `phys_ms` skew: ops whose physical time exceeds
/// `server_now + CLOCK_SKEW_CAP_MS` are rejected with `clock_skew_too_large`
/// (docs/sync-protocol.md §3.5).
pub const CLOCK_SKEW_CAP_MS: i64 = 60_000;

/// Logical counter range. `u16` overflow bumps `phys_ms` artificially.
const LOGICAL_MAX: u32 = 1 << 16;

/// Hybrid Logical Clock — `(phys_ms, logical, node_id)`.
#[derive(Clone, Copy, Debug, Eq, PartialEq, Hash)]
pub struct Hlc {
    pub phys_ms: u64,
    pub logical: u16,
    pub node_id: Uuid,
}

impl Hlc {
    pub const fn new(phys_ms: u64, logical: u16, node_id: Uuid) -> Self {
        Self {
            phys_ms,
            logical,
            node_id,
        }
    }

    /// The "zero" HLC — strictly less than every real one. Usable as the
    /// default `since` cursor on first sync.
    pub const fn zero() -> Self {
        Self {
            phys_ms: 0,
            logical: 0,
            node_id: Uuid::nil(),
        }
    }

    /// Local update rule (docs/sync-protocol.md §3.3).
    pub fn next(local: Hlc, now_ms: i64, node_id: Uuid) -> Hlc {
        let now_clamped = now_ms.max(0) as u64;
        let pmax = local.phys_ms.max(now_clamped);
        let mut logical = if local.phys_ms == pmax {
            local.logical as u32 + 1
        } else {
            0
        };
        let mut phys = pmax;
        if logical >= LOGICAL_MAX {
            phys += 1;
            logical = 0;
        }
        Hlc {
            phys_ms: phys,
            logical: logical as u16,
            node_id,
        }
    }

    /// Three-way merge rule (docs/sync-protocol.md §3.3).
    pub fn merge(local: Hlc, recv: Hlc, now_ms: i64, node_id: Uuid) -> Hlc {
        let now_clamped = now_ms.max(0) as u64;
        let pmax = local.phys_ms.max(recv.phys_ms).max(now_clamped);
        let logical_u32 = if local.phys_ms == pmax && recv.phys_ms == pmax {
            local.logical.max(recv.logical) as u32 + 1
        } else if local.phys_ms == pmax {
            local.logical as u32 + 1
        } else if recv.phys_ms == pmax {
            recv.logical as u32 + 1
        } else {
            0
        };
        let (phys, logical) = if logical_u32 >= LOGICAL_MAX {
            (pmax + 1, 0)
        } else {
            (pmax, logical_u32 as u16)
        };
        Hlc {
            phys_ms: phys,
            logical,
            node_id,
        }
    }

    /// Canonical wire form: `<phys>.<logical:%04x>-<node_id>` (§3.1).
    pub fn to_canonical(self) -> String {
        format!(
            "{}.{:04x}-{}",
            self.phys_ms,
            self.logical,
            self.node_id.as_hyphenated()
        )
    }

    pub fn parse(s: &str) -> Result<Hlc, HlcParseError> {
        let dot = s.find('.').ok_or(HlcParseError::MissingDot)?;
        let dash = s[dot + 1..].find('-').ok_or(HlcParseError::MissingDash)?;
        let phys_str = &s[..dot];
        let logical_str = &s[dot + 1..dot + 1 + dash];
        let node_str = &s[dot + 1 + dash + 1..];

        let phys_ms: u64 = phys_str.parse().map_err(|_| HlcParseError::BadPhys)?;
        if logical_str.len() != 4 {
            return Err(HlcParseError::BadLogical);
        }
        let logical: u16 =
            u16::from_str_radix(logical_str, 16).map_err(|_| HlcParseError::BadLogical)?;
        let node_id: Uuid = node_str.parse().map_err(|_| HlcParseError::BadNode)?;

        Ok(Hlc {
            phys_ms,
            logical,
            node_id,
        })
    }
}

impl fmt::Display for Hlc {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&(*self).to_canonical())
    }
}

impl Ord for Hlc {
    fn cmp(&self, other: &Self) -> Ordering {
        (self.phys_ms, self.logical, self.node_id.as_bytes()).cmp(&(
            other.phys_ms,
            other.logical,
            other.node_id.as_bytes(),
        ))
    }
}

impl PartialOrd for Hlc {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

#[derive(Debug, thiserror::Error, Eq, PartialEq)]
pub enum HlcParseError {
    #[error("missing '.' separator")]
    MissingDot,
    #[error("missing '-' separator")]
    MissingDash,
    #[error("invalid phys_ms")]
    BadPhys,
    #[error("invalid logical counter")]
    BadLogical,
    #[error("invalid node id")]
    BadNode,
}

impl Serialize for Hlc {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.collect_str(&self.to_canonical())
    }
}

impl<'de> Deserialize<'de> for Hlc {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        let raw = String::deserialize(d)?;
        Hlc::parse(&raw).map_err(serde::de::Error::custom)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dev() -> Uuid {
        Uuid::parse_str("1f5b0c3a-4e2d-4d31-9b77-3f7c1f0d2c01").unwrap()
    }

    #[test]
    fn sp_a_1_next_advances_logical_when_phys_equal() {
        let local = Hlc::new(1000, 5, dev());
        let n = Hlc::next(local, 1000, dev());
        assert_eq!(n, Hlc::new(1000, 6, dev()));
    }

    #[test]
    fn sp_a_2_next_resets_logical_when_phys_advances() {
        let local = Hlc::new(1000, 99, dev());
        let n = Hlc::next(local, 1500, dev());
        assert_eq!(n, Hlc::new(1500, 0, dev()));
    }

    #[test]
    fn sp_a_3_next_keeps_pmax_when_local_gt_now() {
        let local = Hlc::new(2000, 0, dev());
        let n = Hlc::next(local, 1500, dev());
        assert_eq!(n, Hlc::new(2000, 1, dev()));
    }

    #[test]
    fn sp_a_4_merge_takes_max_of_three_sources() {
        let local = Hlc::new(1000, 3, dev());
        let recv = Hlc::new(1500, 7, dev());
        let m = Hlc::merge(local, recv, 1200, dev());
        assert_eq!(m, Hlc::new(1500, 8, dev()));
    }

    #[test]
    fn sp_a_5_logical_overflow_bumps_phys() {
        let local = Hlc::new(1000, u16::MAX, dev());
        let n = Hlc::next(local, 1000, dev());
        assert_eq!(n, Hlc::new(1001, 0, dev()));
    }

    #[test]
    fn sp_a_6_canonical_string_roundtrip() {
        let h = Hlc::new(1714291200000, 1, dev());
        let s = h.to_canonical();
        assert_eq!(Hlc::parse(&s).unwrap(), h);
    }

    #[test]
    fn sp_a_7_lex_order_matches_tuple_order() {
        let cases = [
            (Hlc::new(1000, 0, dev()), Hlc::new(1001, 0, dev())),
            (Hlc::new(1000, 0, dev()), Hlc::new(1000, 1, dev())),
            (Hlc::new(1000, 0, Uuid::nil()), Hlc::new(1000, 0, dev())),
        ];
        for (a, b) in cases {
            assert_eq!(a.cmp(&b), Ordering::Less);
            assert_eq!(a.to_canonical().cmp(&b.to_canonical()), Ordering::Less);
        }
    }

    #[test]
    fn parse_rejects_short_logical() {
        assert_eq!(
            Hlc::parse("1000.1-1f5b0c3a-4e2d-4d31-9b77-3f7c1f0d2c01"),
            Err(HlcParseError::BadLogical)
        );
    }
}
