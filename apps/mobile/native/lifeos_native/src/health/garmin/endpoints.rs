//! Garmin Connect API endpoint wrappers.
//!
//! Each function maps to one Garmin Connect API endpoint. All functions
//! go through the rate limiter. Raw JSON is returned; mapping to
//! normalized types happens in `mapper.rs`.

use anyhow::{anyhow, Result};
use chrono::NaiveDate;
use reqwest::Client;
use serde_json::Value;

use super::rate_limiter::GarminRateLimiter;

/// Base URL for Garmin Connect API (global).
const GARMIN_CONNECT_BASE_GLOBAL: &str = "https://connect.garmin.com";

/// Base URL for Garmin Connect API (China).
const GARMIN_CONNECT_BASE_CN: &str = "https://connect.garmin.cn";

/// User-Agent mimicking the Garmin Connect mobile app.
const USER_AGENT: &str = "com.garmin.android.apps.connectmobile";

/// Get the base URL for the configured region.
fn base_url(is_cn: bool) -> &'static str {
    if is_cn {
        GARMIN_CONNECT_BASE_CN
    } else {
        GARMIN_CONNECT_BASE_GLOBAL
    }
}

/// Fetch daily summary for a single date.
pub async fn fetch_daily_summary(
    client: &Client,
    rate_limiter: &GarminRateLimiter,
    date: NaiveDate,
    is_cn: bool,
) -> Result<Value> {
    let url = format!(
        "{}/proxy/usersummary-service/usersummary/daily/{}/{}",
        base_url(is_cn),
        date.format("%Y-%m-%d"),
        date.format("%Y-%m-%d"),
    );
    rate_limiter
        .run(|| get_json(client, &url))
        .await
}

/// Fetch steps data for a date range.
pub async fn fetch_steps(
    client: &Client,
    rate_limiter: &GarminRateLimiter,
    from: NaiveDate,
    to: NaiveDate,
    is_cn: bool,
) -> Result<Value> {
    let url = format!(
        "{}/proxy/usersummary-service/stats/steps/daily/{}/{}",
        base_url(is_cn),
        from.format("%Y-%m-%d"),
        to.format("%Y-%m-%d"),
    );
    rate_limiter
        .run(|| get_json(client, &url))
        .await
}

/// Fetch sleep data for a date.
pub async fn fetch_sleep(
    client: &Client,
    rate_limiter: &GarminRateLimiter,
    date: NaiveDate,
    is_cn: bool,
) -> Result<Value> {
    let url = format!(
        "{}/proxy/wellness-service/wellness/dailySleepData?date={}&nonSleepBufferMinutes=60",
        base_url(is_cn),
        date.format("%Y-%m-%d"),
    );
    rate_limiter
        .run(|| get_json(client, &url))
        .await
}

/// Fetch resting heart rate for a date range.
pub async fn fetch_rhr(
    client: &Client,
    rate_limiter: &GarminRateLimiter,
    from: NaiveDate,
    to: NaiveDate,
    is_cn: bool,
) -> Result<Value> {
    let url = format!(
        "{}/proxy/wellness-service/wellness/dailyHeartRate?from={}&until={}",
        base_url(is_cn),
        from.format("%Y-%m-%d"),
        to.format("%Y-%m-%d"),
    );
    rate_limiter
        .run(|| get_json(client, &url))
        .await
}

/// Fetch HRV data for a date.
pub async fn fetch_hrv(
    client: &Client,
    rate_limiter: &GarminRateLimiter,
    date: NaiveDate,
    is_cn: bool,
) -> Result<Value> {
    let url = format!(
        "{}/proxy/hrv-service/hrv/daily/{}",
        base_url(is_cn),
        date.format("%Y-%m-%d"),
    );
    rate_limiter
        .run(|| get_json(client, &url))
        .await
}

/// Fetch Body Battery data for a date range.
pub async fn fetch_body_battery(
    client: &Client,
    rate_limiter: &GarminRateLimiter,
    from: NaiveDate,
    to: NaiveDate,
    is_cn: bool,
) -> Result<Value> {
    let url = format!(
        "{}/proxy/wellness-service/wellness/bodyBattery?from={}&until={}",
        base_url(is_cn),
        from.format("%Y-%m-%d"),
        to.format("%Y-%m-%d"),
    );
    rate_limiter
        .run(|| get_json(client, &url))
        .await
}

/// Fetch stress data for a date range.
pub async fn fetch_stress(
    client: &Client,
    rate_limiter: &GarminRateLimiter,
    from: NaiveDate,
    to: NaiveDate,
    is_cn: bool,
) -> Result<Value> {
    let url = format!(
        "{}/proxy/wellness-service/wellness/dailyStress?from={}&until={}",
        base_url(is_cn),
        from.format("%Y-%m-%d"),
        to.format("%Y-%m-%d"),
    );
    rate_limiter
        .run(|| get_json(client, &url))
        .await
}

/// Fetch activities (paginated).
pub async fn fetch_activities(
    client: &Client,
    rate_limiter: &GarminRateLimiter,
    start: u32,
    limit: u32,
    is_cn: bool,
) -> Result<Value> {
    let url = format!(
        "{}/proxy/activitylist-service/activities/search?start={}&limit={}",
        base_url(is_cn), start, limit,
    );
    rate_limiter
        .run(|| get_json(client, &url))
        .await
}

/// Fetch training status (includes VO2 max).
pub async fn fetch_training_status(
    client: &Client,
    rate_limiter: &GarminRateLimiter,
    is_cn: bool,
) -> Result<Value> {
    let url = format!(
        "{}/proxy/metrics-service/metrics/trainingStatus",
        base_url(is_cn),
    );
    rate_limiter
        .run(|| get_json(client, &url))
        .await
}

/// Fetch weight data for a date.
pub async fn fetch_weight(
    client: &Client,
    rate_limiter: &GarminRateLimiter,
    date: NaiveDate,
    is_cn: bool,
) -> Result<Value> {
    let url = format!(
        "{}/proxy/weight-service/weight/dateRange?startDate={}&endDate={}",
        base_url(is_cn),
        date.format("%Y-%m-%d"),
        date.format("%Y-%m-%d"),
    );
    rate_limiter
        .run(|| get_json(client, &url))
        .await
}

/// Internal: GET request returning parsed JSON.
async fn get_json(client: &Client, url: &str) -> Result<Value> {
    let response = client
        .get(url)
        .header("User-Agent", USER_AGENT)
        .send()
        .await?;

    let status = response.status();
    if status == reqwest::StatusCode::TOO_MANY_REQUESTS {
        return Err(anyhow!("429 Too Many Requests"));
    }
    if !status.is_success() {
        return Err(anyhow!("Garmin API error: {} {}", status, url));
    }

    let body: Value = response.json().await?;
    Ok(body)
}
