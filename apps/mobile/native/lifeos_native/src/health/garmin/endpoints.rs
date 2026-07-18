//! Garmin Connect API endpoint wrappers.
//!
//! All API calls use DI Bearer token auth with native mobile headers.
//! Raw JSON is returned; mapping to normalized types happens in `mapper.rs`.
//!
//! 429 responses trigger exponential backoff and automatic retry (max 3).

use anyhow::{Result, anyhow};
use chrono::NaiveDate;
use reqwest::Client;
use serde_json::Value;

use super::rate_limiter::GarminRateLimiter;

/// Max retries on 429 before giving up.
const MAX_429_RETRIES: u32 = 3;

/// Connect API base URL templates.
const CONNECT_API_BASE_CN: &str = "https://connectapi.garmin.cn";
const CONNECT_API_BASE_GLOBAL: &str = "https://connectapi.garmin.com";

/// Native API headers (matching python-garminconnect mobile flow).
const NATIVE_USER_AGENT: &str = "GCM-Android-5.23";
const NATIVE_X_GARMIN_UA: &str = "com.garmin.android.apps.connectmobile/5.23; ; Google/sdk_gphone64_arm64/google; Android/33; Dalvik/2.1.0";

fn api_base(is_cn: bool) -> &'static str {
    if is_cn {
        CONNECT_API_BASE_CN
    } else {
        CONNECT_API_BASE_GLOBAL
    }
}

fn path_segment(value: &str) -> String {
    let mut encoded = String::with_capacity(value.len());
    for byte in value.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'.' | b'_' | b'~' => {
                encoded.push(byte as char);
            }
            _ => encoded.push_str(&format!("%{byte:02X}")),
        }
    }
    encoded
}

/// Build a GET request with native API headers + Bearer auth.
fn api_get(client: &Client, url: &str, access_token: &str) -> reqwest::RequestBuilder {
    client
        .get(url)
        .header("User-Agent", NATIVE_USER_AGENT)
        .header("X-Garmin-User-Agent", NATIVE_X_GARMIN_UA)
        .header("X-Garmin-Paired-App-Version", "10861")
        .header("X-Garmin-Client-Platform", "Android")
        .header("X-App-Ver", "10861")
        .header("X-Lang", "en")
        .header("X-GCExperience", "GC5")
        .header("Accept-Language", "en-US,en;q=0.9")
        .header("Authorization", format!("Bearer {}", access_token))
        .header("Accept", "application/json")
}

/// Execute a GET request and parse JSON response.
async fn get_json(client: &Client, url: &str, access_token: &str) -> Result<Value> {
    let response = api_get(client, url, access_token).send().await?;

    let status = response.status();
    if status == reqwest::StatusCode::TOO_MANY_REQUESTS {
        return Err(anyhow!("429 Too Many Requests"));
    }
    if status == reqwest::StatusCode::UNAUTHORIZED {
        return Err(anyhow!("401 Unauthorized — token may be expired"));
    }
    if !status.is_success() {
        return Err(anyhow!("Garmin API error: {} {}", status, url));
    }

    let body: Value = response.json().await?;
    Ok(body)
}

/// Fetch JSON through the rate limiter with 429 exponential backoff retry.
///
/// Each attempt goes through `rl.run()` (concurrency + interval gating).
/// On 429, calls `rl.backoff_sleep()` then retries.
async fn fetch_json(
    client: &Client,
    rl: &GarminRateLimiter,
    token: &str,
    url: String,
) -> Result<Value> {
    for attempt in 0..=MAX_429_RETRIES {
        let result = rl.run(|| get_json(client, &url, token)).await;
        match result {
            Ok(v) => {
                rl.on_success();
                return Ok(v);
            }
            Err(e) if e.to_string().contains("429") && attempt < MAX_429_RETRIES => {
                rl.backoff_sleep().await;
            }
            Err(e) => return Err(e),
        }
    }
    unreachable!()
}

// ---------------------------------------------------------------------------
// Endpoint functions
// ---------------------------------------------------------------------------

pub async fn fetch_social_profile(
    client: &Client,
    rl: &GarminRateLimiter,
    token: &str,
    is_cn: bool,
) -> Result<Value> {
    let url = format!("{}/userprofile-service/socialProfile", api_base(is_cn));
    fetch_json(client, rl, token, url).await
}

pub async fn fetch_daily_summary(
    client: &Client,
    rl: &GarminRateLimiter,
    token: &str,
    date: NaiveDate,
    display_name: &str,
    is_cn: bool,
) -> Result<Value> {
    let display_name = path_segment(display_name);
    let url = format!(
        "{}/usersummary-service/usersummary/daily/{}?calendarDate={}",
        api_base(is_cn),
        display_name,
        date.format("%Y-%m-%d"),
    );
    fetch_json(client, rl, token, url).await
}

pub async fn fetch_steps_day(
    client: &Client,
    rl: &GarminRateLimiter,
    token: &str,
    date: NaiveDate,
    display_name: &str,
    is_cn: bool,
) -> Result<Value> {
    let display_name = path_segment(display_name);
    let url = format!(
        "{}/wellness-service/wellness/dailySummaryChart/{}?date={}",
        api_base(is_cn),
        display_name,
        date.format("%Y-%m-%d"),
    );
    fetch_json(client, rl, token, url).await
}

