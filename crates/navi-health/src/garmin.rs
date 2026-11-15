//! Garmin Connect Personal API: the requests a host makes and how their
//! answers become one summary per day. No I/O: hosts send the requests
//! with their own transport and hand the bodies back.
//!
//! A self-serve personal key is exchanged for a bearer token
//! (`POST …/personal-api-key/token`, `Authorization: ApiKey <key>`, a
//! plain-text JWT valid for 24 hours, no refresh token). A key belongs to
//! one region: an account on garmin.cn gets 404 "does not exist" from the
//! global host, so hosts try [`Region::Global`] then [`Region::China`].
//! Read-only; values Garmin reports as negative mean "not measured".

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};
use serde_json::Value;

/// Where a personal key lives.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Region {
    Global,
    China,
}

impl Region {
    /// Both regions, in the order to try a new key.
    pub const ALL: [Region; 2] = [Region::Global, Region::China];

    pub fn host(self) -> &'static str {
        match self {
            Region::Global => "https://personal.connectapi.garmin.com",
            Region::China => "https://personal.connectapi.garmin.cn",
        }
    }

    /// The token endpoint of this region.
    pub fn token_url(self) -> String {
        format!(
            "{}/personalapitoken-service/personal-api/personal-api-key/token",
            self.host()
        )
    }
}

/// The `Authorization` header that exchanges `key` for a token.
pub fn token_authorization(key: &str) -> String {
    format!("ApiKey {}", key.trim())
}

/// The `Authorization` header of a data request.
pub fn bearer(token: &str) -> String {
    format!("Bearer {}", token.trim())
}

/// The token in a 200 answer of the token endpoint: the body itself.
pub fn read_token(body: &str) -> Option<String> {
    let token = body.trim().trim_matches('"');
    (token.split('.').count() == 3 && !token.contains(char::is_whitespace))
        .then(|| token.to_owned())
}

/// The most days asked for at once; longer spans are split.
pub const MAX_SPAN_DAYS: usize = 30;

/// The data requests for the days `start..=end` (`YYYY-MM-DD`).
pub fn day_requests(region: Region, start: &str, end: &str) -> [(Feed, String); 3] {
    let host = region.host();
    [
        (
            Feed::Daily,
            format!("{host}/usersummary-service/v2/dailysummaries?startDate={start}&endDate={end}"),
        ),
        (
            Feed::Sleep,
            format!(
                "{host}/sleep-service/sleep/dailySleepSummariesByDate?startDate={start}&endDate={end}"
            ),
        ),
        (
            Feed::Hrv,
            format!("{host}/hrv-service/hrv/daily/{start}/{end}"),
        ),
    ]
}

/// Which answer a body is.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Feed {
    Daily,
    Sleep,
    Hrv,
}

/// What Garmin measured on one day; `None` where it measured nothing.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct GarminDay {
    /// `YYYY-MM-DD`, the day the watch reported it for (sleep: the night
    /// ending that morning).
    pub day: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sleep_seconds: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sleep_score: Option<u8>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub resting_hr: Option<u16>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub hrv_ms: Option<u16>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub hrv_status: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub body_battery_high: Option<u8>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub steps: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub stress_avg: Option<u8>,
}

impl GarminDay {
    /// Whether anything was measured.
    pub fn is_empty(&self) -> bool {
        self.sleep_seconds.is_none()
            && self.resting_hr.is_none()
            && self.hrv_ms.is_none()
            && self.body_battery_high.is_none()
            && self.steps.is_none()
            && self.stress_avg.is_none()
    }
}

/// Why an answer could not be read.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum GarminError {
    #[error("the answer is not JSON")]
    NotJson,
    #[error("the answer has no list of days")]
    Shape,
}

/// Adds what `body` (an answer of `feed`) says to `days`, by day.
pub fn merge(
    days: &mut BTreeMap<String, GarminDay>,
    feed: Feed,
    body: &str,
) -> Result<(), GarminError> {
    let value: Value = serde_json::from_str(body).map_err(|_| GarminError::NotJson)?;
    let rows = match feed {
        Feed::Daily => value.get("data"),
        Feed::Sleep => Some(&value),
        Feed::Hrv => value.get("hrvSummaries"),
    }
    .and_then(Value::as_array)
    .ok_or(GarminError::Shape)?;
    for row in rows {
        let Some(date) = row.get("calendarDate").and_then(Value::as_str) else {
            continue;
        };
        if !is_date(date) {
            continue;
        }
        let day = days.entry(date.to_owned()).or_insert_with(|| GarminDay {
            day: date.to_owned(),
            ..GarminDay::default()
        });
        match feed {
            Feed::Daily => {
                day.resting_hr = measured(row, &["heartRate", "restingValue"]);
                day.body_battery_high = measured(row, &["bodyBattery", "maxValue"]);
                day.steps = measured(row, &["movement", "steps", "value"]);
                day.stress_avg = measured(row, &["stress", "avgLevel"]);
            }
            Feed::Sleep => {
                day.sleep_seconds = measured::<u32>(row, &["sleepTimeSeconds"]).filter(|s| *s > 0);
                day.sleep_score = measured(row, &["sleepScores", "overall", "value"]);
            }
            Feed::Hrv => {
                day.hrv_ms = measured(row, &["lastNightAvg"]);
                day.hrv_status = row
                    .get("status")
                    .and_then(Value::as_str)
                    .filter(|s| !s.is_empty())
                    .map(str::to_owned);
            }
        }
    }
    Ok(())
}

