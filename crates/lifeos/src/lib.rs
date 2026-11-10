//! Domain-neutral contracts, storage, sync and backup for the NaviWealth
//! Rust client (the nsh rewrite).
//!
//! `lifeos` is domain-neutral: it never imports domain business code.
//! Domain crates register their syncable tables through
//! [`sync::TableAdapter`] implementations and own their repositories;
//! cross-domain infrastructure may only touch its own tables
//! (`settings`, `op_outbox`).

pub mod backup;
pub mod db;
pub mod error;
pub mod hlc;
pub mod ids;
pub mod key_store;
pub mod logging;
pub mod money;
pub mod sync;

pub use error::{LifeosError, Result};
