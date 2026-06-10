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

    async fn sync_daily_range(
        &self,
        from: NaiveDate,
        to: NaiveDate,
    ) -> Result<HealthSnapshot> {
        let http = self.client.http();
        let rl = self.client.rate_limiter();
        let token = self.client.access_token().await?;
        let cn = self.is_cn;
        let days = (to - from).num_days() + 1;

        let mut steps = Vec::new();
        let mut sleep_sessions = Vec::new();
        let mut rhr = Vec::new();
        let mut hrv = Vec::new();
        let mut heart_rate = Vec::new();
        let mut body_battery = Vec::new();
        let mut stress = Vec::new();
        let mut weight = Vec::new();
        let mut floors = Vec::new();
        let mut spo2 = Vec::new();

        for i in 0..days {
            let date = from + chrono::Duration::days(i);

            if let Ok(json) = endpoints::fetch_steps(http, rl, &token, date, date, cn).await {
                if let Some(metric) = m::map_steps(&json, date) {
                    steps.push(metric);
                }
            }

            if let Ok(json) = endpoints::fetch_sleep(http, rl, &token, date, cn).await {
                if let Some(session) = m::map_sleep(&json, date) {
                    sleep_sessions.push(session);
                }
                // Fallback: extract HR from sleep if all-day HR fails.
                if let Some(hr) = m::map_heart_rate_from_sleep(&json, date) {
                    heart_rate.push(hr);
                }
            }

            // All-day HR (preferred over sleep-based HR).
            if let Ok(json) = endpoints::fetch_heart_rate(http, rl, &token, date, cn).await {
                if let Some(hr) = m::map_heart_rate_all_day(&json, date) {
                    heart_rate.retain(|m| m.date != date);
                    heart_rate.push(hr);
                }
            }

            if let Ok(json) = endpoints::fetch_rhr(http, rl, &token, date, date, cn).await {
                if let Some(metric) = m::map_rhr(&json, date) {
                    rhr.push(metric);
                }
            }

            if let Ok(json) = endpoints::fetch_hrv(http, rl, &token, date, cn).await {
                if let Some(metric) = m::map_hrv(&json, date) {
                    hrv.push(metric);
                }
            }

            if let Ok(json) = endpoints::fetch_body_battery(http, rl, &token, date, date, cn).await
            {
                if let Some(bb) = m::map_body_battery(&json, date) {
                    body_battery.push(bb);
                }
            }

            if let Ok(json) = endpoints::fetch_stress(http, rl, &token, date, date, cn).await {
                if let Some(metric) = m::map_stress(&json, date) {
                    stress.push(metric);
                }
            }

            if let Ok(json) = endpoints::fetch_weight(http, rl, &token, date, date, cn).await {
                if let Some(metric) = m::map_weight(&json, date) {
                    weight.push(metric);
                }
            }

            if let Ok(json) = endpoints::fetch_daily_summary(http, rl, &token, date, cn).await {
                if let Some(f) = m::map_floors_climbed(&json, date) {
                    floors.push(f);
                }
            }

            if let Ok(json) = endpoints::fetch_spo2(http, rl, &token, date, cn).await {
                if let Some(s) = m::map_spo2(&json, date) {
                    spo2.push(s);
                }
            }
        }

        let vo2_json = endpoints::fetch_training_status(http, rl, &token, cn)
            .await
            .unwrap_or_default();
        let vo2_max = m::map_vo2_max(&vo2_json, to).into_iter().collect();
        let training_load = m::map_training_load(&vo2_json, to)
            .into_iter()
            .collect();
        let training_effect = m::map_training_effect(&vo2_json, to)
            .into_iter()
            .collect();

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
            floors,
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
        let token = self.client.access_token().await?;
        let cn = self.is_cn;

        // Paginate through activities until we get an empty page or
        // activities older than the `from` date.
        let mut all_activities = Vec::new();
        let mut start: u32 = 0;
        let page_size: u32 = 50;
        let from_str = from.format("%Y-%m-%d").to_string();

        loop {
            let json = endpoints::fetch_activities(http, rl, &token, start, page_size, cn).await?;
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

            if reached_boundary || page_len < page_size as usize {
                break;
            }
            start += page_size;
            // Safety cap: don't fetch more than 500 activities.
            if start >= 500 {
                break;
            }
        }

        Ok(all_activities)
    }
}
