//! NaviWealth's money truth, shared by every client: a double-entry journal
//! in CNY minor units (fen) and the balances, spending and net worth derived
//! from it; statement parsing for Alipay, WeChat Pay and CMB credit cards;
//! and the import that turns statement rows into balanced transactions.
//! Domain calculations are pure Rust; the repository owns confirmed SQLite writes.

pub mod account;
pub mod assets;
pub mod holdings;
pub mod import;
pub mod journal;
pub mod money;
pub mod recognition;
pub mod repository;
pub mod statement;
