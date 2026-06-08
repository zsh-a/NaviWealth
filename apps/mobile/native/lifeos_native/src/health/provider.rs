//! HealthProvider trait — unified health data provider contract.
//!
//! Every source (Garmin, HealthKit, Health Connect, manual) implements
//! this trait. The sync engine and Dart shell consume only this
//! abstraction; provider-specific details stay in submodules.

use chrono::NaiveDate;
use serde::{Deserialize, Serialize};

/// Unified health data provider contract.
#[async_trait::async_trait]
pub trait HealthProvider: Send + Sync {
    /// Provider display name (e.g. "Garmin Connect").
    fn name(&self) -> &str;

    /// Check if the provider has valid credentials.
    fn is_authenticated(&self) -> bool;

    /// Sync daily metrics for the given date range (inclusive).
    async fn sync_daily_range(
        &self,
        from: NaiveDate,
        to: NaiveDate,
    ) -> anyhow::Result<HealthSnapshot>;

    /// Sync activity/workout sessions for the given date range.
    async fn sync_activities(
        &self,
        from: NaiveDate,
        to: NaiveDate,
    ) -> anyhow::Result<Vec<ActivityRecord>>;
}

// ---------------------------------------------------------------------------
// Normalized types — Dart consumes these via FRB JSON serialization.
// ---------------------------------------------------------------------------

/// Normalized daily health snapshot — provider-agnostic.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct HealthSnapshot {
    pub steps: Vec<DailyMetric>,
    pub sleep_sessions: Vec<SleepSession>,
    pub resting_hr: Vec<DailyMetric>,
    pub hrv: Vec<DailyMetric>,
    pub heart_rate: Vec<DailyMetric>,
    pub active_energy: Vec<DailyMetric>,
    pub vo2_max: Vec<DailyMetric>,
    pub weight: Vec<PointMetric>,
    pub body_fat: Vec<PointMetric>,
    pub floors_climbed: Vec<DailyMetric>,
    pub respiratory_rate: Vec<DailyMetric>,
    /// Garmin-specific: Body Battery daily summary.
    /// Stored in `payload_json` on the Dart side.
    pub body_battery: Vec<BodyBatteryDay>,
    /// Garmin-specific: daily stress average.
    pub stress: Vec<DailyMetric>,
}

/// A value bucketed to a calendar day.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DailyMetric {
    /// Stable dedup ID (e.g. "garmin:steps:2026-06-07").
    pub id: String,
    /// UTC date this value refers to.
    pub date: NaiveDate,
    pub value: f64,
    pub unit: String,
    pub source_device: Option<String>,
}

/// One sleep session that has already ended.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SleepSession {
    pub id: String,
    /// ISO 8601 UTC timestamp.
    pub started_at: String,
    /// Total asleep duration in seconds.
    pub duration_seconds: u32,
    pub source_device: Option<String>,
    /// Optional per-stage histogram JSON.
    pub stage_histogram_json: Option<String>,
}

/// One workout/activity session.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ActivityRecord {
    pub id: String,
    /// Lowercased activity type (e.g. "running", "cycling").
    pub activity_type: String,
    /// ISO 8601 UTC timestamp.
    pub started_at: String,
    pub duration_seconds: u32,
    pub total_energy_kcal: Option<f64>,
    pub total_distance_meters: Option<f64>,
    pub source_device: Option<String>,
}

/// A single timestamped measurement (weight, body fat, etc.).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PointMetric {
    pub id: String,
    /// ISO 8601 UTC timestamp.
    pub measured_at: String,
    pub value: f64,
    pub unit: String,
    pub source_device: Option<String>,
}

/// Garmin Body Battery daily summary.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BodyBatteryDay {
    pub id: String,
    pub date: NaiveDate,
    pub min: u8,
    pub max: u8,
    /// Overnight charge level.
    pub charged: u8,
    /// Daytime drain.
    pub drained: u8,
}
