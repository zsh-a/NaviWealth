//! Garmin JSON → HealthSnapshot mapping.
//!
//! Each function takes raw JSON from a Garmin API endpoint and produces
//! normalized types. Stable IDs use the `garmin:` prefix for dedup.
//!
//! Field shapes are validated against real Garmin CN API responses
//! (2026-06-08 probe output).

use std::collections::HashMap;
use chrono::NaiveDate;
use serde_json::Value;

use crate::health::provider::{
    ActivityRecord, BodyBatteryDay, DailyMetric, HealthSnapshot, PointMetric, SleepSession,
};

/// Map steps JSON to DailyMetric.
///
/// Garmin returns 15-minute interval arrays. We sum all intervals to
/// get the daily total.
pub fn map_steps(json: &Value, date: NaiveDate) -> Option<DailyMetric> {
    let intervals = json.as_array()?;
    let total: f64 = intervals
        .iter()
        .filter_map(|item| item.get("steps").and_then(|v| v.as_f64()))
        .sum();
    if total == 0.0 {
        return None;
    }
    Some(DailyMetric {
        id: format!("garmin:steps:{date}"),
        date,
        value: total,
        unit: "steps".to_string(),
        source_device: Some("garmin".to_string()),
    })
}

/// Map sleep JSON to SleepSession.
///
/// Garmin returns `{ "dailySleepDTO": { ... }, ... }`.
/// Key fields: `id` (epoch ms), `sleepStartTimestampGMT` (epoch ms),
/// `sleepTimeSeconds`, `deepSleepSeconds`, `lightSleepSeconds`,
/// `remSleepSeconds`, `awakeSleepSeconds`.
pub fn map_sleep(json: &Value, date: NaiveDate) -> Option<SleepSession> {
    let dto = json.get("dailySleepDTO")?;
    let duration_seconds = dto.get("sleepTimeSeconds")?.as_u64()? as u32;
    if duration_seconds == 0 {
        return None;
    }

    // Start time is epoch milliseconds.
    let start_ms = dto
        .get("sleepStartTimestampGMT")
        .and_then(|v| v.as_i64())
        .unwrap_or(0);
    let started_at = if start_ms > 0 {
        let secs = start_ms / 1000;
        let nsecs = ((start_ms % 1000) * 1_000_000) as u32;
        chrono::DateTime::from_timestamp(secs, nsecs)
            .map(|dt| dt.to_rfc3339())
            .unwrap_or_default()
    } else {
        String::new()
    };

    let id = dto
        .get("id")
        .and_then(|v| v.as_i64())
        .map(|id| format!("garmin:sleep:{id}"))
        .unwrap_or_else(|| format!("garmin:sleep:{date}"));

    // Build stage histogram from known fields.
    let deep = dto.get("deepSleepSeconds").and_then(|v| v.as_u64()).unwrap_or(0);
    let light = dto.get("lightSleepSeconds").and_then(|v| v.as_u64()).unwrap_or(0);
    let rem = dto.get("remSleepSeconds").and_then(|v| v.as_u64()).unwrap_or(0);
    let awake = dto.get("awakeSleepSeconds").and_then(|v| v.as_u64()).unwrap_or(0);
    let stage_histogram = if deep + light + rem + awake > 0 {
        Some(format!(
            r#"{{"deep":{},"light":{},"rem":{},"awake":{}}}"#,
            deep, light, rem, awake,
        ))
    } else {
        None
    };

    Some(SleepSession {
        id,
        started_at,
        duration_seconds,
        source_device: Some("garmin".to_string()),
        stage_histogram_json: stage_histogram,
    })
}

/// Map RHR JSON to DailyMetric.
///
/// Garmin returns `{ "allMetrics": { "metricsMap": { "WELLNESS_RESTING_HEART_RATE": [...] } } }`.
pub fn map_rhr(json: &Value, date: NaiveDate) -> Option<DailyMetric> {
    let metrics_map = json
        .get("allMetrics")
        .and_then(|m| m.get("metricsMap"))?;
    let rhr_array = metrics_map.get("WELLNESS_RESTING_HEART_RATE")?;
    let value = rhr_array
        .as_array()?
        .first()?
        .get("value")?
        .as_f64()?;
    if value == 0.0 {
        return None;
    }
    Some(DailyMetric {
        id: format!("garmin:rhr:{date}"),
        date,
        value,
        unit: "bpm".to_string(),
        source_device: Some("garmin".to_string()),
    })
}

