//! The user's settings: the model account, the optional daily goal and the
//! models photos may go to without asking. The API key is kept under its
//! own storage key on the device, never with the rest, never logged.

use nsh_core::{prelude::*, storage::Storage};
use serde::{Deserialize, Serialize};

use crate::domain::account::ModelAccount;

const KEY: &str = "settings.v1";
const KEY_SECRET: &str = "secret.model-key.v1";

/// The lowest and highest daily goal accepted, in kcal.
pub const GOAL_RANGE: std::ops::RangeInclusive<f64> = 500.0..=10_000.0;

/// Everything the user set.
#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize)]
pub struct Settings {
    pub account: Option<ModelAccount>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub goal_kcal: Option<f64>,
    /// Account fingerprints the user chose not to be asked about again.
    #[serde(default)]
    pub trusted: Vec<String>,
}

fn settings() -> Signal<Settings> {
    global::<Settings>()
}

/// Reads the kept settings; the root calls it once.
pub fn load() {
    let mut loaded: Settings = Storage::get_item(KEY)
        .and_then(|raw| serde_json::from_str(&raw).ok())
        .unwrap_or_default();
    if let Some(account) = loaded.account.as_mut() {
        account.api_key = Storage::get_item(KEY_SECRET).unwrap_or_default();
    }
    loaded.goal_kcal = loaded.goal_kcal.filter(|goal| GOAL_RANGE.contains(goal));
    settings().set(loaded);
}

fn persist(value: &Settings) {
    let key = value
        .account
        .as_ref()
        .map(|account| account.api_key.trim().to_owned())
        .unwrap_or_default();
    let stored = match serde_json::to_string(value) {
        Ok(json) => Storage::set_item(KEY, json),
        Err(_) => Ok(()),
    };
    let secret = if key.is_empty() {
        Storage::remove_item(KEY_SECRET);
        Ok(())
    } else {
        Storage::set_item(KEY_SECRET, key)
    };
    if stored.is_err() || secret.is_err() {
        log::error!("settings: device storage is full; the change was not kept");
    }
}

/// The settings (tracked).
pub fn current() -> Settings {
    settings().get()
}

/// The account, when it can send photos (tracked).
pub fn ready_account() -> Option<ModelAccount> {
    settings().with(|s| s.account.clone().filter(ModelAccount::is_ready))
}

/// The daily goal in kcal, when set (tracked).
pub fn goal() -> Option<f64> {
    settings().with(|s| s.goal_kcal)
}

/// Whether photos may go to `account` without asking (tracked).
pub fn is_trusted(account: &ModelAccount) -> bool {
    let fingerprint = account.fingerprint();
    settings().with(|s| s.trusted.contains(&fingerprint))
}

/// Stops (or starts) asking before photos go to `account`.
pub fn set_trusted(account: &ModelAccount, trusted: bool) {
    let fingerprint = account.fingerprint();
    settings().update(|s| {
        s.trusted.retain(|kept| *kept != fingerprint);
        if trusted {
            s.trusted.push(fingerprint);
        }
        persist(s);
    });
}

/// Keeps `account` as the model account. Photos go to a changed account
/// only after asking again: trust belongs to an account's fingerprint.
pub fn save_account(account: ModelAccount) {
    settings().update(|s| {
        s.account = Some(account);
        persist(s);
    });
}

/// Keeps the daily goal (`None` clears it; out of range is not kept).
pub fn save_goal(goal_kcal: Option<f64>) {
    settings().update(|s| {
        s.goal_kcal = goal_kcal.filter(|goal| GOAL_RANGE.contains(goal));
        persist(s);
    });
}
