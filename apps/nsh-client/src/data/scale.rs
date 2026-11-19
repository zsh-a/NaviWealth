//! Rust-owned scale sessions and reviewed, atomic health measurements.
//! The UI carries opaque identifiers; it cannot supply a replacement estimate.
use std::{cell::RefCell, rc::Rc};

use navi_health::scale::{DeviceProtocol, LiveReading, Measurement, Session, UserProfile};
use nsh_core::prelude::*;
use nsh_core::storage::Storage;
use rusqlite::{Connection, OptionalExtension, params};
use serde::{Deserialize, Serialize};

use super::{body_metrics, clock, db, settings, weights};
use crate::domain::{meal::Day, weight};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Device {
    pub id: String,
    pub name: String,
}
impl Device {
    fn valid(&self) -> bool {
        !self.id.is_empty()
            && self.id.len() <= 128
            && self.name.len() <= 128
            && !self.id.chars().any(char::is_control)
            && !self.name.chars().any(char::is_control)
    }
}

#[derive(Serialize, Deserialize)]
pub struct RememberedScale {
    pub device: Device,
    pub identity: DeviceProtocol,
}

const REMEMBERED_SCALE_KEY: &str = "scale.remembered-device.v1";

pub fn remembered() -> Option<RememberedScale> {
    let saved: RememberedScale =
        serde_json::from_str(&Storage::get_item(REMEMBERED_SCALE_KEY)?).ok()?;
    saved.device.valid().then_some(saved)
}