/// Map HRV JSON to DailyMetric.
///
/// Garmin returns `{ "hrvSummary": { "lastNightAvg": 103, ... }, ... }`.
pub fn map_hrv(json: &Value, date: NaiveDate) -> Option<DailyMetric> {
    let value = json
        .get("hrvSummary")
        .and_then(|s| s.get("lastNightAvg"))
        .and_then(|v| v.as_f64())?;
    if value == 0.0 {
        return None;
    }
    Some(DailyMetric {
        id: format!("garmin:hrv:{date}"),
        date,
        value,
        unit: "ms".to_string(),
        source_device: Some("garmin".to_string()),
    })
}

/// Map heart rate from sleep JSON.
///
/// From sleep DTO: `avgHeartRate` field.
pub fn map_heart_rate_from_sleep(json: &Value, date: NaiveDate) -> Option<DailyMetric> {
    let value = json
        .get("dailySleepDTO")
        .and_then(|dto| dto.get("avgHeartRate"))
        .and_then(|v| v.as_f64())?;
    if value == 0.0 {
        return None;
    }
    Some(DailyMetric {
        id: format!("garmin:hr:{date}"),
        date,
        value,
        unit: "bpm".to_string(),
        source_device: Some("garmin".to_string()),
    })
}

/// Map all-day heart rate from the heartRate endpoint.
///
/// Garmin returns `{ "heartRateValues": [[ts_ms, bpm], ...] }`.
/// We compute the daily average, skipping zero/null readings.
pub fn map_heart_rate_all_day(json: &Value, date: NaiveDate) -> Option<DailyMetric> {
    let entries = json.get("heartRateValues")?.as_array()?;
    let mut sum = 0.0;
    let mut count = 0;
    for entry in entries {
        if let Some(arr) = entry.as_array() {
            // Array format: [timestamp_ms, heart_rate_bpm]
            if let Some(hr) = arr.get(1).and_then(|v| v.as_f64()) {
                if hr > 0.0 {
                    sum += hr;
                    count += 1;
                }
            }
        } else if let Some(hr) = entry.get("value").and_then(|v| v.as_f64()) {
            // Object format: { "value": bpm }
            if hr > 0.0 {
                sum += hr;
                count += 1;
            }
        }
    }
    if count == 0 {
        return None;
    }
    Some(DailyMetric {
        id: format!("garmin:hr:{date}"),
        date,
        value: sum / count as f64,
        unit: "bpm".to_string(),
        source_device: Some("garmin".to_string()),
    })
}

/// Map Body Battery JSON to BodyBatteryDay.
///
/// Garmin returns an array. Each entry has `date`, `charged`, `drained`,
/// and `bodyBatteryValuesArray` (per-slot readings).
pub fn map_body_battery(json: &Value, date: NaiveDate) -> Option<BodyBatteryDay> {
    let entries = json.as_array()?;
    let entry = entries.first()?;
    let charged = entry.get("charged")?.as_u64()? as u8;
    let drained = entry.get("drained")?.as_u64()? as u8;

    // Derive min/max from bodyBatteryValuesArray.
    let values: Vec<u8> = entry
        .get("bodyBatteryValuesArray")
        .and_then(|v| v.as_array())
        .unwrap_or(&vec![])
        .iter()
        .filter_map(|slot| {
            if let Some(arr) = slot.as_array() {
                arr.get(1).and_then(|v| v.as_u64()).map(|n| n as u8)
            } else {
                slot.get("value").and_then(|v| v.as_u64()).map(|n| n as u8)
            }
        })
        .collect();

    let min = if values.is_empty() {
        0u8
    } else {
        *values.iter().min().unwrap_or(&0)
    };
    let max = if values.is_empty() {
        charged
    } else {
        *values.iter().max().unwrap_or(&charged)
    };

    Some(BodyBatteryDay {
        id: format!("garmin:body_battery:{date}"),
        date,
        min,
        max,
        charged,
        drained,
    })
}

/// Map stress JSON to DailyMetric.
///
/// Garmin returns `{ "avgStressLevel": 19, "maxStressLevel": 86, ... }`.
pub fn map_stress(json: &Value, date: NaiveDate) -> Option<DailyMetric> {
    let value = json
        .get("avgStressLevel")
        .and_then(|v| v.as_f64())?;
    if value == 0.0 {
        return None;
    }
    Some(DailyMetric {
        id: format!("garmin:stress:{date}"),
        date,
        value,
        unit: "level".to_string(),
        source_device: Some("garmin".to_string()),
    })
}

