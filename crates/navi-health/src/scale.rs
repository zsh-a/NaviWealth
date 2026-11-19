//! AFU-WL/Welland foreground measurement protocol, independently implemented
//! from observed wire fields. No I/O, timers, Android or storage lives here.
//!
//! Wire evidence and the two attributed packet fixtures:
//! <https://github.com/Mzdyl/ant-afu-welland-scale> (`protocol.py`,
//! `advertising.py`, `tests/test_protocol_and_bodycomp.py`). Only the live
//! weight/ADC packets and the profile/time command are supported. History and
//! multi-part signing/settings packets never become measurements.

use crate::bodycomp::{self, BodyMetrics, Sex};
use serde::{Deserialize, Serialize};
use thiserror::Error;

pub const SERVICE_UUID: &str = "0000ffb0-0000-1000-8000-00805f9b34fb";
pub const WRITE_UUID: &str = "0000ffb1-0000-1000-8000-00805f9b34fb";
pub const NOTIFY_UUID: &str = "0000ffb2-0000-1000-8000-00805f9b34fb";
pub const ALGORITHM_VERSION: &str = "afu_wl_scale27_bia_v1";
const MIN_GRAMS: u32 = 20_000;
const MAX_GRAMS: u32 = 0x3ffff;
const MAX_ADC: usize = 5;

/// A snapshot of the owner's explicitly entered estimating inputs.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct UserProfile {
    pub height_cm: u16,
    pub age_years: u16,
    pub sex: Sex,
}
impl UserProfile {
    pub fn valid(&self) -> bool {
        (80..=230).contains(&self.height_cm) && (5..=120).contains(&self.age_years)
    }
}

/// An immutable candidate; the host binds it to a session and confirms it.
/// Original grams are retained even when the UI rounds weight to one decimal.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Measurement {
    pub weight_grams: u32,
    pub resistance_ohm: Option<f64>,
    pub raw_impedances: Vec<f64>,
    pub metrics: Option<BodyMetrics>,
    pub profile: UserProfile,
    pub algorithm_version: String,
}
impl Measurement {
    pub fn weight_kg(&self) -> f64 {
        f64::from(self.weight_grams) / 1000.0
    }

    pub fn summary(&self) -> MeasurementSummary {
        let estimated_mass = |percent: f64| rounded_2(self.weight_kg() * percent / 100.0);
        MeasurementSummary {
            bmi: bodycomp::bmi(self.weight_kg(), self.profile.height_cm),
            fat_mass_kg: self
                .metrics
                .as_ref()
                .map(|value| estimated_mass(value.body_fat_percent)),
            fat_free_mass_kg: self
                .metrics
                .as_ref()
                .map(|value| estimated_mass(100.0 - value.body_fat_percent)),
            muscle_mass_kg: self
                .metrics
                .as_ref()
                .map(|value| estimated_mass(value.muscle_percent)),
            water_mass_kg: self
                .metrics
                .as_ref()
                .map(|value| estimated_mass(value.water_percent)),
        }
    }
    /// Checks provenance and recomputes derived values, including after restore.
    pub fn valid(&self) -> bool {
        self.profile.valid()
            && valid_grams(self.weight_grams)
            && self.algorithm_version == ALGORITHM_VERSION
            && self.raw_impedances.len() <= MAX_ADC
            && self.raw_impedances.iter().all(|v| {
                v.is_finite() && (0.0..=f64::from(u16::MAX)).contains(v) && v.fract() == 0.0
            })
            && *self
                == measurement(
                    self.weight_grams,
                    self.raw_impedances.clone(),
                    &self.profile,
                )
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MeasurementSummary {
    pub bmi: Option<f64>,
    pub fat_mass_kg: Option<f64>,
    pub fat_free_mass_kg: Option<f64>,
    pub muscle_mass_kg: Option<f64>,
    pub water_mass_kg: Option<f64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Error)]
pub enum ScaleError {
    #[error("The body profile is incomplete or invalid")]
    Profile,
    #[error("The scale packet has an invalid length")]
    Length,
    #[error("The scale packet is not a supported connected measurement")]
    Packet,
    #[error("The scale packet checksum is invalid")]
    Checksum,
    #[error("The scale weight is outside the supported range")]
    Weight,
    #[error("The impedance does not belong to the current stable weight")]
    StaleMeasurement,
    #[error("The device advertisement does not identify a supported scale")]
    Advertisement,
    #[error("The scale initialization parameters are invalid")]
    Initialization,
}

/// Verified scan metadata used for a profile write, never inferred from a name.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DeviceProtocol {
    pub device_type: u8,
    pub protocol_ver: u8,
}

