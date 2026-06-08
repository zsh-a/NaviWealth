//! Garmin Connect provider implementation.
//!
//! Implements the `HealthProvider` trait for Garmin Connect.
//! Orchestrates client, auth, rate limiting, endpoint calls, and mapping.

pub mod auth;
pub mod client;
pub mod endpoints;
pub mod mapper;
pub mod rate_limiter;
pub mod token_store;

use anyhow::Result;
use chrono::NaiveDate;

use super::provider::{
    ActivityRecord, HealthProvider, HealthSnapshot,
};
use client::GarminClient;
use mapper as m;

/// Garmin Connect health provider.
pub struct GarminProvider {
    client: GarminClient,
    is_cn: bool,
}

impl GarminProvider {
    /// Create a new Garmin provider with the given token store.
    /// `is_cn` selects between China (connect.garmin.cn) and global
    /// (connect.garmin.com) endpoints.
    pub async fn new(
        token_store: std::sync::Arc<dyn token_store::TokenStore>,
        is_cn: bool,
    ) -> Result<Self> {
        let client = GarminClient::new(token_store, is_cn).await?;
        Ok(Self { client, is_cn })
    }

    /// Get a reference to the underlying client (for auth operations).
    pub fn client(&self) -> &GarminClient {
        &self.client
    }
}

#[async_trait::async_trait]
impl HealthProvider for GarminProvider {
    fn name(&self) -> &str {
        "Garmin Connect"
    }

    fn is_authenticated(&self) -> bool {
        // This is async internally but we check the cached state.
        // The actual auth check happens at sync time.
        true // TODO: check client.auth_state() synchronously
    }

    async fn sync_daily_range(
        &self,
        from: NaiveDate,
        to: NaiveDate,
    ) -> Result<HealthSnapshot> {
        let http = self.client.http();
        let rl = self.client.rate_limiter();
        let cn = self.is_cn;
        let days = (to - from).num_days() + 1;

        // Per-day fetches for all metrics. Garmin's per-day endpoints
        // return clean single-day data; range endpoints return mixed
        // shapes that need complex extraction. Per-day is simpler and
        // proven (6/8 endpoints succeed per probe).

        let mut steps = Vec::new();
        let mut sleep_sessions = Vec::new();
        let mut rhr = Vec::new();
        let mut hrv = Vec::new();
        let mut heart_rate = Vec::new();
        let mut body_battery = Vec::new();
        let mut stress = Vec::new();
        let mut weight = Vec::new();

        for i in 0..days {
            let date = from + chrono::Duration::days(i);

            // Steps (per-day, returns 15-min intervals to sum)
            if let Ok(json) = endpoints::fetch_steps(http, rl, date, date, cn).await {
                if let Some(metric) = m::map_steps(&json, date) {
                    steps.push(metric);
                }
            }

            // Sleep (includes avgHeartRate for the night)
            if let Ok(json) = endpoints::fetch_sleep(http, rl, date, cn).await {
                if let Some(session) = m::map_sleep(&json, date) {
                    sleep_sessions.push(session);
                }
                // Heart rate from sleep data (avg overnight HR)
                if let Some(hr) = m::map_heart_rate_from_sleep(&json, date) {
                    heart_rate.push(hr);
                }
            }

            // RHR
            if let Ok(json) = endpoints::fetch_rhr(http, rl, date, date, cn).await {
                if let Some(metric) = m::map_rhr(&json, date) {
                    rhr.push(metric);
                }
            }

            // HRV
            if let Ok(json) = endpoints::fetch_hrv(http, rl, date, cn).await {
                if let Some(metric) = m::map_hrv(&json, date) {
                    hrv.push(metric);
                }
            }

            // Body Battery
            if let Ok(json) = endpoints::fetch_body_battery(http, rl, date, date, cn).await {
                if let Some(bb) = m::map_body_battery(&json, date) {
                    body_battery.push(bb);
                }
            }

            // Stress
            if let Ok(json) = endpoints::fetch_stress(http, rl, date, date, cn).await {
                if let Some(metric) = m::map_stress(&json, date) {
                    stress.push(metric);
                }
            }

            // Weight
            if let Ok(json) = endpoints::fetch_weight(http, rl, date, cn).await {
                if let Some(metric) = m::map_weight(&json, date) {
                    weight.push(metric);
                }
            }
        }

        // VO2 max: single call (not per-day).
        let vo2_json = endpoints::fetch_training_status(http, rl, cn).await.unwrap_or_default();
        let vo2_max = m::map_vo2_max(&vo2_json, to).into_iter().collect();

        Ok(m::build_snapshot(
            steps,
            sleep_sessions,
            rhr,
            hrv,
            heart_rate,
            body_battery,
            stress,
            weight,
            vo2_max,
        ))
    }

    async fn sync_activities(
        &self,
        _from: NaiveDate,
        _to: NaiveDate,
    ) -> Result<Vec<ActivityRecord>> {
        let http = self.client.http();
        let rl = self.client.rate_limiter();
        let cn = self.is_cn;

        // Fetch recent activities (paginated).
        let json = endpoints::fetch_activities(http, rl, 0, 50, cn).await?;
        let activities = json
            .as_array()
            .map(|arr| arr.iter().filter_map(|item| m::map_activity(item)).collect())
            .unwrap_or_default();

        Ok(activities)
    }
}
