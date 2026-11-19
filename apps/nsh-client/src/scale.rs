//! Typed boundary between the mixed TSX entry and the existing Rust app.
use crate::{
    domain::recognition::Lang,
    i18n::s,
    ui::{Btn, Variant},
};
use base64::{Engine, engine::general_purpose::STANDARD};
use navi_health::scale as protocol;
use nsh_core::prelude::*;
use serde_json::{Value, json};
use std::rc::Rc;

#[derive(Clone)]
struct Launcher {
    open: Rc<dyn Fn()>,
}

pub fn provide_launcher(enabled: bool, open: impl Fn() + 'static) {
    if enabled {
        provide_context(Launcher {
            open: Rc::new(open),
        });
    }
}

pub(crate) fn launch_label() -> &'static str {
    if s().lang == Lang::Zh {
        "连接体脂秤"
    } else {
        "Connect scale"
    }
}

pub(crate) fn launch_action() -> Option<impl Fn() + 'static> {
    let launcher = use_context::<Launcher>()?;
    Some(move || (launcher.open)())
}

pub fn launch_button(before: impl Fn() + 'static) -> Option<AnyElement> {
    let open = launch_action()?;
    Some(
        Btn::new(Variant::Tonal)
            .label(|| launch_label().into())
            .on_press(move || {
                before();
                open();
            })
            .into_element(),
    )
}

/// Local scale measurement operations. Android hardware is supplied by the host.
#[module]
pub struct Scale;

#[module]
impl Scale {
    /// Available local models and the preference for the next measurement.
    pub fn algorithms(_cx: &mut ModuleCx) -> Value {
        use navi_health::bodycomp::Algorithm;
        json!({
            "selected": crate::data::settings::scale_algorithm().id(),
            "options": Algorithm::ALL.into_iter().map(algorithm_option).collect::<Vec<_>>(),
        })
    }

    /// Keep the default model for future sessions without altering any draft.
    pub fn set_algorithm(algorithm_id: String, _cx: &mut ModuleCx) -> Result<(), String> {
        let algorithm =
            navi_health::bodycomp::Algorithm::from_id(&algorithm_id).ok_or("unknown_algorithm")?;
        crate::data::settings::save_scale_algorithm(algorithm)
            .map_err(|_| "storage_unavailable".into())
    }

    /// Recalculate only an exact unsaved review, using its original evidence.
    pub fn reestimate(
        session_id: String,
        token: String,
        algorithm_id: String,
        _cx: &mut ModuleCx,
    ) -> Result<Value, String> {
        let algorithm =
            navi_health::bodycomp::Algorithm::from_id(&algorithm_id).ok_or("unknown_algorithm")?;
        let preview = crate::data::scale::reestimate(&session_id, &token, algorithm)?;
        Ok(display_preview(&preview))
    }
    /// UI language; no credentials or profile leave this local bridge.
    pub fn language(_cx: &mut ModuleCx) -> String {
        if s().lang == Lang::Zh { "zh" } else { "en" }.into()
    }

    /// Shared Ink and Daylight tokens for the TSX surface.
    pub fn palette(dark: bool) -> Value {
        use crate::ui::color;
        let hex = |role: nsh_core::element::AdaptiveColor| {
            let color = if dark { role.dark } else { role.light };
            format!("#{:08X}", u32::from(color.to_rgb()))
        };
        json!({"canvas":hex(color::CANVAS),"surface":hex(color::SURFACE),
            "ink":hex(color::INK),"muted":hex(color::MUTED),"line":hex(color::LINE),
            "well":hex(color::SUNKEN),"danger":hex(color::DANGER),
            "onAction":hex(color::ON_ACTION),"positive":hex(color::POSITIVE),"scrim":hex(color::SCRIM.opacity(0.32))})
    }

    /// Whether the explicit body profile is ready for a measurement.
    pub fn profile_ready(_cx: &mut ModuleCx) -> bool {
        let Some(profile) = profile() else {
            return false;
        };
        profile.valid()
    }

    /// Returns to the existing body-profile editor.
    pub fn open_profile(_cx: &mut ModuleCx) {
        crate::pages::open_body_profile();
    }