/// Map activity JSON to ActivityRecord.
///
/// Garmin returns `{ "activityId": ..., "activityType": { "typeKey": "cycling" }, ... }`.
pub fn map_activity(json: &Value) -> Option<ActivityRecord> {
    let id = json.get("activityId").and_then(|v| v.as_i64())?;
    let activity_type = json
        .get("activityType")
        .and_then(|t| t.get("typeKey"))
        .and_then(|v| v.as_str())
        .unwrap_or("unknown")
        .to_lowercase();
    let started_at = json
        .get("startTimeGMT")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let duration_seconds = json
        .get("duration")
        .and_then(|v| v.as_f64())
        .unwrap_or(0.0) as u32;
    let calories = json.get("calories").and_then(|v| v.as_f64());
    let distance = json.get("distance").and_then(|v| v.as_f64());

    if duration_seconds == 0 {
        return None;
    }

    Some(ActivityRecord {
        id: format!("garmin:activity:{id}"),
        activity_type,
        started_at,
        duration_seconds,
        total_energy_kcal: calories,
        total_distance_meters: distance,
        source_device: Some("garmin".to_string()),
    })
}

/// Map weight JSON to PointMetric.
///
/// Garmin returns `{ "dateWeightList": [...] }` or direct array.
pub fn map_weight(json: &Value, date: NaiveDate) -> Option<PointMetric> {
    let empty = vec![];
    let entries = json
        .get("dateWeightList")
        .and_then(|v| v.as_array())
        .unwrap_or(&empty);
    let first = entries.first()?;
    let kg = first.get("weight").and_then(|v| v.as_f64())? / 1000.0;
    if kg == 0.0 {
        return None;
    }
    let id = first
        .get("samplePk")
        .and_then(|v| v.as_i64())
        .map(|pk| format!("garmin:weight:{pk}"))
        .unwrap_or_else(|| format!("garmin:weight:{date}"));
    Some(PointMetric {
        id,
        measured_at: date.to_string(),
        value: kg,
        unit: "kg".to_string(),
        source_device: Some("garmin".to_string()),
    })
}

/// Map SpO2 (blood oxygen) from daily SpO2 JSON.
///
/// Garmin returns `{ "spO2Measurements": [{ "value": 97, ... }, ...] }`
/// or `{ "avgSpO2": 97, ... }`. We extract the average.
pub fn map_spo2(json: &Value, date: NaiveDate) -> Option<DailyMetric> {
    // Try the direct average field first.
    if let Some(avg) = json.get("avgSpO2").and_then(|v| v.as_f64()) {
        if avg > 0.0 {
            return Some(DailyMetric {
                id: format!("garmin:spo2:{date}"),
                date,
                value: avg,
                unit: "%".to_string(),
                source_device: Some("garmin".to_string()),
            });
        }
    }
    // Fall back to computing from measurements array.
    let entries = json.get("spO2Measurements")?.as_array()?;
    let mut sum = 0.0;
    let mut count = 0;
    for entry in entries {
        if let Some(v) = entry.get("value").and_then(|v| v.as_f64()) {
            if v > 0.0 {
                sum += v;
                count += 1;
            }
        }
    }
    if count == 0 {
        return None;
    }
    Some(DailyMetric {
        id: format!("garmin:spo2:{date}"),
        date,
        value: sum / count as f64,
        unit: "%".to_string(),
        source_device: Some("garmin".to_string()),
    })
}

/// Map VO2 max from training status JSON.
pub fn map_vo2_max(json: &Value, date: NaiveDate) -> Option<DailyMetric> {
    let vo2 = json
        .get("mostRecentVO2Max")
        .or_else(|| json.get("vo2Max"))
        .and_then(|v| v.as_f64())?;
    if vo2 == 0.0 {
        return None;
    }
    Some(DailyMetric {
        id: format!("garmin:vo2max:{date}"),
        date,
        value: vo2,
        unit: "ml/kg/min".to_string(),
        source_device: Some("garmin".to_string()),
    })
}