/// Manufacturer bytes exclude the company identifier on Android. Reconstruct
/// that two-byte little-endian prefix before inspecting the device flags.
/// Services alone do not identify a protocol; many scales omit them in ads.
pub fn identify_advertisement(
    manufacturer_data: &[(u16, Vec<u8>)],
    name: &str,
    services: &[String],
) -> Result<DeviceProtocol, ScaleError> {
    identify_advertisement_with_service_data(manufacturer_data, name, services, &[])
}

/// Some Android advertisements expose the same AC-prefixed identification
/// in 16-bit service data. The UUID supplies its little-endian two-byte prefix.
/// Unsupported service-data encodings are not filled with guessed defaults.
pub fn identify_advertisement_with_service_data(
    manufacturer_data: &[(u16, Vec<u8>)],
    name: &str,
    _services: &[String],
    service_data: &[(String, Vec<u8>)],
) -> Result<DeviceProtocol, ScaleError> {
    if !name.starts_with("AFU-WL") || manufacturer_data.len() > 32 || service_data.len() > 32 {
        return Err(ScaleError::Advertisement);
    }
    let candidates = manufacturer_data
        .iter()
        .map(|(company, payload)| (*company, payload.as_slice()))
        .chain(service_data.iter().filter_map(|(uuid, payload)| {
            service_uuid16(uuid).map(|company| (company, payload.as_slice()))
        }));
    let mut found: Option<DeviceProtocol> = None;
    for (company, payload) in candidates {
        if payload.len() > 254 {
            continue;
        }
        let prefix = company.to_le_bytes();
        if prefix[0] != 0xac || prefix[1] != 0x27 || payload.len() < 7 {
            continue;
        }
        let candidate = DeviceProtocol {
            device_type: prefix[1],
            protocol_ver: payload[6],
        };
        if found.as_ref().is_some_and(|old| old != &candidate) {
            return Err(ScaleError::Advertisement);
        }
        found = Some(candidate);
    }
    found.ok_or(ScaleError::Advertisement)
}