    /// Verify scan evidence and begin one Rust-owned measurement attempt.
    pub fn begin(device: Value, _cx: &mut ModuleCx) -> Result<Value, String> {
        let address = device["address"].as_str().ok_or("invalid_device")?;
        let name = device["name"].as_str().ok_or("invalid_device")?;
        if address.is_empty() || address.len() > 128 || name.len() > 128 {
            return Err("invalid_device".into());
        }
        let manufacturers = manufacturer_data(&device["manufacturerData"])?;
        let services: Vec<String> = device["serviceUuids"]
            .as_array()
            .ok_or("invalid_device")?
            .iter()
            .map(|s| {
                s.as_str()
                    .filter(|s| s.len() <= 64)
                    .map(str::to_owned)
                    .ok_or("invalid_device".to_owned())
            })
            .collect::<Result<_, _>>()?;
        if services.len() > 32 {
            return Err("invalid_device".into());
        }
        let service_data = service_data(&device["serviceData"])?;
        let identity = protocol::identify_advertisement_with_service_data(
            &manufacturers,
            name,
            &services,
            &service_data,
        )
        .map_err(|_| "unsupported_scale".to_owned())?;
        begin_session(
            crate::data::scale::Device {
                id: address.into(),
                name: name.into(),
            },
            identity,
        )
    }

    /// Display the scale saved in local preferences without starting a connection.
    pub fn remembered(_cx: &mut ModuleCx) -> Value {
        json!(crate::data::scale::remembered().map(|saved| saved.device))
    }

    /// Start a new attempt using the last successfully initialized scale.
    pub fn begin_remembered(_cx: &mut ModuleCx) -> Result<Value, String> {
        let saved = crate::data::scale::remembered().ok_or("no_saved_scale")?;
        begin_session(saved.device, saved.identity)
    }

    /// Remember the active scale after the host acknowledges initialization.
    pub fn remember(session_id: String, _cx: &mut ModuleCx) -> Value {
        json!(crate::data::scale::remember(&session_id))
    }

    /// Decode one native notification; only Rust may produce a save token.
    pub fn feed(
        session_id: String,
        data_base64: String,
        _cx: &mut ModuleCx,
    ) -> Result<Value, String> {
        if data_base64.len() > 256 {
            let _ = crate::data::scale::invalidate(&session_id);
            return Err("invalid_packet".into());
        }
        let bytes = match STANDARD.decode(data_base64) {
            Ok(bytes) => bytes,
            Err(_) => {
                let _ = crate::data::scale::invalidate(&session_id);
                return Err("invalid_packet".into());
            }
        };
        let preview = crate::data::scale::feed(&session_id, &bytes)?;
        Ok(json!({
            "preview": preview.as_ref().map(display_preview),
            "reading": crate::data::scale::live_reading(&session_id),
        }))
    }

    /// Reopen a locally kept measurement; a connection is never restored automatically.
    pub fn pending(_cx: &mut ModuleCx) -> Result<Value, String> {
        Ok(json!(
            crate::data::scale::pending()?.as_ref().map(display_preview)
        ))
    }

    /// Atomically confirm the exact reviewed Rust draft once.
    pub fn confirm(
        session_id: String,
        token: String,
        replace_existing: bool,
        _cx: &mut ModuleCx,
    ) -> Result<Value, String> {
        serde_json::to_value(
            crate::data::scale::confirm(&session_id, &token, replace_existing).map_err(
                |error| match error.as_str() {
                    "Local data unavailable"
                    | "Could not save the measurement. Check device storage and try again." => {
                        "storage_unavailable".to_owned()
                    }
                    _ => "stale_measurement".to_owned(),
                },
            )?,
        )
        .map_err(|_| "invalid_confirmation".into())
    }

    /// Stop accepting notifications while retaining a completed local draft.
    pub fn pause(session_id: String, _cx: &mut ModuleCx) -> Result<(), String> {
        crate::data::scale::pause(&session_id)
    }

    /// Discard this measurement attempt without changing any confirmed records.
    pub fn cancel(session_id: String, _cx: &mut ModuleCx) -> Result<(), String> {
        crate::data::scale::cancel(&session_id)
    }

    /// Retire invalid evidence even if SQLite cannot delete the draft.
    pub fn invalidate(session_id: String, _cx: &mut ModuleCx) -> Result<(), String> {
        crate::data::scale::invalidate(&session_id)
    }
}