/// The number at `path`, if it is a non-negative whole number in range.
fn measured<T: TryFrom<u64>>(row: &Value, path: &[&str]) -> Option<T> {
    let mut at = row;
    for key in path {
        at = at.get(key)?;
    }
    let number = at.as_f64()?;
    if !number.is_finite() || number < 0.0 {
        return None;
    }
    T::try_from(number.round() as u64).ok()
}

fn is_date(text: &str) -> bool {
    let bytes = text.as_bytes();
    bytes.len() == 10
        && bytes[4] == b'-'
        && bytes[7] == b'-'
        && bytes
            .iter()
            .enumerate()
            .all(|(i, b)| i == 4 || i == 7 || b.is_ascii_digit())
}

#[cfg(test)]
mod tests {
    use super::*;

    const DAILY: &str = r#"{"data":[
        {"calendarDate":"2026-11-12","heartRate":{"restingValue":44,"minValue":43},
         "bodyBattery":{"maxValue":76,"latestValue":30},"stress":{"avgLevel":25},
         "movement":{"steps":{"value":8614,"goal":8700}}},
        {"calendarDate":"2026-11-13","heartRate":{"restingValue":-1},
         "bodyBattery":{},"stress":{"avgLevel":-2},"movement":{"steps":{"value":13794}}},
        {"calendarDate":"not-a-day","heartRate":{"restingValue":50}}
    ]}"#;
    const SLEEP: &str = r#"[
        {"calendarDate":"2026-11-13","sleepTimeSeconds":27120,
         "sleepScores":{"overall":{"value":89,"qualifierKey":"GOOD"}}},
        {"calendarDate":"2026-11-11","sleepTimeSeconds":0}
    ]"#;
    const HRV: &str = r#"{"hrvSummaries":[
        {"calendarDate":"2026-11-13","lastNightAvg":75,"weeklyAvg":71,"status":"LOW"}
    ],"userProfilePk":1}"#;

    #[test]
    fn answers_merge_into_one_summary_per_day() {
        let mut days = BTreeMap::new();
        merge(&mut days, Feed::Daily, DAILY).unwrap();
        merge(&mut days, Feed::Sleep, SLEEP).unwrap();
        merge(&mut days, Feed::Hrv, HRV).unwrap();
        assert_eq!(
            days.keys().collect::<Vec<_>>(),
            ["2026-11-11", "2026-11-12", "2026-11-13"]
        );
        let today = &days["2026-11-13"];
        assert_eq!(today.sleep_seconds, Some(27120));
        assert_eq!(today.sleep_score, Some(89));
        assert_eq!(today.hrv_ms, Some(75));
        assert_eq!(today.hrv_status.as_deref(), Some("LOW"));
        assert_eq!(today.steps, Some(13794));
        // Negative values are "not measured", missing ones too.
        assert_eq!(today.resting_hr, None);
        assert_eq!(today.stress_avg, None);
        assert_eq!(today.body_battery_high, None);
        let before = &days["2026-11-12"];
        assert_eq!(
            (
                before.resting_hr,
                before.body_battery_high,
                before.stress_avg
            ),
            (Some(44), Some(76), Some(25))
        );
        // A night with no sleep recorded is not zero hours.
        assert!(days["2026-11-11"].is_empty());
    }

    #[test]
    fn unreadable_answers_are_errors_not_empty_days() {
        let mut days = BTreeMap::new();
        assert_eq!(
            merge(&mut days, Feed::Daily, "<html>"),
            Err(GarminError::NotJson)
        );
        assert_eq!(merge(&mut days, Feed::Hrv, "{}"), Err(GarminError::Shape));
        assert!(days.is_empty());
    }

    #[test]
    fn requests_and_tokens() {
        assert_eq!(
            Region::China.token_url(),
            "https://personal.connectapi.garmin.cn/personalapitoken-service/personal-api/personal-api-key/token"
        );
        assert_eq!(token_authorization(" GCDC-x \n"), "ApiKey GCDC-x");
        assert_eq!(read_token("aaa.bbb.ccc\n").as_deref(), Some("aaa.bbb.ccc"));
        assert_eq!(read_token("{\"error\":1}"), None);
        let requests = day_requests(Region::Global, "2026-11-01", "2026-11-13");
        assert!(
            requests[2]
                .1
                .ends_with("/hrv-service/hrv/daily/2026-11-01/2026-11-13")
        );
        let stored = serde_json::to_string(&GarminDay {
            day: "2026-11-13".into(),
            steps: Some(5),
            ..GarminDay::default()
        })
        .unwrap();
        assert_eq!(stored, r#"{"day":"2026-11-13","steps":5}"#);
    }
}