fn service_uuid16(uuid: &str) -> Option<u16> {
    if uuid.len() != 4 && uuid.len() != 36 {
        return None;
    }
    let normalized = uuid.to_ascii_lowercase();
    let short = if normalized.len() == 4 {
        normalized.as_str()
    } else if normalized.len() == 36
        && normalized.starts_with("0000")
        && normalized.ends_with("-0000-1000-8000-00805f9b34fb")
    {
        normalized.get(4..8)?
    } else {
        return None;
    };
    u16::from_str_radix(short, 16).ok()
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum Event {
    Weight {
        weight_grams: u32,
        stable: bool,
    },
    Impedance {
        weight_grams: u32,
        raw_impedances: Vec<f64>,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LiveReading {
    pub weight_grams: u32,
    pub stable: bool,
}

/// Each measurement notification is one independently checksummed 20-byte
/// frame. A shortened ATT value is rejected, never glued to a later reading.
/// Unknown/history/settings frames are ignored and cannot produce drafts.
#[derive(Debug, Default)]
pub struct Protocol;
impl Protocol {
    pub fn reset(&mut self) {}
    pub fn feed(&mut self, data: &[u8]) -> Result<Option<Event>, ScaleError> {
        if data.len() != 20 {
            return Err(ScaleError::Length);
        }
        if data[0] != 0xac || !(0x20..=0x2f).contains(&data[1]) {
            return Err(ScaleError::Packet);
        }
        let sum = data[2..19].iter().fold(0u8, |sum, n| sum.wrapping_add(*n)) & 0x1f;
        if sum != data[19] & 0x1f {
            return Err(ScaleError::Checksum);
        }
        let payload = &data[2..18];
        match data[18] {
            0xd5 => {
                let encoded = u32::from_be_bytes(payload[..4].try_into().unwrap());
                let weight_grams = encoded & 0x3ffff;
                let stable = encoded & 0x8000_0000 != 0;
                if stable && !valid_grams(weight_grams) {
                    return Err(ScaleError::Weight);
                }
                Ok(Some(Event::Weight {
                    weight_grams,
                    stable,
                }))
            }
            0xd6 => {
                let count = usize::from(payload[0]);
                let end = 2 + count * 2;
                if count == 0 || count > MAX_ADC || end + 5 > payload.len() {
                    return Err(ScaleError::Packet);
                }
                // This initial live format includes its own weight (mode 1).
                // Other modes are not joined against a remembered old value.
                if payload[end] != 1 {
                    return Err(ScaleError::Packet);
                }
                let encoded = u32::from_be_bytes(payload[end + 1..end + 5].try_into().unwrap());
                let weight_grams = encoded & 0x3ffff;
                if encoded & 0x8000_0000 == 0 {
                    return Err(ScaleError::StaleMeasurement);
                }
                if !valid_grams(weight_grams) {
                    return Err(ScaleError::Weight);
                }
                let raw_impedances = payload[2..end]
                    .as_chunks::<2>()
                    .0
                    .iter()
                    .map(|b| f64::from(u16::from_be_bytes([b[0], b[1]])))
                    .collect();
                Ok(Some(Event::Impedance {
                    weight_grams,
                    raw_impedances,
                }))
            }
            _ => Ok(None),
        }
    }
}

/// A single connection/measurement attempt. The host must reset or discard it
/// when disconnected/cancelled; session identifiers belong to the host.
#[derive(Debug)]
pub struct Session {
    profile: UserProfile,
    protocol: Protocol,
    latest: Option<Measurement>,
    live_reading: Option<LiveReading>,
}
impl Session {
    pub fn new(profile: UserProfile) -> Result<Self, ScaleError> {
        if !profile.valid() {
            return Err(ScaleError::Profile);
        }
        Ok(Self {
            profile,
            protocol: Protocol,
            latest: None,
            live_reading: None,
        })
    }
    pub fn reset(&mut self) {
        self.protocol.reset();
        self.latest = None;
        self.live_reading = None;
    }
    pub fn latest(&self) -> Option<Measurement> {
        self.latest.clone()
    }
    pub fn live_reading(&self) -> Option<LiveReading> {
        self.live_reading.clone()
    }
    pub fn feed(&mut self, data: &[u8]) -> Result<Option<Measurement>, ScaleError> {
        let event = match self.protocol.feed(data) {
            Ok(event) => event,
            Err(error) => {
                self.reset();
                return Err(error);
            }
        };
        if let Some(Event::Weight {
            weight_grams,
            stable,
        }) = &event
        {
            self.live_reading = Some(LiveReading {
                weight_grams: *weight_grams,
                stable: *stable,
            });
        }
        let candidate = match event {
            Some(Event::Weight { stable: false, .. }) => {
                self.latest = None;
                return Ok(None);
            }
            Some(Event::Weight {
                weight_grams,
                stable: true,
            }) => {
                if self
                    .latest
                    .as_ref()
                    .is_some_and(|m| m.weight_grams == weight_grams)
                {
                    return Ok(None);
                }
                measurement(weight_grams, Vec::new(), &self.profile)
            }
            Some(Event::Impedance {
                weight_grams,
                raw_impedances,
            }) => {
                if self
                    .latest
                    .as_ref()
                    .is_none_or(|m| m.weight_grams != weight_grams)
                {
                    self.reset();
                    return Err(ScaleError::StaleMeasurement);
                }
                let candidate = measurement(weight_grams, raw_impedances, &self.profile);
                if candidate.metrics.is_none()
                    && self.latest.as_ref().is_some_and(|m| m.metrics.is_some())
                {
                    return Ok(None);
                }
                candidate
            }
            None => return Ok(None),
        };
        if self.latest.as_ref() == Some(&candidate) {
            return Ok(None);
        }
        self.latest = Some(candidate.clone());
        Ok(Some(candidate))
    }
}

fn valid_grams(grams: u32) -> bool {
    (MIN_GRAMS..=MAX_GRAMS).contains(&grams)
}
fn rounded_2(value: f64) -> f64 {
    (value * 100.0).round() / 100.0
}

fn measurement(weight_grams: u32, raw_impedances: Vec<f64>, profile: &UserProfile) -> Measurement {
    let weight_kg = f64::from(weight_grams) / 1000.0;
    // The five-electrode variant puts its whole-body channel last. Other
    // variants use the first ADC, converted only when it is an ADC-scale value.
    let resistance_ohm = if raw_impedances.len() == 5 {
        raw_impedances.last().copied()
    } else {
        raw_impedances.first().map(|raw| {
            if *raw >= 1500.0 {
                rounded_2((*raw - 1000.0 - weight_kg * 4.0) / 6.0)
            } else {
                *raw
            }
        })
    }
    .filter(|r| {
        r.is_finite() && (bodycomp::MIN_RESISTANCE_OHM..=bodycomp::MAX_RESISTANCE_OHM).contains(r)
    });
    let metrics = resistance_ohm.and_then(|r| {
        bodycomp::estimate(
            weight_kg,
            f64::from(profile.height_cm),
            profile.age_years,
            profile.sex,
            Some(r),
        )
    });
    Measurement {
        weight_grams,
        resistance_ohm,
        raw_impedances,
        metrics,
        profile: profile.clone(),
        algorithm_version: ALGORITHM_VERSION.into(),
    }
}

/// One profile/time command for the connected AFU-WL subtype verified by its
/// advertisement. Caller supplies time and timezone; this function owns no clock.
/// kg, user slot 1, no target/profile weight, BIA enabled. No unknown handshake.
pub fn encode_profile(
    profile: &UserProfile,
    unix_seconds: u32,
    utc_offset_quarters: i8,
    device_type: u8,
    protocol_ver: u8,
) -> Result<Vec<u8>, ScaleError> {
    if !profile.valid() {
        return Err(ScaleError::Profile);
    }
    // The reference names revisions 1/2 and its legacy revision 0. Their
    // layout is identical for the normal (non-athlete) profile we support.
    // An observed zero revision is accepted; absence of metadata is not.
    if device_type != 0x27 || protocol_ver > 2 || !(-48..=56).contains(&utc_offset_quarters) {
        return Err(ScaleError::Initialization);
    }
    let mut packet = vec![0; 20];
    packet[0] = 0xac;
    packet[1] = device_type;
    packet[2..6].copy_from_slice(&unix_seconds.to_be_bytes());
    packet[6] = utc_offset_quarters as u8;
    packet[7] = 0; // kilograms
    packet[8] = 1; // user slot
    packet[9] = profile.height_cm as u8;
    packet[12] = profile.age_years as u8;
    packet[13] = match profile.sex {
        Sex::Male => 1,
        Sex::Female => 2,
    };
    packet[16] = 3; // enable impedance and measurement
    packet[18] = 0xd0;
    packet[19] = packet[2..19]
        .iter()
        .fold(0u8, |sum, n| sum.wrapping_add(*n));
    Ok(packet)
}

/// Initial GATT writes after notification subscription succeeds. The
/// AFU-WL-TZ-A1 capture uses the DF/08 time command, not the D0 user profile.
pub fn encode_initialization(
    profile: &UserProfile,
    unix_seconds: u32,
    utc_offset_quarters: i8,
    identity: &DeviceProtocol,
    model_name: &str,
) -> Result<Vec<Vec<u8>>, ScaleError> {
    if model_name == "AFU-WL-TZ-A1" {
        if !profile.valid() {
            return Err(ScaleError::Profile);
        }
        if identity.device_type != 0x27 || identity.protocol_ver > 2 {
            return Err(ScaleError::Initialization);
        }
        let mut packet = vec![0; 20];
        packet[..3].copy_from_slice(&[0xac, identity.device_type, 0x08]);
        packet[3..7].copy_from_slice(&unix_seconds.to_be_bytes());
        packet[7] = 0x20;
        packet[18] = 0xdf;
        packet[19] = packet[2..19].iter().copied().fold(0u8, u8::wrapping_add);
        return Ok(vec![packet]);
    }
    encode_profile(
        profile,
        unix_seconds,
        utc_offset_quarters,
        identity.device_type,
        identity.protocol_ver,
    )
    .map(|p| vec![p])
}

#[cfg(test)]
mod tests;
