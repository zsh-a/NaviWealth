//! The user's settings: the model account, the optional daily goal and the
//! models photos may go to without asking. The API key is kept under its
//! own storage key on the device, never with the rest, never logged.

use nsh_core::{prelude::*, storage::Storage};
use serde::{Deserialize, Serialize};

use crate::domain::{account::ModelAccount, meal::Day, weight};
use navi_health::bodycomp::{Algorithm, Sex};

const KEY: &str = "settings.v1";
const KEY_SECRET: &str = "secret.model-key.v1";

/// The lowest and highest daily goal accepted, in kcal.
pub const GOAL_RANGE: std::ops::RangeInclusive<f64> = 500.0..=10_000.0;

/// The appearance the app asks for, whatever the device is set to.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum Appearance {
    /// Follow the device (default).
    #[default]
    System,
    /// Always light.
    Light,
    /// Always dark.
    Dark,
}

impl Appearance {
    /// The engine override this choice asks for.
    pub fn scheme(self) -> nsh_core::platform::Appearance {
        match self {
            Self::System => nsh_core::platform::Appearance::System,
            Self::Light => nsh_core::platform::Appearance::Light,
            Self::Dark => nsh_core::platform::Appearance::Dark,
        }
    }
}

/// The plausible height range, in centimetres (the scale profiles agree).
pub const HEIGHT_RANGE: std::ops::RangeInclusive<u16> = 80..=230;
/// The plausible age range, in years (the scale profiles agree).
pub use navi_health::profile::AGE_RANGE;

/// Everything the user set.
#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize)]
pub struct Settings {
    pub account: Option<ModelAccount>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub goal_kcal: Option<f64>,
    /// Account fingerprints the user chose not to be asked about again.
    #[serde(default)]
    pub trusted: Vec<String>,
    #[serde(default)]
    pub ledger: LedgerDefaults,
    #[serde(default)]
    pub trusted_capture: Vec<String>,
    /// The body profile: BMI now, scale estimates later. Never a secret.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub height_cm: Option<u16>,
    /// An actual user-supplied calendar date, never inferred from legacy age.
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        deserialize_with = "read_birth_date"
    )]
    pub birth_date: Option<Day>,
    /// Legacy fallback only, until the owner supplies a birth date.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub age_years: Option<u16>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sex: Option<Sex>,
    /// The goal weight, in kilograms (`None` clears it).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub goal_kg: Option<f64>,
    /// Light, dark, or the device's choice.
    #[serde(default)]
    pub appearance: Appearance,
    /// The default for new scale sessions, never a historical recalculation.
    #[serde(default, deserialize_with = "read_scale_algorithm")]
    pub scale_algorithm: Algorithm,
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
    loaded.height_cm = loaded
        .height_cm
        .filter(|height| HEIGHT_RANGE.contains(height));
    loaded.age_years = loaded.age_years.filter(|age| AGE_RANGE.contains(age));
    loaded.goal_kg = loaded
        .goal_kg
        .filter(|goal| weight::valid_kg(*goal))
        .map(weight::rounded);
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

/// The height in centimetres, when set (tracked).
pub fn height_cm() -> Option<u16> {
    settings().with(|s| s.height_cm)
}

/// The saved birth date (tracked).
pub fn birth_date() -> Option<Day> {
    settings().with(|s| s.birth_date)
}

/// Current completed years in the device's local calendar (tracked).
/// Legacy age is used only when there is no saved birth date. Scale sessions
/// take their own immutable snapshot of this value.
pub fn age_years() -> Option<u16> {
    settings().with(|s| match s.birth_date {
        Some(birth_date) => age_on(birth_date, super::clock::today()),
        None => s.age_years,
    })
}

pub fn age_on(birth_date: Day, today: Day) -> Option<u16> {
    let parts = |day: Day| (day.0.year(), day.0.month(), day.0.day());
    navi_health::profile::age_years_on(parts(birth_date), parts(today))
}

/// A malformed date must not discard unrelated settings or credentials.
fn read_birth_date<'de, D: serde::Deserializer<'de>>(reader: D) -> Result<Option<Day>, D::Error> {
    let value = Option::<serde_json::Value>::deserialize(reader)?;
    Ok(value.and_then(|v| v.as_str()?.parse().ok()))
}