pub fn remember(session_id: &str) -> Option<Device> {
    let active = live().get_untracked().0?;
    if active.start.session_id != session_id {
        return None;
    }
    let saved = RememberedScale {
        device: active.device.clone(),
        identity: active.identity.clone(),
    };
    let encoded = serde_json::to_string(&saved).ok()?;
    Storage::set_item(REMEMBERED_SCALE_KEY, &encoded).ok()?;
    Some(saved.device)
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Start {
    pub session_id: String,
    pub profile: UserProfile,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Preview {
    pub session_id: String,
    pub token: String,
    pub day: Day,
    pub measured_at_ms: i64,
    pub device: Device,
    pub measurement: Measurement,
    pub existing_kg: Option<f64>,
}
impl Preview {
    fn valid(&self) -> bool {
        self.session_id.len() == 32
            && self.token.len() == 32
            && self.measured_at_ms > 0
            && self.device.valid()
            && self.measurement.valid()
            && weight::valid_kg(self.measurement.weight_kg())
            && self.existing_kg.is_none_or(weight::valid_kg)
    }
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Confirmed {
    pub day: Day,
    pub weight_kg: f64,
    pub already_saved: bool,
}
#[derive(Clone, PartialEq, Serialize, Deserialize)]
struct Draft {
    preview: Preview,
    revision: i64,
}
#[derive(Clone, PartialEq, Serialize, Deserialize)]
struct Saved {
    preview: Preview,
    confirmed_at_ms: i64,
}
struct Active {
    start: Start,
    device: Device,
    identity: DeviceProtocol,
    day: Day,
    revision: i64,
    existing_kg: Option<f64>,
    protocol: RefCell<Session>,
}
#[derive(Clone, Default)]
struct Live(Option<Rc<Active>>);
impl PartialEq for Live {
    fn eq(&self, other: &Self) -> bool {
        match (&self.0, &other.0) {
            (Some(a), Some(b)) => Rc::ptr_eq(a, b),
            (None, None) => true,
            _ => false,
        }
    }
}
fn live() -> Signal<Live> {
    global::<Live>()
}

// A failed deletion can leave a stale draft in SQLite. Quarantine it even
// when SQLite is read-only, using the app's separate preferences store.
const DRAFT_QUARANTINE_KEY: &str = "scale.draft-quarantine.v1";

#[derive(Clone, Default, PartialEq)]
struct DraftQuarantine(bool);

fn drafts_quarantined() -> bool {
    global::<DraftQuarantine>().get_untracked().0
        || Storage::get_item(DRAFT_QUARANTINE_KEY).is_some()
}

fn quarantine_drafts() {
    global::<DraftQuarantine>().set(DraftQuarantine(true));
    if Storage::set_item(DRAFT_QUARANTINE_KEY, "1").is_err() {
        log::error!("scale: could not persist draft quarantine");
    }
}

fn random_id() -> Result<String, String> {
    let mut bytes = [0_u8; 16];
    getrandom::fill(&mut bytes).map_err(|_| "Could not create a measurement session".to_owned())?;
    Ok(bytes.iter().map(|b| format!("{b:02x}")).collect())
}
fn sql_error(_: rusqlite::Error) -> String {
    "Could not save the measurement. Check device storage and try again.".into()
}
fn revision(c: &Connection, day: Day) -> rusqlite::Result<i64> {
    Ok(c.query_row(
        "SELECT revision FROM weight_revisions WHERE day=?1",
        [day.to_string()],
        |r| r.get(0),
    )
    .optional()?
    .unwrap_or(0))
}
fn weight_on(c: &Connection, day: Day) -> rusqlite::Result<Option<f64>> {
    c.query_row(
        "SELECT kg FROM weights WHERE day=?1",
        [day.to_string()],
        |r| r.get(0),
    )
    .optional()
}

/// Distinguishes absent scale provenance from evidence that cannot be trusted.
#[derive(Clone, PartialEq)]
pub enum MeasurementEvidence {
    Legacy,
    Confirmed(Measurement),
    Rejected,
}

/// Reads scale evidence without changing storage or consulting today's profile.
/// Callers track weight/body-metrics signals to refresh this read-only lookup.
pub fn evidence_on(day: Day) -> MeasurementEvidence {
    db::with(|c| evidence_on_in(c, day)).unwrap_or(MeasurementEvidence::Rejected)
}

/// Returns only confirmed evidence, retaining its original precision and profile.
pub fn measurement_on(day: Day) -> Option<navi_health::scale::Measurement> {
    match evidence_on(day) {
        MeasurementEvidence::Confirmed(measurement) => Some(measurement),
        MeasurementEvidence::Legacy | MeasurementEvidence::Rejected => None,
    }
}

fn evidence_on_in(c: &Connection, day: Day) -> MeasurementEvidence {
    // Keep provenance and both associated records in one consistent read snapshot.
    let read = || -> Result<MeasurementEvidence, String> {
        let tx = c.unchecked_transaction().map_err(sql_error)?;
        let row: Option<(String, String)> = tx
            .query_row(
                "SELECT session_id,body FROM scale_measurements WHERE day=?1",
                [day.to_string()],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .optional()
            .map_err(sql_error)?;
        let evidence = match row {
            Some((id, body)) => MeasurementEvidence::Confirmed(
                validate_record(&tx, &day.to_string(), &id, &body)?
                    .preview
                    .measurement,
            ),
            None => MeasurementEvidence::Legacy,
        };
        tx.commit().map_err(sql_error)?;
        Ok(evidence)
    };
    read().unwrap_or(MeasurementEvidence::Rejected)
}

/// Starts a fresh foreground session, snapshotting the owner profile and today's entry.
/// Starting a new session retires old pending decisions and callback identifiers.
pub fn begin(device: Device, identity: DeviceProtocol) -> Result<Start, String> {
    if !device.valid() {
        return Err("Invalid scale identity".into());
    }
    let profile = UserProfile {
        height_cm: settings::height_cm()
            .ok_or("Set height in Body profile before connecting the scale")?,
        age_years: settings::age_years()
            .ok_or("Set date of birth in Body profile before connecting the scale")?,
        sex: settings::sex().ok_or("Set sex in Body profile before connecting the scale")?,
    };
    let protocol =
        Session::new(profile.clone()).map_err(|_| "Check the body profile".to_owned())?;
    let start = Start {
        session_id: random_id()?,
        profile,
    };
    let day = clock::today();
    let (baseline, existing_kg) = db::with(|c| -> rusqlite::Result<_> {
        let tx = c.unchecked_transaction()?;
        let result = (revision(&tx, day)?, weight_on(&tx, day)?);
        tx.execute("DELETE FROM scale_drafts", [])?;
        tx.commit()?;
        Ok(result)
    })
    .ok_or("Local data unavailable")?
    .map_err(sql_error)?;
    // The transaction retired every old draft before allowing a new one.
    Storage::remove_item(DRAFT_QUARANTINE_KEY);
    global::<DraftQuarantine>().set(DraftQuarantine::default());
    live().set(Live(Some(Rc::new(Active {
        start: start.clone(),
        device,
        identity,
        day,
        revision: baseline,
        existing_kg,
        protocol: RefCell::new(protocol),
    }))));
    Ok(start)
}

/// Feeds one notification for the current session. Late/foreign callbacks are rejected.
/// Duplicate packets keep the same opaque review token; changed evidence rotates it.
pub fn feed(session_id: &str, bytes: &[u8]) -> Result<Option<Preview>, String> {
    let active = live()
        .get_untracked()
        .0
        .ok_or("The scale session has ended")?;
    if active.start.session_id != session_id {
        return Err("The scale session has ended".into());
    }
    if clock::today() != active.day {
        invalidate(session_id)?;
        return Err("The day changed. Start a new measurement.".into());
    }
    let (result, latest) = {
        let mut protocol = active.protocol.borrow_mut();
        let result = protocol.feed(bytes);
        (result, protocol.latest())
    };
    let clear = || {
        delete_draft(session_id).inspect_err(|_| {
            quarantine_drafts();
            stop_session(session_id);
        })
    };
    let measurement = match result {
        Err(_) => {
            invalidate(session_id)?;
            return Err("The scale sent an unreadable measurement. Try again.".into());
        }
        Ok(Some(measurement)) => measurement,
        Ok(None) => {
            let Some(latest) = latest else {
                clear()?;
                return Ok(None);
            };
            return Ok(pending()?.filter(|p| p.session_id == session_id && p.measurement == latest));
        }
    };
    if !measurement.valid() || !weight::valid_kg(measurement.weight_kg()) {
        invalidate(session_id)?;
        return Err("The scale sent an invalid measurement".into());
    }
    let existing = pending()?;
    if let Some(preview) =
        existing.filter(|p| p.session_id == session_id && p.measurement == measurement)
    {
        return Ok(Some(preview));
    }
    // Retire an older candidate before preparing changed evidence. A failed
    // allocation or draft write must never leave its old review token usable.
    clear()?;
    let preview = Preview {
        session_id: session_id.into(),
        token: random_id()?,
        day: active.day,
        measured_at_ms: clock::now_ms(),
        device: active.device.clone(),
        measurement,
        existing_kg: active.existing_kg,
    };
    let draft = Draft {
        preview: preview.clone(),
        revision: active.revision,
    };
    let body = serde_json::to_string(&draft).map_err(|_| "Invalid scale draft")?;
    db::with(|c| c.execute("INSERT INTO scale_drafts(session_id,body) VALUES(?1,?2) ON CONFLICT(session_id) DO UPDATE SET body=excluded.body", params![session_id,body])).ok_or("Local data unavailable")?.map_err(sql_error)?;
    Ok(Some(preview))
}

/// The last review survives app reload; it never recreates an active BLE connection.
pub fn pending() -> Result<Option<Preview>, String> {
    if drafts_quarantined() {
        return Ok(None);
    }
    db::with(|c| -> Result<_, String> {
        let body: Option<String> = c
            .query_row("SELECT body FROM scale_drafts LIMIT 1", [], |r| r.get(0))
            .optional()
            .map_err(sql_error)?;
        body.map(|body| {
            let draft: Draft = serde_json::from_str(&body).map_err(|_| "Invalid scale draft")?;
            if !draft.preview.valid() {
                return Err("Invalid scale draft".into());
            }
            Ok(draft.preview)
        })
        .transpose()
    })
    .ok_or("Local data unavailable")?
}

/// Cancels exactly this session and its pending review. Other sessions are unaffected.
pub fn cancel(session_id: &str) -> Result<(), String> {
    delete_draft(session_id)?;
    stop_session(session_id);
    Ok(())
}

/// Rejects untrusted evidence before attempting draft deletion. A failed
/// deletion must never return that draft to the review flow.
pub fn invalidate(session_id: &str) -> Result<(), String> {
    stop_session(session_id);
    delete_draft(session_id).inspect_err(|_| quarantine_drafts())
}

fn delete_draft(session_id: &str) -> Result<(), String> {
    db::with(|c| c.execute("DELETE FROM scale_drafts WHERE session_id=?1", [session_id]))
        .ok_or("Local data unavailable")?
        .map_err(sql_error)?;
    Ok(())
}

/// Stops accepting notifications while retaining a completed review for confirmation.
/// Called when the Android connection closes; reconnecting always starts a fresh session.
pub fn pause(session_id: &str) -> Result<(), String> {
    stop_session(session_id);
    Ok(())
}

pub fn live_reading(session_id: &str) -> Option<LiveReading> {
    let active = live().get_untracked().0?;
    if active.start.session_id != session_id {
        return None;
    }
    active.protocol.borrow().live_reading()
}

fn stop_session(session_id: &str) {
    if live()
        .get_untracked()
        .0
        .is_some_and(|a| a.start.session_id == session_id)
    {
        live().set(Live::default());
    }
}

/// Confirms the Rust-owned review. Same-day replacement is an explicit UI decision.
pub fn confirm(session_id: &str, token: &str, replace_existing: bool) -> Result<Confirmed, String> {
    if drafts_quarantined() {
        return Err("The measurement is no longer stable".into());
    }
    if let Some(active) = live()
        .get_untracked()
        .0
        .filter(|a| a.start.session_id == session_id)
    {
        let pending = pending()?.ok_or("The measurement is no longer stable")?;
        if active.protocol.borrow().latest().as_ref() != Some(&pending.measurement) {
            return Err("The measurement has changed. Wait for a stable reading.".into());
        }
    }
    let result = db::with(|c| confirm_in(c, session_id, token, replace_existing, clock::now_ms()))
        .ok_or("Local data unavailable")??;
    if live()
        .get_untracked()
        .0
        .is_some_and(|a| a.start.session_id == session_id)
    {
        live().set(Live::default());
    }
    weights::load();
    body_metrics::load();
    Ok(result)
}
fn confirm_in(
    c: &Connection,
    session_id: &str,
    token: &str,
    replace_existing: bool,
    now: i64,
) -> Result<Confirmed, String> {
    let tx = c.unchecked_transaction().map_err(sql_error)?;
    let kept: Option<String> = tx
        .query_row(
            "SELECT body FROM scale_measurements WHERE session_id=?1",
            [session_id],
            |r| r.get(0),
        )
        .optional()
        .map_err(sql_error)?;
    if let Some(body) = kept {
        let saved: Saved = serde_json::from_str(&body).map_err(|_| "Invalid saved measurement")?;
        if !saved.preview.valid() || saved.preview.token != token {
            return Err("The review has changed. Review the latest measurement.".into());
        }
        return Ok(Confirmed {
            day: saved.preview.day,
            weight_kg: weight::rounded(saved.preview.measurement.weight_kg()),
            already_saved: true,
        });
    }
    let body: String = tx
        .query_row(
            "SELECT body FROM scale_drafts WHERE session_id=?1",
            [session_id],
            |r| r.get(0),
        )
        .optional()
        .map_err(sql_error)?
        .ok_or("The scale draft is no longer available")?;
    let draft: Draft = serde_json::from_str(&body).map_err(|_| "Invalid scale draft")?;
    let p = &draft.preview;
    if !p.valid() || p.session_id != session_id || p.token != token {
        return Err("The review has changed. Review the latest measurement.".into());
    }
    if revision(&tx, p.day).map_err(sql_error)? != draft.revision {
        return Err("Today's weight changed. Start a new measurement before replacing it.".into());
    }
    let old = weight_on(&tx, p.day).map_err(sql_error)?;
    if old.is_some() && !replace_existing {
        return Err("Confirm replacement of today's existing weight first".into());
    }
    let kg = weight::rounded(p.measurement.weight_kg());
    tx.execute("INSERT INTO weights(day,kg,logged_at_ms) VALUES(?1,?2,?3) ON CONFLICT(day) DO UPDATE SET kg=excluded.kg,logged_at_ms=excluded.logged_at_ms", params![p.day.to_string(),kg,p.measured_at_ms]).map_err(sql_error)?;
    tx.execute("DELETE FROM body_metrics WHERE day=?1", [p.day.to_string()])
        .map_err(sql_error)?;
    if let Some(metrics) = &p.measurement.metrics {
        let body = serde_json::to_string(metrics).map_err(|_| "Invalid composition")?;
        tx.execute(
            "INSERT INTO body_metrics(day,body,fetched_at_ms) VALUES(?1,?2,?3)",
            params![p.day.to_string(), body, p.measured_at_ms],
        )
        .map_err(sql_error)?;
    }
    let saved = Saved {
        preview: p.clone(),
        confirmed_at_ms: now.max(p.measured_at_ms),
    };
    let body = serde_json::to_string(&saved).map_err(|_| "Invalid scale provenance")?;
    tx.execute("INSERT INTO scale_measurements(day,session_id,body) VALUES(?1,?2,?3) ON CONFLICT(day) DO UPDATE SET session_id=excluded.session_id,body=excluded.body", params![p.day.to_string(),session_id,body]).map_err(sql_error)?;
    tx.execute("DELETE FROM scale_drafts WHERE session_id=?1", [session_id])
        .map_err(sql_error)?;
    tx.commit().map_err(sql_error)?;
    Ok(Confirmed {
        day: p.day,
        weight_kg: kg,
        already_saved: false,
    })
}

/// Called inside the same transaction as a manual/capture weight change.
/// Compare before updating the weight row. The same displayed weight preserves its evidence.
pub fn reconcile_weight_in_transaction(
    c: &Connection,
    day: &str,
    new_kg: Option<f64>,
) -> rusqlite::Result<()> {
    let old: Option<f64> = c
        .query_row("SELECT kg FROM weights WHERE day=?1", [day], |r| r.get(0))
        .optional()?;
    if old != new_kg {
        c.execute("DELETE FROM body_metrics WHERE day=?1", [day])?;
        c.execute("DELETE FROM scale_measurements WHERE day=?1", [day])?;
    }
    Ok(())
}

/// Backup validation ties scale provenance to the exact kept weight and composition.
pub(super) fn validate_saved(c: &Connection) -> Result<(), String> {
    let mut query = c
        .prepare("SELECT day,session_id,body FROM scale_measurements")
        .map_err(sql_error)?;
    let rows = query
        .query_map([], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, String>(2)?,
            ))
        })
        .map_err(sql_error)?;
    for row in rows {
        let (day, id, body) = row.map_err(sql_error)?;
        validate_record(c, &day, &id, &body)?;
    }
    Ok(())
}

fn validate_record(c: &Connection, day: &str, id: &str, body: &str) -> Result<Saved, String> {
    let saved: Saved = serde_json::from_str(body).map_err(|_| "Invalid scale provenance")?;
    let p = &saved.preview;
    if !p.valid()
        || p.day.to_string() != day
        || p.session_id != id
        || saved.confirmed_at_ms < p.measured_at_ms
        || weight_on(c, p.day).map_err(sql_error)?
            != Some(weight::rounded(p.measurement.weight_kg()))
    {
        return Err("Scale provenance does not match the kept weight".into());
    }
    let body: Option<String> = c
        .query_row("SELECT body FROM body_metrics WHERE day=?1", [day], |r| {
            r.get(0)
        })
        .optional()
        .map_err(sql_error)?;
    let metrics = body
        .map(|b| serde_json::from_str(&b))
        .transpose()
        .map_err(|_| "Invalid composition")?;
    if metrics != p.measurement.metrics {
        return Err("Scale provenance does not match the composition".into());
    }
    Ok(saved)
}

#[cfg(test)]
mod tests {
    use super::*;
    use navi_health::bodycomp::Sex;

    #[component]
    fn UnavailableDatabaseProbe() -> impl IntoElement {
        let day = "2026-11-18".parse().unwrap();
        assert!(db::with(|_| ()).is_none());
        assert!(matches!(evidence_on(day), MeasurementEvidence::Rejected));
        assert!(measurement_on(day).is_none());
        text("Unavailable database rejected")
    }

    #[test]
    fn unavailable_database_is_rejected_rather_than_legacy() {
        let config =
            nsh_engine::EngineConfig::new(nsh_engine::Root::of::<UnavailableDatabaseProbe>());
        let mut app = nsh_testing::Headless::start(config).unwrap();
        app.wait_for("Unavailable database rejected").unwrap();
    }

    #[component]
    fn SessionProbe() -> impl IntoElement {
        db::open().unwrap();
        settings::load();
        weights::load();
        body_metrics::load();
        let first = pending().unwrap();
        let id = signal(
            first
                .as_ref()
                .map(|p| p.session_id.clone())
                .unwrap_or_default(),
        );
        let reviewed = signal(first);
        let status = signal("Ready".to_owned());
        let packet = |hex: &str| -> Vec<u8> {
            (0..hex.len())
                .step_by(2)
                .map(|i| u8::from_str_radix(&hex[i..i + 2], 16).unwrap())
                .collect()
        };
        view()
            .gap_2()
            .child(
                nsh_base::button()
                    .min_h(px(44.0))
                    .child(text("Begin"))
                    .on_press(move || {
                        match begin(
                            Device {
                                id: "device".into(),
                                name: "AFU-WL".into(),
                            },
                            DeviceProtocol {
                                device_type: 0x27,
                                protocol_ver: 2,
                            },
                        ) {
                            Ok(start) => {
                                id.set(start.session_id);
                                reviewed.set(None);
                                status.set("Started".into());
                            }
                            Err(e) => status.set(e),
                        }
                    }),
            )
            .child(
                nsh_base::button()
                    .min_h(px(44.0))
                    .child(text("Stable"))
                    .on_press(move || {
                        match feed(
                            &id.get_untracked(),
                            &packet("AC298068E2C2020005400000000000000029D511"),
                        ) {
                            Ok(Some(p)) => {
                                reviewed.set(Some(p));
                                status.set("Review".into());
                            }
                            Ok(None) => status.set("No reading".into()),
                            Err(e) => status.set(e),
                        }
                    }),
            )
            .child(
                nsh_base::button()
                    .min_h(px(44.0))
                    .child(text("Composition"))
                    .on_press(move || {
                        let p = feed(
                            &id.get_untracked(),
                            &packet("AC290200020501D8018068E2C20000000029D60E"),
                        )
                        .unwrap()
                        .unwrap();
                        reviewed.set(Some(p));
                        status.set("Composition review".into());
                    }),
            )
            .child(
                nsh_base::button()
                    .min_h(px(44.0))
                    .child(text("Change profile"))
                    .on_press(move || {
                        settings::save_height(Some(180));
                        settings::save_age(Some(45));
                        settings::save_sex(Some(Sex::Female));
                        status.set("Profile changed".into());
                    }),
            )
            .child(
                nsh_base::button()
                    .min_h(px(44.0))
                    .child(text("Check frozen measurement"))
                    .on_press(move || {
                        let p = reviewed.get_untracked().unwrap();
                        let kept = measurement_on(p.day);
                        status.set(
                            if kept == Some(p.measurement) {
                                "Original measurement retained"
                            } else {
                                "No matching measurement"
                            }
                            .into(),
                        );
                    }),
            )
            .child(
                nsh_base::button()
                    .min_h(px(44.0))
                    .child(text("Bad packet"))
                    .on_press(move || {
                        let result = feed(&id.get_untracked(), &[0]);
                        status.set(
                            if result.is_err() {
                                "Packet rejected"
                            } else {
                                "Unexpected"
                            }
                            .into(),
                        );
                    }),
            )
            .child(
                nsh_base::button()
                    .min_h(px(44.0))
                    .child(text("Pause"))
                    .on_press(move || {
                        pause(&id.get_untracked()).unwrap();
                        status.set("Paused".into());
                    }),
            )
            .child(
                nsh_base::button()
                    .min_h(px(44.0))
                    .child(text("Check retained review"))
                    .on_press(move || {
                        status.set(if pending().unwrap().is_some() {
                            "Retained review".into()
                        } else {
                            "No retained review".into()
                        });
                    }),
            )
            .child(
                nsh_base::button()
                    .min_h(px(44.0))
                    .child(text("Cancel"))
                    .on_press(move || {
                        cancel(&id.get_untracked()).unwrap();
                        status.set("Cancelled".into());
                    }),
            )
            .child(
                nsh_base::button()
                    .min_h(px(44.0))
                    .child(text("Confirm"))
                    .on_press(move || {
                        let p = reviewed.get_untracked().unwrap();
                        status.set(match confirm(&p.session_id, &p.token, true) {
                            Ok(r) => format!("Saved:{}:{}", r.already_saved, r.weight_kg),
                            Err(_) => "Confirmation rejected".into(),
                        });
                    }),
            )
            .child(text(move || status.get()))
    }
    fn probe(dir: &std::path::Path) -> nsh_testing::Headless {
        probe_with_storage(dir, profile_storage())
    }
    fn profile_storage() -> std::sync::Arc<nsh_testing::MemoryStorage> {
        nsh_testing::MemoryStorage::new(vec![(
            "settings.v1".into(),
            serde_json::json!({"height_cm":170,"age_years":23,"sex":"male"}).to_string(),
        )])
    }
    fn probe_with_storage(
        dir: &std::path::Path,
        storage: std::sync::Arc<nsh_testing::MemoryStorage>,
    ) -> nsh_testing::Headless {
        let mut config = nsh_engine::EngineConfig::new(nsh_engine::Root::of::<SessionProbe>());
        config.data_dir = Some(dir.to_path_buf());
        config.storage = Some(storage);
        let mut app = nsh_testing::Headless::start(config).unwrap();
        app.wait_for("Ready").unwrap();
        app
    }
    #[test]
    fn native_session_rejects_bad_packets_and_late_callbacks_without_saving() {
        let dir = tempfile::tempdir().unwrap();
        let mut app = probe(dir.path());
        app.press("Begin").unwrap();
        app.press("Stable").unwrap();
        app.wait_for("Review").unwrap();
        app.press("Bad packet").unwrap();
        app.wait_for("Packet rejected").unwrap();
        app.press("Confirm").unwrap();
        app.wait_for("Confirmation rejected").unwrap();
        app.press("Begin").unwrap();
        app.press("Stable").unwrap();
        app.press("Cancel").unwrap();
        app.press("Stable").unwrap();
        app.wait_for("The scale session has ended").unwrap();
        app.press("Confirm").unwrap();
        app.wait_for("Confirmation rejected").unwrap();
    }
    #[test]
    fn a_failed_invalidation_deletion_cannot_restore_the_old_draft() {
        let dir = tempfile::tempdir().unwrap();
        let storage = profile_storage();
        let mut app = probe_with_storage(dir.path(), storage.clone());
        app.press("Begin").unwrap();
        app.press("Stable").unwrap();
        app.wait_for("Review").unwrap();
        let db_path = std::fs::read_dir(dir.path())
            .unwrap()
            .flatten()
            .map(|entry| entry.path().join("naviwealth.sqlite"))
            .find(|path| path.is_file())
            .expect("NSH created the database in the app's data directory");
        let db = Connection::open(db_path).unwrap();
        db.execute_batch(
            "CREATE TRIGGER fail_delete BEFORE DELETE ON scale_drafts
             BEGIN SELECT RAISE(ABORT, 'temporary write failure'); END;",
        )
        .unwrap();
        app.press("Bad packet").unwrap();
        app.wait_for("Packet rejected").unwrap();
        assert_eq!(
            db.query_row("SELECT COUNT(*) FROM scale_drafts", [], |row| row
                .get::<_, i64>(0))
                .unwrap(),
            1
        );
        app.press("Check retained review").unwrap();
        app.wait_for("No retained review").unwrap();
        app.press("Confirm").unwrap();
        app.wait_for("Confirmation rejected").unwrap();
        drop(app);

        db.execute_batch("DROP TRIGGER fail_delete").unwrap();
        let mut app = probe_with_storage(dir.path(), storage);
        app.press("Check retained review").unwrap();
        app.wait_for("No retained review").unwrap();
        app.press("Begin").unwrap();
        app.press("Stable").unwrap();
        app.wait_for("Review").unwrap();
        app.press("Confirm").unwrap();
        app.wait_for("Saved:false:58.1").unwrap();
    }
    #[test]
    fn completed_review_survives_restart_and_pause_blocks_notifications() {
        let dir = tempfile::tempdir().unwrap();
        let mut app = probe(dir.path());
        app.press("Begin").unwrap();
        app.press("Stable").unwrap();
        app.press("Pause").unwrap();
        app.press("Stable").unwrap();
        app.wait_for("The scale session has ended").unwrap();
        drop(app);
        let mut app = probe(dir.path());
        app.press("Confirm").unwrap();
        app.wait_for("Saved:false:58.1").unwrap();
        app.press("Confirm").unwrap();
        app.wait_for("Saved:true:58.1").unwrap();
    }
    #[test]
    fn confirmed_measurement_keeps_frozen_profile_and_metrics_after_settings_change() {
        let dir = tempfile::tempdir().unwrap();
        let mut app = probe(dir.path());
        app.press("Begin").unwrap();
        app.press("Stable").unwrap();
        app.press("Composition").unwrap();
        app.wait_for("Composition review").unwrap();
        app.press("Check frozen measurement").unwrap();
        app.wait_for("No matching measurement").unwrap();
        app.press("Confirm").unwrap();
        app.wait_for("Saved:false:58.1").unwrap();
        app.press("Change profile").unwrap();
        app.wait_for("Profile changed").unwrap();
        app.press("Check frozen measurement").unwrap();
        app.wait_for("Original measurement retained").unwrap();
    }
    fn database() -> Connection {
        let mut c = Connection::open_in_memory().unwrap();
        db::migrate(&mut c).unwrap();
        c
    }
    fn measurement_on_in(c: &Connection, day: Day) -> Option<Measurement> {
        match evidence_on_in(c, day) {
            MeasurementEvidence::Confirmed(measurement) => Some(measurement),
            MeasurementEvidence::Legacy | MeasurementEvidence::Rejected => None,
        }
    }
    fn draft(c: &Connection, with_impedance: bool) -> Draft {
        let profile = UserProfile {
            height_cm: 170,
            age_years: 23,
            sex: Sex::Male,
        };
        let resistance = with_impedance.then_some(506.0);
        let measurement = Measurement {
            weight_grams: 58_050,
            resistance_ohm: resistance,
            raw_impedances: if with_impedance {
                vec![506.0, 465.0]
            } else {
                vec![]
            },
            metrics: resistance.and_then(|r| {
                navi_health::bodycomp::estimate(58.05, 170.0, 23, Sex::Male, Some(r))
            }),
            profile,
            algorithm_version: navi_health::scale::ALGORITHM_VERSION.into(),
        };
        let day: Day = "2026-11-18".parse().unwrap();
        Draft {
            preview: Preview {
                session_id: "1".repeat(32),
                token: "2".repeat(32),
                day,
                measured_at_ms: 1_795_000_000_000,
                device: Device {
                    id: "local-device".into(),
                    name: "AFU-WL".into(),
                },
                measurement,
                existing_kg: weight_on(c, day).unwrap(),
            },
            revision: revision(c, day).unwrap(),
        }
    }
    fn keep(c: &Connection, draft: &Draft) {
        assert!(draft.preview.valid());
        c.execute(
            "INSERT INTO scale_drafts VALUES(?1,?2)",
            params![
                draft.preview.session_id,
                serde_json::to_string(draft).unwrap()
            ],
        )
        .unwrap();
    }
    fn confirm_draft(c: &Connection, d: &Draft, replace: bool) -> Result<Confirmed, String> {
        confirm_in(
            c,
            &d.preview.session_id,
            &d.preview.token,
            replace,
            d.preview.measured_at_ms + 1,
        )
    }
    #[test]
    fn measurement_lookup_is_read_only_and_retains_original_precision() {
        for with_impedance in [false, true] {
            let c = database();
            let d = draft(&c, with_impedance);
            keep(&c, &d);
            confirm_draft(&c, &d, false).unwrap();
            let changes = c.total_changes();
            c.pragma_update(None, "query_only", true).unwrap();
            assert!(
                evidence_on_in(&c, d.preview.day)
                    == MeasurementEvidence::Confirmed(d.preview.measurement.clone())
            );
            assert_eq!(
                measurement_on_in(&c, d.preview.day),
                Some(d.preview.measurement.clone())
            );
            assert_eq!(weight_on(&c, d.preview.day).unwrap(), Some(58.1));
            assert_eq!(c.total_changes(), changes);
        }
    }
    #[test]
    fn measurement_lookup_ignores_missing_manual_and_unconfirmed_measurements() {
        let c = database();
        let d = draft(&c, true);
        let day = d.preview.day;
        assert_eq!(measurement_on_in(&c, day), None);
        assert!(matches!(
            evidence_on_in(&c, day),
            MeasurementEvidence::Legacy
        ));
        keep(&c, &d);
        assert_eq!(measurement_on_in(&c, day), None);
        assert!(matches!(
            evidence_on_in(&c, day),
            MeasurementEvidence::Legacy
        ));
        c.execute("INSERT INTO weights VALUES(?1,58.1,1)", [day.to_string()])
            .unwrap();
        assert_eq!(measurement_on_in(&c, day), None);
        assert!(matches!(
            evidence_on_in(&c, day),
            MeasurementEvidence::Legacy
        ));
        c.execute(
            "INSERT INTO body_metrics VALUES(?1,?2,1)",
            params![
                day.to_string(),
                serde_json::to_string(d.preview.measurement.metrics.as_ref().unwrap()).unwrap()
            ],
        )
        .unwrap();
        assert_eq!(measurement_on_in(&c, day), None);
        assert!(matches!(
            evidence_on_in(&c, day),
            MeasurementEvidence::Legacy
        ));
        c.execute("DELETE FROM scale_drafts", []).unwrap();
        let d = draft(&c, true);
        keep(&c, &d);
        confirm_draft(&c, &d, true).unwrap();
        assert_eq!(measurement_on_in(&c, day.plus_days(1)), None);
        assert!(matches!(
            evidence_on_in(&c, day.plus_days(1)),
            MeasurementEvidence::Legacy
        ));
    }
    #[test]
    fn measurement_lookup_rejects_invalid_or_mismatched_provenance_without_writes() {
        for sql in [
            "DELETE FROM weights",
            "UPDATE weights SET kg=80.0",
            "DELETE FROM body_metrics",
            "UPDATE body_metrics SET body='unreadable'",
            "UPDATE body_metrics SET body=json_set(body,'$.body_fat_percent',99)",
            "UPDATE scale_measurements SET body='unreadable'",
            "UPDATE scale_measurements SET body=json_set(body,'$.preview.day','2026-11-17')",
            "UPDATE scale_measurements SET session_id='foreign-session'",
            "UPDATE scale_measurements SET body=json_set(body,'$.confirmed_at_ms',0)",
            "UPDATE scale_measurements SET body=json_set(body,'$.preview.token','invalid')",
            "UPDATE scale_measurements SET body=json_set(body,'$.preview.measured_at_ms',0)",
            "UPDATE scale_measurements SET body=json_set(body,'$.preview.measurement.profile.height_cm',0)",
            "UPDATE scale_measurements SET body=json_set(body,'$.preview.measurement.profile.age_years',0)",
            "UPDATE scale_measurements SET body=json_set(body,'$.preview.measurement.algorithm_version','unknown')",
            "UPDATE scale_measurements SET body=json_set(body,'$.preview.measurement.metrics',null)",
            "ALTER TABLE scale_measurements RENAME TO unavailable_scale_measurements",
        ] {
            let c = database();
            let d = draft(&c, true);
            keep(&c, &d);
            confirm_draft(&c, &d, false).unwrap();
            c.execute_batch(sql).unwrap();
            let changes = c.total_changes();
            c.pragma_update(None, "query_only", true).unwrap();
            assert_eq!(measurement_on_in(&c, d.preview.day), None, "{sql}");
            assert!(
                matches!(
                    evidence_on_in(&c, d.preview.day),
                    MeasurementEvidence::Rejected
                ),
                "{sql}"
            );
            assert_eq!(c.total_changes(), changes);
        }
    }
    #[test]
    fn confirmation_is_atomic_repeatable_and_keeps_original_precision() {
        let c = database();
        let d = draft(&c, true);
        keep(&c, &d);
        c.execute_batch("CREATE TRIGGER fail_metrics BEFORE INSERT ON body_metrics BEGIN SELECT RAISE(ABORT,'full disk'); END;").unwrap();
        assert!(confirm_draft(&c, &d, false).is_err());
        assert_eq!(weight_on(&c, d.preview.day).unwrap(), None);
        assert_eq!(
            c.query_row("SELECT count(*) FROM scale_measurements", [], |r| r
                .get::<_, i64>(0))
                .unwrap(),
            0
        );
        assert_eq!(
            c.query_row("SELECT count(*) FROM scale_drafts", [], |r| r
                .get::<_, i64>(0))
                .unwrap(),
            1
        );
        c.execute_batch("DROP TRIGGER fail_metrics").unwrap();
        assert!(!confirm_draft(&c, &d, false).unwrap().already_saved);
        assert!(confirm_draft(&c, &d, false).unwrap().already_saved);
        assert_eq!(weight_on(&c, d.preview.day).unwrap(), Some(58.1));
        let raw: String = c
            .query_row("SELECT body FROM scale_measurements", [], |r| r.get(0))
            .unwrap();
        let saved: Saved = serde_json::from_str(&raw).unwrap();
        assert_eq!(saved.preview.measurement.weight_grams, 58_050);
        assert_eq!(saved.preview.measurement.profile.height_cm, 170);
        assert!(validate_saved(&c).is_ok());
        assert!(
            confirm_in(
                &c,
                &d.preview.session_id,
                &"3".repeat(32),
                false,
                d.preview.measured_at_ms + 1
            )
            .is_err()
        );
    }
    #[test]
    fn temporarily_unavailable_draft_storage_is_retryable_and_preserves_review() {
        let c = database();
        let d = draft(&c, true);
        keep(&c, &d);
        c.execute_batch("ALTER TABLE scale_drafts RENAME TO unavailable_scale_drafts")
            .unwrap();
        let failure = confirm_draft(&c, &d, false).unwrap_err();
        assert_eq!(
            failure,
            "Could not save the measurement. Check device storage and try again."
        );
        assert_eq!(weight_on(&c, d.preview.day).unwrap(), None);
        c.execute_batch("ALTER TABLE unavailable_scale_drafts RENAME TO scale_drafts")
            .unwrap();
        assert!(!confirm_draft(&c, &d, false).unwrap().already_saved);
        assert_eq!(weight_on(&c, d.preview.day).unwrap(), Some(58.1));
    }

    #[test]
    fn stale_or_changed_review_never_overwrites_intervening_weight() {
        let c = database();
        let d = draft(&c, true);
        keep(&c, &d);
        c.execute(
            "INSERT INTO weights VALUES(?1,80.0,1)",
            [d.preview.day.to_string()],
        )
        .unwrap();
        assert!(confirm_draft(&c, &d, true).is_err());
        assert_eq!(weight_on(&c, d.preview.day).unwrap(), Some(80.0));
        c.execute("DELETE FROM scale_drafts", []).unwrap();
        let d = draft(&c, false);
        keep(&c, &d);
        assert!(
            confirm_draft(&c, &d, false).is_err(),
            "replacement needs explicit confirmation"
        );
        assert!(confirm_draft(&c, &d, true).is_ok());
        assert_eq!(
            c.query_row("SELECT count(*) FROM body_metrics", [], |r| r
                .get::<_, i64>(0))
                .unwrap(),
            0
        );
    }
    #[test]
    fn old_tokens_and_same_value_manual_edits_invalidate_review() {
        let c = database();
        let d = draft(&c, true);
        keep(&c, &d);
        assert!(
            confirm_in(
                &c,
                &d.preview.session_id,
                &"3".repeat(32),
                false,
                d.preview.measured_at_ms + 1
            )
            .is_err()
        );
        c.execute(
            "INSERT INTO weights VALUES(?1,58.1,1)",
            [d.preview.day.to_string()],
        )
        .unwrap();
        c.execute("DELETE FROM scale_drafts", []).unwrap();
        let d = draft(&c, true);
        keep(&c, &d);
        c.execute(
            "UPDATE weights SET kg=58.1 WHERE day=?1",
            [d.preview.day.to_string()],
        )
        .unwrap();
        assert!(
            confirm_draft(&c, &d, true).is_err(),
            "revision catches even same-value edits"
        );
    }
    #[test]
    fn backup_validation_rejects_stale_or_tampered_provenance() {
        let c = database();
        let d = draft(&c, true);
        keep(&c, &d);
        confirm_draft(&c, &d, false).unwrap();
        c.execute("UPDATE weights SET kg=80.0", []).unwrap();
        assert!(validate_saved(&c).is_err());
        reconcile_weight_in_transaction(&c, &d.preview.day.to_string(), Some(81.0)).unwrap();
        assert_eq!(
            c.query_row("SELECT count(*) FROM body_metrics", [], |r| r
                .get::<_, i64>(0))
                .unwrap(),
            0
        );
        assert!(validate_saved(&c).is_ok());
    }
}