fn begin_session(
    device: crate::data::scale::Device,
    identity: protocol::DeviceProtocol,
) -> Result<Value, String> {
    let timestamp = jiff::Timestamp::now();
    let seconds = u32::try_from(timestamp.as_second()).map_err(|_| "invalid_time")?;
    let offset = timestamp
        .to_zoned(jiff::tz::TimeZone::system())
        .offset()
        .seconds();
    if offset % 900 != 0 {
        return Err("invalid_timezone".into());
    }
    let quarters = i8::try_from(offset / 900).map_err(|_| "invalid_timezone")?;
    let commands = protocol::encode_initialization(
        &profile().ok_or("incomplete_profile")?,
        seconds,
        quarters,
        &identity,
        &device.name,
    )
    .map_err(|_| "unsupported_scale".to_owned())?;
    let address = device.id.clone();
    let start = crate::data::scale::begin(device, identity)?;
    let mut result = serde_json::to_value(start).map_err(|_| "invalid_session")?;
    result["address"] = json!(address);
    result["commands"] = json!(
        commands
            .into_iter()
            .map(|b| STANDARD.encode(b))
            .collect::<Vec<_>>()
    );
    Ok(result)
}

fn display_preview(preview: &crate::data::scale::Preview) -> Value {
    json!({
        "session_id": preview.session_id,
        "token": preview.token,
        "day": preview.day,
        "measured_at_ms": preview.measured_at_ms,
        "device": preview.device,
        "measurement": preview.measurement,
        "existing_kg": preview.existing_kg,
        "summary": preview.measurement.summary(),
        "algorithm": algorithm_option(preview.measurement.algorithm().expect("validated measurement has an algorithm")),
        "algorithm_unavailable": preview.measurement.resistance_ohm.is_some() && preview.measurement.metrics.is_none(),
    })
}

pub(crate) fn algorithm_name(algorithm: navi_health::bodycomp::Algorithm) -> &'static str {
    match algorithm {
        navi_health::bodycomp::Algorithm::Segal => "Segal BIA",
        navi_health::bodycomp::Algorithm::Wu2015 => "Wu 2015",
        navi_health::bodycomp::Algorithm::Sun2003 => "Sun 2003",
    }
}

pub(crate) fn algorithm_description(algorithm: navi_health::bodycomp::Algorithm) -> &'static str {
    match algorithm {
        navi_health::bodycomp::Algorithm::Segal => s().algorithm_segal_note,
        navi_health::bodycomp::Algorithm::Wu2015 => s().algorithm_wu_note,
        navi_health::bodycomp::Algorithm::Sun2003 => s().algorithm_sun_note,
    }
}

fn algorithm_option(algorithm: navi_health::bodycomp::Algorithm) -> Value {
    json!({"id":algorithm.id(),"name":algorithm_name(algorithm),
        "description":algorithm_description(algorithm),"experimental":algorithm.experimental()})
}

fn profile() -> Option<protocol::UserProfile> {
    use crate::data::settings;
    Some(protocol::UserProfile {
        height_cm: settings::height_cm()?,
        age_years: settings::age_years()?,
        sex: settings::sex()?,
    })
}

fn manufacturer_data(value: &Value) -> Result<Vec<(u16, Vec<u8>)>, String> {
    let map = value.as_object().ok_or("invalid_device")?;
    if map.len() > 32 {
        return Err("invalid_device".into());
    }
    map.iter()
        .map(|(id, bytes)| {
            let id = id.parse::<u16>().map_err(|_| "invalid_device")?;
            let bytes = decode_advertisement(bytes)?;
            Ok((id, bytes))
        })
        .collect()
}
fn service_data(value: &Value) -> Result<Vec<(String, Vec<u8>)>, String> {
    let Some(map) = value.as_object() else {
        return if value.is_null() {
            Ok(vec![])
        } else {
            Err("invalid_device".into())
        };
    };
    if map.len() > 32 {
        return Err("invalid_device".into());
    }
    map.iter()
        .map(|(uuid, bytes)| {
            if uuid.len() > 64 {
                return Err("invalid_device".into());
            }
            Ok((uuid.clone(), decode_advertisement(bytes)?))
        })
        .collect()
}
fn decode_advertisement(value: &Value) -> Result<Vec<u8>, String> {
    let value = value
        .as_str()
        .filter(|s| s.len() <= 344)
        .ok_or("invalid_device")?;
    let bytes = STANDARD.decode(value).map_err(|_| "invalid_device")?;
    if bytes.len() > 254 {
        return Err("invalid_device".into());
    }
    Ok(bytes)
}