fn read_scale_algorithm<'de, D: serde::Deserializer<'de>>(
    reader: D,
) -> Result<Algorithm, D::Error> {
    let value = serde_json::Value::deserialize(reader)?;
    Ok(value
        .as_str()
        .and_then(Algorithm::from_id)
        .unwrap_or_default())
}

pub fn scale_algorithm() -> Algorithm {
    settings().with(|s| s.scale_algorithm)
}

/// Publish only after the preference was actually kept. This writes no
/// measurement and leaves credentials in their separate storage key.
pub fn save_scale_algorithm(algorithm: Algorithm) -> Result<(), String> {
    let mut next = settings().get_untracked();
    next.scale_algorithm = algorithm;
    let body = serde_json::to_string(&next).map_err(|_| "Invalid settings")?;
    Storage::set_item(KEY, body).map_err(|_| "Could not keep the algorithm preference")?;
    settings().set(next);
    Ok(())
}

/// The sex the estimates need, when set (tracked).
pub fn sex() -> Option<Sex> {
    settings().with(|s| s.sex)
}

/// The goal weight in kilograms, when set (tracked).
pub fn goal_kg() -> Option<f64> {
    settings().with(|s| s.goal_kg)
}

/// Keeps the height (`None` clears it; outside the range is not kept).
pub fn save_height(height_cm: Option<u16>) {
    settings().update(|s| {
        s.height_cm = height_cm.filter(|height| HEIGHT_RANGE.contains(height));
        persist(s);
    });
}

/// Legacy compatibility for old fixtures and development previews. The
/// editor collects birth date; a saved birth date always takes precedence.
pub fn save_age(age_years: Option<u16>) {
    settings().update(|s| {
        s.age_years = age_years.filter(|age| AGE_RANGE.contains(age));
        persist(s);
    });
}

/// Keeps a genuine birth date, or clears it. Invalid ages leave the saved
/// profile unchanged; supplying a date retires the legacy static age.
pub fn save_birth_date(birth_date: Option<Day>) -> bool {
    if birth_date.is_some_and(|date| age_on(date, super::clock::today()).is_none()) {
        return false;
    }
    settings().update(|s| {
        s.birth_date = birth_date;
        if birth_date.is_some() {
            s.age_years = None;
        }
        persist(s);
    });
    true
}

/// Keeps the sex the estimates need (`None` clears it).
pub fn save_sex(sex: Option<Sex>) {
    settings().update(|s| {
        s.sex = sex;
        persist(s);
    });
}

/// Keeps the goal weight (`None` clears it; out of range is not kept).
pub fn save_goal_kg(goal_kg: Option<f64>) {
    settings().update(|s| {
        s.goal_kg = goal_kg
            .filter(|goal| weight::valid_kg(*goal))
            .map(weight::rounded);
        persist(s);
    });
}

/// The appearance the app asks for (tracked); the root hands each change to
/// the engine.
pub fn appearance() -> Appearance {
    settings().with(|s| s.appearance)
}

/// Keeps the appearance. Takes effect at once; there is no Save.
pub fn save_appearance(appearance: Appearance) {
    settings().update(|s| {
        s.appearance = appearance;
        persist(s);
    });
}

/// Last confirmed choices are preferences, not ledger truth. Accounts are
/// checked against the current ledger before the editor uses them.
#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize)]
pub struct LedgerDefaults {
    pub own: Option<String>,
    pub other: Option<String>,
    pub expense: Option<String>,
    pub income: Option<String>,
}

pub fn save_ledger_defaults(defaults: LedgerDefaults) {
    settings().update(|s| {
        s.ledger = defaults;
        persist(s);
    });
}

pub fn capture_trusted(account: &ModelAccount) -> bool {
    settings().with(|s| s.trusted_capture.contains(&account.fingerprint()))
}

pub fn trust_capture(account: &ModelAccount) {
    settings().update(|s| {
        let key = account.fingerprint();
        if !s.trusted_capture.contains(&key) {
            s.trusted_capture.push(key);
        }
        persist(s);
    });
}

pub fn all_recognition_trusted(account: &ModelAccount) -> bool {
    is_trusted(account) && capture_trusted(account)
}

pub fn set_all_recognition_trusted(account: &ModelAccount, trusted: bool) {
    let key = account.fingerprint();
    settings().update(|s| {
        s.trusted.retain(|v| v != &key);
        s.trusted_capture.retain(|v| v != &key);
        if trusted {
            s.trusted.push(key.clone());
            s.trusted_capture.push(key.clone());
        }
        persist(s);
    });
}