/// Map training load from training status JSON.
///
/// Garmin returns `weeklyTrainingLoad` (float) and feedback labels
/// (`loadShortFeedback`, `loadMediumFeedback`, `loadLongFeedback`).
pub fn map_training_load(json: &Value, date: NaiveDate) -> Option<DailyMetric> {
    let value = json.get("weeklyTrainingLoad").and_then(|v| v.as_f64())?;
    if value == 0.0 {
        return None;
    }
    Some(DailyMetric {
        id: format!("garmin:training_load:{date}"),
        date,
        value,
        unit: "load".to_string(),
        source_device: Some("garmin".to_string()),
    })
}

/// Map training effect from training status JSON.
///
/// Garmin returns `trainingEffectLabel` (e.g. "Improving", "Maintaining",
/// "Recovery", "Strained") as a string. We encode it as a numeric score:
///   Improving = 4, Productive = 3, Maintaining = 2, Recovery = 1,
///   Strained/Overreaching = 0, Unknown = -1.
pub fn map_training_effect(json: &Value, date: NaiveDate) -> Option<DailyMetric> {
    let label = json
        .get("trainingEffectLabel")
        .or_else(|| json.get("trainingStatus"))
        .and_then(|v| v.as_str())?;
    let score = match label.to_lowercase().as_str() {
        "improving" => 4.0,
        "productive" => 3.0,
        "maintaining" => 2.0,
        "recovery" | "resting" => 1.0,
        "strained" | "overreaching" | "detraining" => 0.0,
        _ => return None,
    };
    Some(DailyMetric {
        id: format!("garmin:training_effect:{date}"),
        date,
        value: score,
        unit: "level".to_string(),
        source_device: Some("garmin".to_string()),
    })
}

// ---------------------------------------------------------------------------
// Range mappers — batch multiple days into one API call.
// ---------------------------------------------------------------------------

/// Map floors climbed from daily summary JSON.
///
/// Garmin returns `{ "floorsAscended": 5, ... }` in the daily summary.
pub fn map_floors_climbed(json: &Value, date: NaiveDate) -> Option<DailyMetric> {
    let value = json.get("floorsAscended").and_then(|v| v.as_f64())?;
    if value == 0.0 {
        return None;
    }
    Some(DailyMetric {
        id: format!("garmin:floors:{date}"),
        date,
        value,
        unit: "count".to_string(),
        source_device: Some("garmin".to_string()),
    })
}

/// Map steps JSON for a date range → Vec<DailyMetric>.
///
/// The Garmin range API returns 15-minute intervals spanning all days.
/// We group by calendar date (from `startGMT`) and sum each day.
pub fn map_steps_range(json: &Value) -> Vec<DailyMetric> {
    let intervals = match json.as_array() {
        Some(a) => a,
        None => return vec![],
    };

    let mut by_date: HashMap<String, f64> = HashMap::new();
    for item in intervals {
        let steps = item.get("steps").and_then(|v| v.as_f64()).unwrap_or(0.0);
        if steps == 0.0 {
            continue;
        }
        if let Some(start) = item.get("startGMT").and_then(|v| v.as_str()) {
            let date_str = &start[..10.min(start.len())];
            *by_date.entry(date_str.to_string()).or_insert(0.0) += steps;
        }
    }

    by_date
        .into_iter()
        .filter(|(_, v)| *v > 0.0)
        .filter_map(|(date_str, total)| {
            let date = NaiveDate::parse_from_str(&date_str, "%Y-%m-%d").ok()?;
            Some(DailyMetric {
                id: format!("garmin:steps:{date}"),
                date,
                value: total,
                unit: "steps".to_string(),
                source_device: Some("garmin".to_string()),
            })
        })
        .collect()
}

/// Map RHR JSON for a date range → Vec<DailyMetric>.
///
/// `WELLNESS_RESTING_HEART_RATE` array contains one entry per day
/// with `calendarDate` and `value`.
pub fn map_rhr_range(json: &Value) -> Vec<DailyMetric> {
    let metrics_map = match json
        .get("allMetrics")
        .and_then(|m| m.get("metricsMap"))
    {
        Some(m) => m,
        None => return vec![],
    };
    let rhr_array = match metrics_map
        .get("WELLNESS_RESTING_HEART_RATE")
        .and_then(|v| v.as_array())
    {
        Some(a) => a,
        None => return vec![],
    };

    rhr_array
        .iter()
        .filter_map(|entry| {
            let value = entry.get("value")?.as_f64()?;
            if value == 0.0 {
                return None;
            }
            let date_str = entry.get("calendarDate")?.as_str()?;
            let date = NaiveDate::parse_from_str(date_str, "%Y-%m-%d").ok()?;
            Some(DailyMetric {
                id: format!("garmin:rhr:{date}"),
                date,
                value,
                unit: "bpm".to_string(),
                source_device: Some("garmin".to_string()),
            })
        })
        .collect()
}

