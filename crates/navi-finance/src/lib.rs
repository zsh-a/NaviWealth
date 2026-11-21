//! NaviWealth's money truth, shared by every client: a double-entry journal
//! in account currency minor units and the balances, spending and net worth derived
//! from it; statement parsing for Alipay, WeChat Pay and CMB credit cards;
//! and the import that turns statement rows into balanced transactions.
//! Domain calculations are pure Rust; the repository owns confirmed SQLite writes.

/// The SHA-256 of `bytes` as lowercase hex — the integrity-fingerprint
/// form every persisted digest uses.
pub fn sha256_hex(bytes: &[u8]) -> String {
    use sha2::{Digest, Sha256};
    Sha256::digest(bytes)
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

pub mod account;
pub mod assets;
pub mod attribution;
pub mod catalog;
pub mod currency;
pub mod history;
pub mod holdings;
pub mod import;
pub mod journal;
pub mod market;
pub mod money;
pub mod recognition;
pub mod repository;
pub mod review;
pub mod statement;

pub mod valuation;

pub mod history_provider;
