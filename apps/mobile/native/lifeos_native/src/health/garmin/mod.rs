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
    ActivityRecord, BodyBatteryDay, DailyMetric, HealthProvider, HealthSnapshot,
};
use client::GarminClient;
use mapper as m;

const ACTIVITY_PAGE_SIZE: u32 = 50;
const MAX_ACTIVITY_PAGES: u32 = 1;

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

    /// Create a provider from an existing client (clone).
    /// Used by `garmin_init` so the provider shares auth state
    /// with the client used for login/token operations.
    pub fn from_client(client: GarminClient) -> Self {
        let is_cn = client.is_cn();
        Self { client, is_cn }
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
        // Use try_lock to check auth state synchronously.
        // Falls back to false if the lock is contended (conservative).
        self.client
            .auth_state_sync()
            .map(|s| s.can_make_requests())
            .unwrap_or(false)
    }

    async fn sync_daily_range(&self, from: NaiveDate, to: NaiveDate) -> Result<HealthSnapshot> {
        let http = self.client.http();
        let rl = self.client.rate_limiter();
        let token = self.client.fresh_access_token().await?;
        let cn = self.is_cn;
        let days = (to - from).num_days() + 1;
        let display_name = endpoints::fetch_social_profile(http, rl, &token, cn)
            .await?
            .get("displayName")
            .and_then(|v| v.as_str())
            .filter(|v| !v.is_empty())
            .map(|v| v.to_string())
            .ok_or_else(|| anyhow::anyhow!("Garmin profile missing displayName"))?;

        let mut steps: Vec<DailyMetric> = Vec::new();
        let mut sleep_sessions = Vec::new();
        let mut rhr: Vec<DailyMetric> = Vec::new();
        let mut hrv: Vec<DailyMetric> = Vec::new();
        let mut heart_rate: Vec<DailyMetric> = Vec::new();
        let mut body_battery: Vec<BodyBatteryDay> = Vec::new();
        let mut stress: Vec<DailyMetric> = Vec::new();
        let mut weight = Vec::new();
        let mut active_energy: Vec<DailyMetric> = Vec::new();
        let mut distance: Vec<DailyMetric> = Vec::new();
        let mut total_energy: Vec<DailyMetric> = Vec::new();
        let mut floors: Vec<DailyMetric> = Vec::new();
        let mut respiration: Vec<DailyMetric> = Vec::new();
        let mut spo2: Vec<DailyMetric> = Vec::new();

        if let Ok(json) = endpoints::fetch_weight(http, rl, &token, from, to, cn).await {
            weight = m::map_weight_range(&json);
        }

        for i in 0..days {
            let date = from + chrono::Duration::days(i);

            if let Ok(json) =
                endpoints::fetch_daily_summary(http, rl, &token, date, &display_name, cn).await
            {
                if let Some(metric) = m::map_steps_from_daily_summary(&json, date) {
                    steps.retain(|m| m.date != date);
                    steps.push(metric);
                }
                if let Some(metric) = m::map_rhr(&json, date) {
                    rhr.retain(|m| m.date != date);
                    rhr.push(metric);
                }
                if let Some(metric) = m::map_stress(&json, date) {
                    stress.retain(|m| m.date != date);
                    stress.push(metric);
                }
                if let Some(metric) = m::map_respiratory_rate(&json, date) {
                    respiration.retain(|m| m.date != date);
                    respiration.push(metric);
                }
                if let Some(metric) = m::map_spo2(&json, date) {
                    spo2.retain(|m| m.date != date);
                    spo2.push(metric);
                }
                if let Some(metric) = m::map_body_battery_from_daily_summary(&json, date) {
                    body_battery.retain(|m| m.date != date);
                    body_battery.push(metric);
                }
                if let Some(f) = m::map_floors_climbed(&json, date) {
                    floors.retain(|m| m.date != date);
                    floors.push(f);
                }
                let (distance_metric, active_metric, total_metric) =
                    m::map_daily_summary_metrics(&json, date);
                if let Some(metric) = distance_metric {
                    distance.retain(|m| m.date != date);
                    distance.push(metric);
                }
                if let Some(metric) = active_metric {
                    active_energy.retain(|m| m.date != date);
                    active_energy.push(metric);
                }
                if let Some(metric) = total_metric {
                    total_energy.retain(|m| m.date != date);
                    total_energy.push(metric);
                }
            }

            if let Ok(json) =
                endpoints::fetch_sleep(http, rl, &token, date, &display_name, cn).await
            {
                if let Some(session) = m::map_sleep(&json, date) {
                    sleep_sessions.push(session);
                }
                if let Some(hr) = m::map_heart_rate_from_sleep(&json, date) {
                    heart_rate.retain(|m| m.date != date);
                    heart_rate.push(hr);
                }
                if let Some(metric) = m::map_hrv_from_sleep(&json, date) {
                    hrv.retain(|m| m.date != date);
                    hrv.push(metric);
                }
                if !rhr.iter().any(|m| m.date == date) {
                    if let Some(metric) = m::map_rhr_from_sleep(&json, date) {
                        rhr.push(metric);
                    }
                }
                if !stress.iter().any(|m| m.date == date) {
                    if let Some(metric) = m::map_stress_from_sleep(&json, date) {
                        stress.push(metric);
                    }
                }
                if !body_battery.iter().any(|m| m.date == date) {
                    if let Some(metric) = m::map_body_battery_from_sleep(&json, date) {
                        body_battery.push(metric);
                    }
                }
                if !respiration.iter().any(|m| m.date == date) {
                    if let Some(metric) = m::map_respiratory_rate_from_sleep(&json, date) {
                        respiration.push(metric);
                    }
                }
                if !spo2.iter().any(|m| m.date == date) {
                    if let Some(metric) = m::map_spo2_from_sleep(&json, date) {
                        spo2.push(metric);
                    }
                }
            }
        }

        let vo2_json = endpoints::fetch_training_status(http, rl, &token, to, cn)
            .await
            .unwrap_or_default();
        let vo2_max = m::map_vo2_max(&vo2_json, to).into_iter().collect();
        let training_load = m::map_training_load(&vo2_json, to).into_iter().collect();
        let training_effect = m::map_training_effect(&vo2_json, to).into_iter().collect();

        Ok(m::build_snapshot(
            steps,
            sleep_sessions,
            vec![],
            rhr,
            hrv,
            heart_rate,
            body_battery,
            stress,
            weight,
            active_energy,
            distance,
            total_energy,
            vo2_max,
            floors,
            respiration,
            training_load,
            training_effect,
            spo2,
        ))
    }

    async fn sync_activities(
        &self,
        from: NaiveDate,
        _to: NaiveDate,
    ) -> Result<Vec<ActivityRecord>> {
        let http = self.client.http();
        let rl = self.client.rate_limiter();
        let token = self.client.fresh_access_token().await?;
        let cn = self.is_cn;

        // Paginate through activities until we get an empty page or
        // activities older than the `from` date.
        let mut all_activities = Vec::new();
        let mut start: u32 = 0;
        let from_str = from.format("%Y-%m-%d").to_string();
        let mut pages_fetched: u32 = 0;

        loop {
            let json = endpoints::fetch_activities(http, rl, &token, start, ACTIVITY_PAGE_SIZE, cn)
                .await?;
            pages_fetched += 1;
            let page = json.as_array();
            let page_len = page.map(|a| a.len()).unwrap_or(0);
            if page_len == 0 {
                break;
            }

            let mut reached_boundary = false;
            if let Some(arr) = page {
                for item in arr {
                    if let Some(activity) = m::map_activity(item) {
                        // Activities are sorted newest-first. If we've gone
                        // past the `from` date, stop paginating.
                        let act_date = &activity.started_at[..10.min(activity.started_at.len())];
                        if act_date < from_str.as_str() {
                            reached_boundary = true;
                            break;
                        }
                        all_activities.push(activity);
                    }
                }
            }

            if reached_boundary || page_len < ACTIVITY_PAGE_SIZE as usize {
                break;
            }
            if pages_fetched >= MAX_ACTIVITY_PAGES {
                break;
            }
            start += ACTIVITY_PAGE_SIZE;
        }

        Ok(all_activities)
    }
}