/// Map Body Battery JSON for a date range → Vec<BodyBatteryDay>.
///
/// The range API returns an array with one entry per day.
pub fn map_body_battery_range(json: &Value) -> Vec<BodyBatteryDay> {
    let entries = match json.as_array() {
        Some(a) => a,
        None => return vec![],
    };

    entries
        .iter()
        .filter_map(|entry| {
            let date_str = entry.get("date")?.as_str()?;
            let date = NaiveDate::parse_from_str(date_str, "%Y-%m-%d").ok()?;
            let charged = entry.get("charged")?.as_u64()? as u8;
            let drained = entry.get("drained")?.as_u64()? as u8;

            let values: Vec<u8> = entry
                .get("bodyBatteryValuesArray")
                .and_then(|v| v.as_array())
                .unwrap_or(&vec![])
                .iter()
                .filter_map(|slot| {
                    if let Some(arr) = slot.as_array() {
                        arr.get(1).and_then(|v| v.as_u64()).map(|n| n as u8)
                    } else {
                        slot.get("value").and_then(|v| v.as_u64()).map(|n| n as u8)
                    }
                })
                .collect();

            let min = if values.is_empty() {
                0u8
            } else {
                *values.iter().min().unwrap_or(&0)
            };
            let max = if values.is_empty() {
                charged
            } else {
                *values.iter().max().unwrap_or(&charged)
            };

            Some(BodyBatteryDay {
                id: format!("garmin:body_battery:{date}"),
                date,
                min,
                max,
                charged,
                drained,
            })
        })
        .collect()
}

/// Map stress JSON for a date range → Vec<DailyMetric>.
///
/// The range API returns an array of per-day objects with
/// `calendarDate` and `avgStressLevel`.
pub fn map_stress_range(json: &Value) -> Vec<DailyMetric> {
    let entries = match json.as_array() {
        Some(a) => a,
        None => return vec![],
    };

    entries
        .iter()
        .filter_map(|entry| {
            let value = entry.get("avgStressLevel")?.as_f64()?;
            if value == 0.0 {
                return None;
            }
            let date_str = entry
                .get("calendarDate")
                .or_else(|| entry.get("date"))
                .and_then(|v| v.as_str())?;
            let date = NaiveDate::parse_from_str(date_str, "%Y-%m-%d").ok()?;
            Some(DailyMetric {
                id: format!("garmin:stress:{date}"),
                date,
                value,
                unit: "level".to_string(),
                source_device: Some("garmin".to_string()),
            })
        })
        .collect()
}

/// Map weight JSON for a date range → Vec<PointMetric>.
///
/// `dateWeightList` entries each have a `date` field and `weight` (grams).
pub fn map_weight_range(json: &Value) -> Vec<PointMetric> {
    let empty = vec![];
    let entries = json
        .get("dateWeightList")
        .and_then(|v| v.as_array())
        .unwrap_or(&empty);

    entries
        .iter()
        .filter_map(|entry| {
            let kg = entry.get("weight")?.as_f64()? / 1000.0;
            if kg == 0.0 {
                return None;
            }
            let date_str = entry.get("date")?.as_str()?;
            let date = NaiveDate::parse_from_str(date_str, "%Y-%m-%d").ok()?;
            let id = entry
                .get("samplePk")
                .and_then(|v| v.as_i64())
                .map(|pk| format!("garmin:weight:{pk}"))
                .unwrap_or_else(|| format!("garmin:weight:{date}"));
            Some(PointMetric {
                id,
                measured_at: date.to_string(),
                value: kg,
                unit: "kg".to_string(),
                source_device: Some("garmin".to_string()),
            })
        })
        .collect()
}

