//! Hybrid Logical Clock, ported from the Flutter client's
//! `apps/mobile/lib/core/sync/hlc.dart` so both stacks produce the same
//! canonical string and total order.
//!
//! Pairs wall time with a monotonically-increasing logical counter so two
//! events still get a stable total order even when one device's clock
//! drifts backwards. The total order is `(wallMillis, counter, nodeId)`
//! lexicographically — `nodeId` is only the final tie-breaker and never
//! affects causality.
//!
//! Canonical string form: `<wallMillis>.<counter:%04x>-<nodeId>`. The dot
//! separator and zero-padded hex counter make the string sort
//! lexicographically the same as the tuple, which is why sync v3 uses it
//! directly as the opaque, ordered `version` token.

use std::cmp::Ordering;
use std::fmt;

/// Logical counter is u16; overflow bumps `wallMillis`.
pub const COUNTER_MAX: u16 = 0xFFFF;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Hlc {
    /// Local wall-clock reading (milliseconds since the Unix epoch) at the
    /// moment the event was generated *or* observed — whichever is later.
    pub wall_millis: i64,
    /// Logical counter. Resets to 0 each time `wallMillis` increases.
    pub counter: u16,
    /// Stable per-device identifier. Tie-breaker only.
    pub node_id: String,
}

#[derive(Debug, thiserror::Error)]
#[error("malformed HLC: {0}")]
pub struct HlcError(pub String);

impl Hlc {
    /// Initial HLC for a node with no prior history.
    pub fn zero(node_id: impl Into<String>) -> Self {
        Self {
            wall_millis: 0,
            counter: 0,
            node_id: node_id.into(),
        }
    }

    /// Generate the next local HLC tick for a new event on this node.
    ///
    /// `last_seen` is the most recent HLC observed locally (whether
    /// generated or received). `now_millis` is the wall reading (injected
    /// in tests).
    pub fn tick(last_seen: &Hlc, now_millis: i64) -> Self {
        if now_millis > last_seen.wall_millis {
            return Self {
                wall_millis: now_millis,
                counter: 0,
                node_id: last_seen.node_id.clone(),
            };
        }
        let next_counter = u32::from(last_seen.counter) + 1;
        if next_counter > u32::from(COUNTER_MAX) {
            return Self {
                wall_millis: last_seen.wall_millis + 1,
                counter: 0,
                node_id: last_seen.node_id.clone(),
            };
        }
        Self {
            wall_millis: last_seen.wall_millis,
            counter: next_counter as u16,
            node_id: last_seen.node_id.clone(),
        }
    }

    /// Merge a remote HLC into the local clock when receiving an event.
    ///
    /// Per the HLC paper:
    /// - if the wall clock leads both, take wall + counter 0;
    /// - if local leads, bump the local counter;
    /// - if remote leads, take remote wall + counter+1;
    /// - if they tie on wall, take max(counter)+1.
    pub fn merge(local: &Hlc, remote: &Hlc, now_millis: i64) -> Self {
        let max_wall = now_millis.max(local.wall_millis).max(remote.wall_millis);

        let next_counter: u32 = if max_wall == local.wall_millis && max_wall == remote.wall_millis {
            u32::from(local.counter.max(remote.counter)) + 1
        } else if max_wall == local.wall_millis {
            u32::from(local.counter) + 1
        } else if max_wall == remote.wall_millis {
            u32::from(remote.counter) + 1
        } else {
            0
        };

        if next_counter > u32::from(COUNTER_MAX) {
            return Self {
                wall_millis: max_wall + 1,
                counter: 0,
                node_id: local.node_id.clone(),
            };
        }
        Self {
            wall_millis: max_wall,
            counter: next_counter as u16,
            node_id: local.node_id.clone(),
        }
    }

    /// Parse the canonical string form `<wallMillis>.<counter:%04x>-<nodeId>`.
    /// Malformed input is a non-recoverable corruption signal.
    pub fn parse(packed: &str) -> Result<Self, HlcError> {
        let malformed = || HlcError(packed.to_owned());
        let dot = packed.find('.').ok_or_else(&malformed)?;
        let dash = packed[dot + 1..]
            .find('-')
            .map(|i| i + dot + 1)
            .ok_or_else(&malformed)?;
        if dot < 1 {
            return Err(malformed());
        }
        let wall_str = &packed[..dot];
        let counter_str = &packed[dot + 1..dash];
        let node = &packed[dash + 1..];
        if node.is_empty() {
            return Err(malformed());
        }
        let wall_millis: i64 = wall_str.parse().map_err(|_| malformed())?;
        if wall_millis < 0 {
            return Err(malformed());
        }
        if counter_str.len() != 4 {
            return Err(malformed());
        }
        let counter = u16::from_str_radix(counter_str, 16).map_err(|_| malformed())?;
        Ok(Self {
            wall_millis,
            counter,
            node_id: node.to_owned(),
        })
    }
}

impl fmt::Display for Hlc {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "{}.{:04x}-{}",
            self.wall_millis, self.counter, self.node_id
        )
    }
}

impl Ord for Hlc {
    fn cmp(&self, other: &Self) -> Ordering {
        self.wall_millis
            .cmp(&other.wall_millis)
            .then(self.counter.cmp(&other.counter))
            .then(self.node_id.cmp(&other.node_id))
    }
}

