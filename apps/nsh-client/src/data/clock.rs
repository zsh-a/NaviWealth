//! Local time: the device's time zone as the platform names it, the
//! current calendar day (advancing at midnight), and times as people read
//! them.

use jiff::{
    Timestamp, Zoned,
    tz::{Offset, TimeZone},
};
use nsh_core::prelude::*;

use crate::domain::meal::Day;

/// The time zone named `name`: an IANA zone, or an offset zone such as
/// Android's `GMT+08:00`; else the system's, else UTC.
pub fn parse_zone(name: &str) -> TimeZone {
    if let Ok(zone) = TimeZone::get(name) {
        return zone;
    }
    if let Some(offset) = parse_offset(name) {
        return TimeZone::fixed(offset);
    }
    TimeZone::try_system().unwrap_or(TimeZone::UTC)
}

/// `GMT+08:00`, `UTC-5`, `GMT+0530` as an offset.
fn parse_offset(name: &str) -> Option<Offset> {
    let rest = name
        .strip_prefix("GMT")
        .or_else(|| name.strip_prefix("UTC"))?;
    if rest.is_empty() {
        return Some(Offset::UTC);
    }
    let (sign, digits) = match rest.as_bytes().first()? {
        b'+' => (1, &rest[1..]),
        b'-' => (-1, &rest[1..]),
        _ => return None,
    };
    let digits: String = digits.chars().filter(char::is_ascii_digit).collect();
    let (hours, minutes) = match digits.len() {
        1 | 2 => (digits.parse::<i32>().ok()?, 0),
        3 | 4 => {
            let split = digits.len() - 2;
            (digits[..split].parse().ok()?, digits[split..].parse().ok()?)
        }
        _ => return None,
    };
    if hours > 14 || minutes > 59 {
        return None;
    }
    Offset::from_seconds(sign * (hours * 3600 + minutes * 60)).ok()
}

/// The device's zone (tracked where it is read).
pub fn zone() -> TimeZone {
    parse_zone(locale_settings().time_zone.as_str())
}

/// Now, in Unix milliseconds (the engine's clock: manual in tests).
pub fn now_ms() -> i64 {
    nsh_core::time::unix_ms() as i64
}

/// `ms` in the device's zone.
pub fn zoned(ms: i64) -> Zoned {
    Timestamp::from_millisecond(ms)
        .unwrap_or(Timestamp::UNIX_EPOCH)
        .to_zoned(zone())
}

/// The local day of `ms`.
pub fn day_of(ms: i64) -> Day {
    Day(zoned(ms).date())
}

/// The local hour and minute of `ms`.
pub fn hour_minute(ms: i64) -> (u8, u8) {
    let time = zoned(ms);
    (time.hour() as u8, time.minute() as u8)
}

/// `ms` as a time of day: `12:40`, or `12:40 PM` where 12-hour time is
/// the user's setting.
pub fn time_label(ms: i64) -> String {
    let (hour, minute) = hour_minute(ms);
    format_time(hour, minute, locale_settings().hour_cycle.twelve_hour())
}

/// A time of day in 24- or 12-hour form.
pub fn format_time(hour: u8, minute: u8, twelve_hour: bool) -> String {
    if twelve_hour {
        let suffix = if hour < 12 { "AM" } else { "PM" };
        let hour = match hour % 12 {
            0 => 12,
            h => h,
        };
        format!("{hour}:{minute:02} {suffix}")
    } else {
        format!("{hour:02}:{minute:02}")
    }
}

#[derive(Clone, Copy, PartialEq)]
struct CurrentDay(Day);

impl Default for CurrentDay {
    fn default() -> Self {
        CurrentDay(day_of(now_ms()))
    }
}

/// Today in the device's zone (tracked where it is read).
pub fn today() -> Day {
    global::<CurrentDay>().get().0
}

/// Moves [`today`] on when midnight passed; the root calls it every minute
/// and on resume.
pub fn tick() {
    global::<CurrentDay>().set(CurrentDay(day_of(now_ms())));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn offset_zones_parse() {
        assert_eq!(
            parse_offset("GMT+08:00"),
            Offset::from_seconds(8 * 3600).ok()
        );
        assert_eq!(parse_offset("UTC-5"), Offset::from_seconds(-5 * 3600).ok());
        assert_eq!(parse_offset("GMT+0530"), Offset::from_seconds(19800).ok());
        assert_eq!(parse_offset("GMT"), Some(Offset::UTC));
        assert_eq!(parse_offset("GMT+25"), None);
        assert_eq!(parse_offset("Asia/Shanghai"), None);
    }

    #[test]
    fn named_zones_resolve() {
        let zone = parse_zone("Asia/Shanghai");
        let noon_utc = Timestamp::from_second(1_762_948_800).unwrap(); // 2025-11-12 12:00 UTC
        assert_eq!(noon_utc.to_zoned(zone).hour(), 20);
        let fixed = parse_zone("GMT+08:00");
        assert_eq!(noon_utc.to_zoned(fixed).hour(), 20);
    }

    #[test]
    fn times_read_in_both_cycles() {
        assert_eq!(format_time(9, 5, false), "09:05");
        assert_eq!(format_time(0, 30, true), "12:30 AM");
        assert_eq!(format_time(13, 0, true), "1:00 PM");
    }
}
