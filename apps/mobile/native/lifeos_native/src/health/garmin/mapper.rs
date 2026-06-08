//! Garmin JSON → HealthSnapshot mapping.
//!
//! Each function takes raw JSON from a Garmin API endpoint and produces
//! normalized types. Stable IDs use the `garmin:` prefix for dedup.
//!
//! Field shapes are validated against real Garmin CN API responses
//! (2026-06-08 probe output).

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
        // Convert ms to DateTime UTC
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

/// Map heart rate from sleep or daily summary JSON.
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
            // Each slot is [timestamp, value] or {"value": N}
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
        charged // fallback
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
    // Duration is in seconds (float).
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
    let kg = first.get("weight").and_then(|v| v.as_f64())? / 1000.0; // Garmin stores grams
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
) -> HealthSnapshot {
    HealthSnapshot {
        steps,
        sleep_sessions,
        resting_hr,
        hrv,
        heart_rate,
        active_energy: vec![],  // Garmin doesn't have a direct active energy endpoint
        vo2_max,
        weight,
        body_fat: vec![],       // Not available from Garmin
        floors_climbed: vec![], // Available but low priority
        respiratory_rate: vec![],
        body_battery,
        stress,
    }
}