impl PartialOrd for Hlc {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

/// The device's running clock: the most recent HLC observed locally,
/// persisted across launches (`settings.sync.hlc`).
#[derive(Debug, Clone)]
pub struct HlcClock {
    last: Hlc,
}

impl HlcClock {
    pub fn new(last: Hlc) -> Self {
        Self { last }
    }

    pub fn last(&self) -> &Hlc {
        &self.last
    }

    pub fn tick(&mut self, now_millis: i64) -> Hlc {
        self.last = Hlc::tick(&self.last, now_millis);
        self.last.clone()
    }

    pub fn merge(&mut self, remote: &Hlc, now_millis: i64) -> Hlc {
        self.last = Hlc::merge(&self.last, remote, now_millis);
        self.last.clone()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn canonical_string_sorts_like_the_tuple() {
        let a = Hlc {
            wall_millis: 1_000,
            counter: 1,
            node_id: "a".into(),
        };
        let b = Hlc {
            wall_millis: 1_000,
            counter: 2,
            node_id: "a".into(),
        };
        let c = Hlc {
            wall_millis: 1_001,
            counter: 0,
            node_id: "a".into(),
        };
        let d = Hlc {
            wall_millis: 1_000,
            counter: 0xFFFF,
            node_id: "a".into(),
        };
        assert!(a < b);
        assert!(b < c);
        assert!(b < d);
        assert!(d < c);
        // Lexicographic string order matches Ord.
        let mut strings = [a.to_string(), b.to_string(), c.to_string(), d.to_string()];
        strings.sort_unstable();
        let mut parsed: Vec<Hlc> = strings.iter().map(|s| Hlc::parse(s).unwrap()).collect();
        parsed.sort();
        assert_eq!(parsed, vec![a, b, d, c]);
    }

    #[test]
    fn display_and_parse_roundtrip() {
        let h = Hlc {
            wall_millis: 1_767_258_000_123,
            counter: 0x00ab,
            node_id: "dev-1".into(),
        };
        let s = h.to_string();
        assert_eq!(s, "1767258000123.00ab-dev-1");
        assert_eq!(Hlc::parse(&s).unwrap(), h);
    }

    #[test]
    fn parse_rejects_malformed_input() {
        for bad in [
            "",
            "no-dot",
            ".00ab-node",
            "1.0ab-node",
            "1.00ab-",
            "1.00a-node",
            "-1.00ab-node",
        ] {
            assert!(Hlc::parse(bad).is_err(), "should reject {bad:?}");
        }
    }

    #[test]
    fn tick_advances_within_and_across_millis() {
        let node = "n1";
        let mut clock = HlcClock::new(Hlc::zero(node));
        let first = clock.tick(1_000);
        assert_eq!(
            first,
            Hlc {
                wall_millis: 1_000,
                counter: 0,
                node_id: node.into()
            }
        );
        let second = clock.tick(1_000);
        assert_eq!(second.counter, 1);
        // Backward wall jump must not go back.
        let third = clock.tick(500);
        assert_eq!(third.wall_millis, 1_000);
        assert_eq!(third.counter, 2);
        let fourth = clock.tick(1_001);
        assert_eq!(
            fourth,
            Hlc {
                wall_millis: 1_001,
                counter: 0,
                node_id: node.into()
            }
        );
    }

    #[test]
    fn tick_counter_overflow_bumps_wall() {
        let last = Hlc {
            wall_millis: 5_000,
            counter: COUNTER_MAX,
            node_id: "n".into(),
        };
        let next = Hlc::tick(&last, 5_000);
        assert_eq!(
            next,
            Hlc {
                wall_millis: 5_001,
                counter: 0,
                node_id: "n".into()
            }
        );
    }

    #[test]
    fn merge_follows_the_hlc_paper() {
        let node = "local";
        let mut clock = HlcClock::new(Hlc::zero(node));

        // Remote leads: take remote wall + counter+1.
        let remote = Hlc {
            wall_millis: 2_000,
            counter: 5,
            node_id: "r".into(),
        };
        let merged = clock.merge(&remote, 1_000);
        assert_eq!(merged.wall_millis, 2_000);
        assert_eq!(merged.counter, 6);
        assert_eq!(merged.node_id, node);

        // Local leads: bump local counter.
        let stale = Hlc {
            wall_millis: 1_500,
            counter: 9,
            node_id: "r".into(),
        };
        let merged = clock.merge(&stale, 1_500);
        assert_eq!(merged.wall_millis, 2_000);
        assert_eq!(merged.counter, 7);

        // Tie on wall: max(counter)+1.
        let tie = Hlc {
            wall_millis: 2_000,
            counter: 50,
            node_id: "r".into(),
        };
        let merged = clock.merge(&tie, 1_999);
        assert_eq!(merged.wall_millis, 2_000);
        assert_eq!(merged.counter, 51);

        // Wall clock leads both: wall + counter 0.
        let merged = clock.merge(&tie, 9_999);
        assert_eq!(
            merged,
            Hlc {
                wall_millis: 9_999,
                counter: 0,
                node_id: node.into()
            }
        );
    }

    #[test]
    fn merge_counter_overflow_bumps_wall() {
        let local = Hlc {
            wall_millis: 7_000,
            counter: COUNTER_MAX,
            node_id: "l".into(),
        };
        let remote = Hlc {
            wall_millis: 7_000,
            counter: COUNTER_MAX,
            node_id: "r".into(),
        };
        let merged = Hlc::merge(&local, &remote, 7_000);
        assert_eq!(merged.wall_millis, 7_001);
        assert_eq!(merged.counter, 0);
    }
}