pub async fn fetch_sleep(
    client: &Client,
    rl: &GarminRateLimiter,
    token: &str,
    date: NaiveDate,
    display_name: &str,
    is_cn: bool,
) -> Result<Value> {
    let display_name = path_segment(display_name);
    let url = format!(
        "{}/wellness-service/wellness/dailySleepData/{}?date={}&nonSleepBufferMinutes=60",
        api_base(is_cn),
        display_name,
        date.format("%Y-%m-%d"),
    );
    fetch_json(client, rl, token, url).await
}

pub async fn fetch_rhr_day(
    client: &Client,
    rl: &GarminRateLimiter,
    token: &str,
    date: NaiveDate,
    display_name: &str,
    is_cn: bool,
) -> Result<Value> {
    let display_name = path_segment(display_name);
    let url = format!(
        "{}/userstats-service/wellness/daily/{}?fromDate={}&untilDate={}&metricId=60",
        api_base(is_cn),
        display_name,
        date.format("%Y-%m-%d"),
        date.format("%Y-%m-%d"),
    );
    fetch_json(client, rl, token, url).await
}

pub async fn fetch_heart_rate(
    client: &Client,
    rl: &GarminRateLimiter,
    token: &str,
    date: NaiveDate,
    display_name: &str,
    is_cn: bool,
) -> Result<Value> {
    let display_name = path_segment(display_name);
    let url = format!(
        "{}/wellness-service/wellness/dailyHeartRate/{}?date={}",
        api_base(is_cn),
        display_name,
        date.format("%Y-%m-%d"),
    );
    fetch_json(client, rl, token, url).await
}

pub async fn fetch_hrv(
    client: &Client,
    rl: &GarminRateLimiter,
    token: &str,
    date: NaiveDate,
    is_cn: bool,
) -> Result<Value> {
    let url = format!(
        "{}/hrv-service/hrv/{}",
        api_base(is_cn),
        date.format("%Y-%m-%d"),
    );
    fetch_json(client, rl, token, url).await
}

pub async fn fetch_spo2(
    client: &Client,
    rl: &GarminRateLimiter,
    token: &str,
    date: NaiveDate,
    is_cn: bool,
) -> Result<Value> {
    let url = format!(
        "{}/wellness-service/wellness/daily/spo2/{}",
        api_base(is_cn),
        date.format("%Y-%m-%d"),
    );
    fetch_json(client, rl, token, url).await
}

pub async fn fetch_respiration(
    client: &Client,
    rl: &GarminRateLimiter,
    token: &str,
    date: NaiveDate,
    is_cn: bool,
) -> Result<Value> {
    let url = format!(
        "{}/wellness-service/wellness/daily/respiration/{}",
        api_base(is_cn),
        date.format("%Y-%m-%d"),
    );
    fetch_json(client, rl, token, url).await
}

pub async fn fetch_body_battery(
    client: &Client,
    rl: &GarminRateLimiter,
    token: &str,
    from: NaiveDate,
    to: NaiveDate,
    is_cn: bool,
) -> Result<Value> {
    let url = format!(
        "{}/wellness-service/wellness/bodyBattery/reports/daily?startDate={}&endDate={}",
        api_base(is_cn),
        from.format("%Y-%m-%d"),
        to.format("%Y-%m-%d"),
    );
    fetch_json(client, rl, token, url).await
}

pub async fn fetch_stress(
    client: &Client,
    rl: &GarminRateLimiter,
    token: &str,
    from: NaiveDate,
    to: NaiveDate,
    is_cn: bool,
) -> Result<Value> {
    let url = format!(
        "{}/wellness-service/wellness/dailyStress?from={}&until={}",
        api_base(is_cn),
        from.format("%Y-%m-%d"),
        to.format("%Y-%m-%d"),
    );
    fetch_json(client, rl, token, url).await
}

pub async fn fetch_stress_day(
    client: &Client,
    rl: &GarminRateLimiter,
    token: &str,
    date: NaiveDate,
    is_cn: bool,
) -> Result<Value> {
    let url = format!(
        "{}/wellness-service/wellness/dailyStress/{}",
        api_base(is_cn),
        date.format("%Y-%m-%d"),
    );
    fetch_json(client, rl, token, url).await
}

pub async fn fetch_activities(
    client: &Client,
    rl: &GarminRateLimiter,
    token: &str,
    start: u32,
    limit: u32,
    is_cn: bool,
) -> Result<Value> {
    let url = format!(
        "{}/activitylist-service/activities/search/activities?start={}&limit={}",
        api_base(is_cn),
        start,
        limit,
    );
    fetch_json(client, rl, token, url).await
}

pub async fn fetch_training_status(
    client: &Client,
    rl: &GarminRateLimiter,
    token: &str,
    date: NaiveDate,
    is_cn: bool,
) -> Result<Value> {
    let url = format!(
        "{}/metrics-service/metrics/trainingstatus/aggregated/{}",
        api_base(is_cn),
        date.format("%Y-%m-%d"),
    );
    fetch_json(client, rl, token, url).await
}

pub async fn fetch_weight(
    client: &Client,
    rl: &GarminRateLimiter,
    token: &str,
    from: NaiveDate,
    to: NaiveDate,
    is_cn: bool,
) -> Result<Value> {
    let url = format!(
        "{}/weight-service/weight/dateRange?startDate={}&endDate={}",
        api_base(is_cn),
        from.format("%Y-%m-%d"),
        to.format("%Y-%m-%d"),
    );
    fetch_json(client, rl, token, url).await
}