/// Build a full HealthSnapshot from individual endpoint results.
pub fn build_snapshot(
    steps: Vec<DailyMetric>,
    sleep_sessions: Vec<SleepSession>,
    resting_hr: Vec<DailyMetric>,
    hrv: Vec<DailyMetric>,
    heart_rate: Vec<DailyMetric>,
    body_battery: Vec<BodyBatteryDay>,
    stress: Vec<DailyMetric>,
    weight: Vec<PointMetric>,
    vo2_max: Vec<DailyMetric>,
    floors_climbed: Vec<DailyMetric>,
    training_load: Vec<DailyMetric>,
    training_effect: Vec<DailyMetric>,
    spo2: Vec<DailyMetric>,
) -> HealthSnapshot {
    HealthSnapshot {
        steps,
        sleep_sessions,
        resting_hr,
        hrv,
        heart_rate,
        active_energy: vec![],
        vo2_max,
        weight,
        body_fat: vec![],
        floors_climbed,
        respiratory_rate: vec![],
        body_battery,
        stress,
        training_load,
        training_effect,
        spo2,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn date(s: &str) -> NaiveDate {
        NaiveDate::parse_from_str(s, "%Y-%m-%d").unwrap()
    }

    // ---- Steps ----

    #[test]
    fn steps_sums_15min_intervals() {
        let data = json!([
            {"startGMT": "2026-06-07T16:00:00.0", "endGMT": "2026-06-07T16:15:00.0", "steps": 100},
            {"startGMT": "2026-06-07T16:15:00.0", "endGMT": "2026-06-07T16:30:00.0", "steps": 250},
            {"startGMT": "2026-06-07T16:30:00.0", "endGMT": "2026-06-07T16:45:00.0", "steps": 0},
        ]);
        let m = map_steps(&data, date("2026-06-07")).unwrap();
        assert_eq!(m.value, 350.0);
        assert_eq!(m.unit, "steps");
        assert_eq!(m.id, "garmin:steps:2026-06-07");
    }

    #[test]
    fn steps_zero_returns_none() {
        let data = json!([
            {"steps": 0},
            {"steps": 0},
        ]);
        assert!(map_steps(&data, date("2026-06-07")).is_none());
    }

    // ---- Sleep ----

    #[test]
    fn sleep_parses_dto_with_stages() {
        let data = json!({
            "dailySleepDTO": {
                "id": 1780767017000i64,
                "sleepStartTimestampGMT": 1780767017000i64,
                "sleepTimeSeconds": 27035,
                "deepSleepSeconds": 6840,
                "lightSleepSeconds": 13680,
                "remSleepSeconds": 6540,
                "awakeSleepSeconds": 0,
                "avgHeartRate": 45.0
            }
        });
        let s = map_sleep(&data, date("2026-06-07")).unwrap();
        assert_eq!(s.duration_seconds, 27035);
        assert_eq!(s.id, "garmin:sleep:1780767017000");
        assert!(s.started_at.contains("2026")); // epoch ms → ISO 8601
        let hist = s.stage_histogram_json.unwrap();
        assert!(hist.contains("\"deep\":6840"));
        assert!(hist.contains("\"light\":13680"));
        assert!(hist.contains("\"rem\":6540"));
        assert!(hist.contains("\"awake\":0"));
    }

    #[test]
    fn sleep_zero_duration_returns_none() {
        let data = json!({"dailySleepDTO": {"sleepTimeSeconds": 0}});
        assert!(map_sleep(&data, date("2026-06-07")).is_none());
    }

    #[test]
    fn heart_rate_from_sleep() {
        let data = json!({
            "dailySleepDTO": {"avgHeartRate": 45.0}
        });
        let hr = map_heart_rate_from_sleep(&data, date("2026-06-07")).unwrap();
        assert_eq!(hr.value, 45.0);
        assert_eq!(hr.unit, "bpm");
    }

    // ---- All-day HR ----

    #[test]
    fn heart_rate_all_day_from_array() {
        let data = json!({
            "heartRateValues": [
                [1717700000000i64, 72.0],
                [1717700900000i64, 75.0],
                [1717701800000i64, 0.0],  // zero should be skipped
                [1717702700000i64, 68.0]
            ]
        });
        let hr = map_heart_rate_all_day(&data, date("2026-06-07")).unwrap();
        assert_eq!(hr.value, (72.0 + 75.0 + 68.0) / 3.0);
        assert_eq!(hr.unit, "bpm");
        assert_eq!(hr.id, "garmin:hr:2026-06-07");
    }

    #[test]
    fn heart_rate_all_day_empty_returns_none() {
        let data = json!({"heartRateValues": []});
        assert!(map_heart_rate_all_day(&data, date("2026-06-07")).is_none());
    }

    #[test]
    fn heart_rate_all_day_all_zeros_returns_none() {
        let data = json!({
            "heartRateValues": [
                [1717700000000i64, 0.0],
                [1717700900000i64, 0.0]
            ]
        });
        assert!(map_heart_rate_all_day(&data, date("2026-06-07")).is_none());
    }

    // ---- RHR ----

    #[test]
    fn rhr_from_metrics_map() {
        let data = json!({
            "allMetrics": {
                "metricsMap": {
                    "WELLNESS_RESTING_HEART_RATE": [
                        {"value": 40.0, "calendarDate": "2026-06-07"}
                    ]
                }
            }
        });
        let m = map_rhr(&data, date("2026-06-07")).unwrap();
        assert_eq!(m.value, 40.0);
        assert_eq!(m.id, "garmin:rhr:2026-06-07");
    }

    #[test]
    fn rhr_missing_metrics_returns_none() {
        let data = json!({"allMetrics": {"metricsMap": {}}});
        assert!(map_rhr(&data, date("2026-06-07")).is_none());
    }

    // ---- HRV ----

    #[test]
    fn hrv_from_summary() {
        let data = json!({
            "hrvSummary": {
                "lastNightAvg": 103,
                "weeklyAvg": 85
            }
        });
        let m = map_hrv(&data, date("2026-06-07")).unwrap();
        assert_eq!(m.value, 103.0);
        assert_eq!(m.unit, "ms");
    }

    // ---- Body Battery ----

    #[test]
    fn body_battery_from_array() {
        let data = json!([
            {
                "date": "2026-06-07",
                "charged": 71,
                "drained": 72,
                "bodyBatteryValuesArray": [[0, 55], [1, 60], [2, 71]]
            }
        ]);
        let bb = map_body_battery(&data, date("2026-06-07")).unwrap();
        assert_eq!(bb.charged, 71);
        assert_eq!(bb.drained, 72);
        assert_eq!(bb.min, 55);
        assert_eq!(bb.max, 71);
    }

    #[test]
    fn body_battery_empty_array_returns_none() {
        let data = json!([]);
        assert!(map_body_battery(&data, date("2026-06-07")).is_none());
    }

    // ---- Stress ----

    #[test]
    fn stress_from_avg() {
        let data = json!({
            "avgStressLevel": 19,
            "maxStressLevel": 86
        });
        let m = map_stress(&data, date("2026-06-07")).unwrap();
        assert_eq!(m.value, 19.0);
        assert_eq!(m.unit, "level");
    }

    // ---- Activity ----

    #[test]
    fn activity_cycling() {
        let data = json!({
            "activityId": 12345678901i64,
            "activityName": "海淀区 骑行",
            "activityType": {"typeKey": "cycling"},
            "startTimeGMT": "2026-06-08 14:21:29",
            "duration": 1280.6619873046875,
            "distance": 6397.68017578125,
            "calories": 183.0
        });
        let a = map_activity(&data).unwrap();
        assert_eq!(a.activity_type, "cycling");
        assert_eq!(a.duration_seconds, 1280);
        assert_eq!(a.total_energy_kcal, Some(183.0));
        assert_eq!(a.total_distance_meters, Some(6397.68017578125));
        assert_eq!(a.id, "garmin:activity:12345678901");
    }

    #[test]
    fn activity_zero_duration_returns_none() {
        let data = json!({"activityId": 1, "duration": 0.0});
        assert!(map_activity(&data).is_none());
    }

    // ---- VO2 Max ----

    #[test]
    fn vo2_max_from_training_status() {
        let data = json!({"mostRecentVO2Max": 48.2});
        let m = map_vo2_max(&data, date("2026-06-07")).unwrap();
        assert_eq!(m.value, 48.2);
        assert_eq!(m.unit, "ml/kg/min");
    }

    #[test]
    fn vo2_max_zero_returns_none() {
        let data = json!({"mostRecentVO2Max": 0.0});
        assert!(map_vo2_max(&data, date("2026-06-07")).is_none());
    }

    // ---- Build snapshot ----

    // ---- Floors climbed ----

    #[test]
    fn floors_climbed_from_daily_summary() {
        let data = json!({
            "floorsAscended": 5,
            "floorsDescended": 3
        });
        let m = map_floors_climbed(&data, date("2026-06-07")).unwrap();
        assert_eq!(m.value, 5.0);
        assert_eq!(m.unit, "count");
        assert_eq!(m.id, "garmin:floors:2026-06-07");
    }

    #[test]
    fn floors_climbed_zero_returns_none() {
        let data = json!({"floorsAscended": 0});
        assert!(map_floors_climbed(&data, date("2026-06-07")).is_none());
    }

    #[test]
    fn floors_climbed_missing_field_returns_none() {
        let data = json!({"someOtherField": 10});
        assert!(map_floors_climbed(&data, date("2026-06-07")).is_none());
    }

    // ---- Training load ----

    #[test]
    fn training_load_from_status() {
        let data = json!({
            "weeklyTrainingLoad": 420.5,
            "loadShortFeedback": "OPTIMAL",
            "loadMediumFeedback": "OPTIMAL"
        });
        let m = map_training_load(&data, date("2026-06-07")).unwrap();
        assert_eq!(m.value, 420.5);
        assert_eq!(m.unit, "load");
        assert_eq!(m.id, "garmin:training_load:2026-06-07");
    }

    #[test]
    fn training_load_zero_returns_none() {
        let data = json!({"weeklyTrainingLoad": 0.0});
        assert!(map_training_load(&data, date("2026-06-07")).is_none());
    }

    #[test]
    fn training_load_missing_field_returns_none() {
        let data = json!({"mostRecentVO2Max": 48.0});
        assert!(map_training_load(&data, date("2026-06-07")).is_none());
    }

    // ---- Training effect ----

    #[test]
    fn training_effect_improving() {
        let data = json!({"trainingEffectLabel": "Improving"});
        let m = map_training_effect(&data, date("2026-06-07")).unwrap();
        assert_eq!(m.value, 4.0);
        assert_eq!(m.unit, "level");
    }

    #[test]
    fn training_effect_maintaining() {
        let data = json!({"trainingEffectLabel": "Maintaining"});
        let m = map_training_effect(&data, date("2026-06-07")).unwrap();
        assert_eq!(m.value, 2.0);
    }

    #[test]
    fn training_effect_strained() {
        let data = json!({"trainingEffectLabel": "Strained"});
        let m = map_training_effect(&data, date("2026-06-07")).unwrap();
        assert_eq!(m.value, 0.0);
    }

    #[test]
    fn training_effect_unknown_label_returns_none() {
        let data = json!({"trainingEffectLabel": "SomeNewLabel"});
        assert!(map_training_effect(&data, date("2026-06-07")).is_none());
    }

    #[test]
    fn training_effect_missing_field_returns_none() {
        let data = json!({"mostRecentVO2Max": 48.0});
        assert!(map_training_effect(&data, date("2026-06-07")).is_none());
    }

    // ---- SpO2 ----

    #[test]
    fn spo2_from_avg_field() {
        let data = json!({"avgSpO2": 97.5});
        let m = map_spo2(&data, date("2026-06-07")).unwrap();
        assert_eq!(m.value, 97.5);
        assert_eq!(m.unit, "%");
        assert_eq!(m.id, "garmin:spo2:2026-06-07");
    }

    #[test]
    fn spo2_from_measurements() {
        let data = json!({
            "spO2Measurements": [
                {"value": 97.0},
                {"value": 98.0},
                {"value": 96.0}
            ]
        });
        let m = map_spo2(&data, date("2026-06-07")).unwrap();
        assert_eq!(m.value, (97.0 + 98.0 + 96.0) / 3.0);
    }

    #[test]
    fn spo2_empty_returns_none() {
        let data = json!({"spO2Measurements": []});
        assert!(map_spo2(&data, date("2026-06-07")).is_none());
    }

    #[test]
    fn spo2_zero_avg_returns_none() {
        let data = json!({"avgSpO2": 0.0});
        assert!(map_spo2(&data, date("2026-06-07")).is_none());
    }

    #[test]
    fn build_snapshot_combines_all_fields() {
        let snap = build_snapshot(
            vec![DailyMetric {
                id: "garmin:steps:2026-06-07".into(),
                date: date("2026-06-07"),
                value: 10000.0,
                unit: "steps".into(),
                source_device: Some("garmin".into()),
            }],
            vec![],
            vec![],
            vec![],
            vec![],
            vec![],
            vec![],
            vec![],
            vec![],
            vec![],
            vec![],
            vec![],
            vec![],
        );
        assert_eq!(snap.steps.len(), 1);
        assert_eq!(snap.sleep_sessions.len(), 0);
        assert_eq!(snap.active_energy.len(), 0); // Garmin doesn't provide this
        assert_eq!(snap.floors_climbed.len(), 0);
        assert_eq!(snap.training_load.len(), 0);
        assert_eq!(snap.training_effect.len(), 0);
        assert_eq!(snap.spo2.len(), 0);
    }
}
