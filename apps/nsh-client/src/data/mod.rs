//! Device and reactive adapters over domain repositories, with host-owned
//! transactions for capture, measuring evidence and encrypted backup/restore.

pub mod backup;
pub mod backup_file;
pub mod body_metrics;
pub mod catalog;
pub mod clock;
pub mod db;
pub mod favorites;
pub mod finance;
pub mod garmin;
pub mod keyboard;
pub mod market;
pub mod meals;
pub mod notes;
pub mod pending;
pub mod photos;
pub mod scale;
pub mod settings;
pub mod statement_import;
pub mod tasks;
pub mod updates;
pub mod vision;
pub mod webdav;
pub mod weights;

pub mod capture;

pub mod valuation;

pub mod history;
