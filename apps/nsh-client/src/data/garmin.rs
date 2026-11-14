//! Garmin daily data through the official Personal API: the user's own
//! key, read-only, pulled when the app starts or comes back (at most every
//! 30 minutes unless asked). Imported days are kept in the database and
//! stay visible when an update fails. The key stays in app-private storage
//! under its own entry; the 24-hour token only in memory.

use std::collections::BTreeMap;

use health_core::garmin::{self, GarminDay, Region};
use nsh_core::{platform::HttpRequest, prelude::*, storage::Storage};
use rusqlite::{Connection, params};
use serde::{Deserialize, Serialize};

use super::{clock, db};
use crate::domain::meal::Day;

const KEY_SECRET: &str = "secret.garmin-key.v1";
const KEY_LINK: &str = "garmin.v1";
/// How often a foreground pull may run on its own.
const FRESH_MS: i64 = 30 * 60 * 1000;
/// Days pulled the first time.
const FIRST_DAYS: i32 = 30;
/// A token is renewed this long before Garmin's 24 hours run out.
const TOKEN_MS: i64 = 23 * 60 * 60 * 1000;

/// Why Garmin gave nothing.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Failure {
    /// The key does not exist (in either region), expired or was revoked.
    KeyRejected,
    /// The request did not complete.
    Network,
    /// Garmin answered something unreadable or an error.
    Unreadable,
}

/// Where the last pull is.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum SyncState {
    #[default]
    Idle,
    Syncing,
    Failed(Failure),
}

/// What is kept about the connection (not the key).
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
struct Link {
    region: Option<Region>,
    last_sync_ms: Option<i64>,
}

#[derive(Clone, Default, PartialEq)]
struct State {
    generation: u64,
    link: Link,
    key: String,
    token: Option<(String, i64)>,
    sync: SyncState,
    days: BTreeMap<Day, GarminDay>,
}

fn state() -> Signal<State> {
    global::<State>()
}

/// Reads the connection and the kept days; the root calls it once.
pub fn load() {
    let generation = state().with_untracked(|s| s.generation.wrapping_add(1));
    let link: Link = Storage::get_item(KEY_LINK)
        .and_then(|raw| serde_json::from_str(&raw).ok())
        .unwrap_or_default();
    let key = Storage::get_item(KEY_SECRET).unwrap_or_default();
    let days = db::with(|c| {
        read_days(c).unwrap_or_else(|error| {
            log::error!("garmin: cannot read the database: {error}");
            BTreeMap::new()
        })
    })
    .unwrap_or_default();
    state().set(State {
        generation,
        link,
        key,
        days,
        ..State::default()
    });
}

fn read_days(connection: &Connection) -> rusqlite::Result<BTreeMap<Day, GarminDay>> {
    let mut statement = connection.prepare("SELECT day, body FROM garmin_days")?;
    let rows = statement.query_map([], |row| {
        Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
    })?;
    let mut days = BTreeMap::new();
    for row in rows {
        let (day, body) = row?;
        match (day.parse(), serde_json::from_str::<GarminDay>(&body)) {
            (Ok(date), Ok(summary)) => {
                days.insert(Day(date), summary);
            }
            _ => log::warn!("garmin: dropped unreadable day {day}"),
        }
    }
    Ok(days)
}

fn persist_link(link: &Link) {
    if let Ok(json) = serde_json::to_string(link) {
        let _ = Storage::set_item(KEY_LINK, json);
    }
}

/// Whether a key is kept (tracked).
pub fn connected() -> bool {
    state().with(|s| !s.key.is_empty() && s.link.region.is_some())
}

/// The connected region (tracked).
pub fn region() -> Option<Region> {
    state().with(|s| s.link.region)
}

/// Where the last pull is (tracked).
pub fn sync_state() -> SyncState {
    state().with(|s| s.sync)
}

/// What Garmin measured on `day` (tracked).
pub fn on(day: Day) -> Option<GarminDay> {
    state().with(|s| s.days.get(&day).cloned())
}

/// Connects `key`: finds its region by exchanging it for a token and keeps
/// it. The root's [`refresh`] then pulls the last 30 days. Both tasks live
/// under the app root so closing Settings does not interrupt them. Nothing is
/// kept when it fails.
pub async fn connect(key: String) -> Result<Region, Failure> {
    let key = key.trim().to_owned();
    if key.is_empty() {
        return Err(Failure::KeyRejected);
    }
    let mut last = Failure::KeyRejected;
    for region in Region::ALL {
        match exchange(region, &key).await {
            Ok(token) => {
                let _ = Storage::set_item(KEY_SECRET, key.clone());
                state().update(|s| {
                    s.generation = s.generation.wrapping_add(1);
                    s.key = key.clone();
                    s.link.region = Some(region);
                    s.token = Some((token, clock::now_ms() + TOKEN_MS));
                    s.sync = SyncState::Idle;
                    persist_link(&s.link);
                });
                return Ok(region);
            }
            // A key of the other region: try it there.
            Err(Failure::KeyRejected) => last = Failure::KeyRejected,
            Err(failure) => return Err(failure),
        }
    }
    Err(last)
}

/// Forgets the key and token; imported days stay.
pub fn disconnect() {
    Storage::remove_item(KEY_SECRET);
    state().update(|s| {
        s.generation = s.generation.wrapping_add(1);
        s.key.clear();
        s.token = None;
        s.link = Link::default();
        s.sync = SyncState::Idle;
        persist_link(&s.link);
    });
}

/// Pulls recent days when connected: always when `force`, else only when
/// the last pull is older than 30 minutes. One pull at a time.
pub async fn refresh(force: bool) {
    let (key, region, last, syncing, token, generation) = state().with_untracked(|s| {
        (
            s.key.clone(),
            s.link.region,
            s.link.last_sync_ms,
            s.sync == SyncState::Syncing,
            s.token.clone(),
            s.generation,
        )
    });
    let Some(region) = region.filter(|_| !key.is_empty()) else {
        return;
    };
    let now = clock::now_ms();
    if syncing || (!force && last.is_some_and(|at| now - at < FRESH_MS)) {
        return;
    }
    state().update(|s| s.sync = SyncState::Syncing);
    let result = pull(region, &key, token.filter(|(_, until)| *until > now)).await;
    // A root task can finish after disconnect, reconnect or restore.
    // It must not write or revive the previous connection's state.
    if state().with_untracked(|s| s.generation != generation) {
        return;
    }
    if let Ok((_, days)) = &result {
        let written = db::with(|c| write_days(c, days));
        if let Some(Err(error)) = written {
            log::error!("garmin: days were not kept: {error}");
        }
    }
    state().update(|s| match result {
        Ok((token, days)) => {
            s.token = Some(token);
            s.days.extend(days);
            s.link.last_sync_ms = Some(clock::now_ms());
            s.sync = SyncState::Idle;
            persist_link(&s.link);
        }
        Err(failure) => {
            if failure == Failure::KeyRejected {
                s.token = None;
            }
            s.sync = SyncState::Failed(failure);
        }
    });
}

type Pulled = ((String, i64), BTreeMap<Day, GarminDay>);

async fn pull(region: Region, key: &str, token: Option<(String, i64)>) -> Result<Pulled, Failure> {
    let today = clock::today();
    let latest = state().with_untracked(|s| s.days.keys().next_back().copied());
    let first_allowed = today.plus_days(1 - FIRST_DAYS);
    // Re-read the last two days: a night or a day may have filled in since.
    let start = latest
        .map(|day| day.plus_days(-2).max(first_allowed))
        .unwrap_or(first_allowed);
    let mut token = match token {
        Some(token) => token,
        None => (exchange(region, key).await?, clock::now_ms() + TOKEN_MS),
    };
    let mut merged = BTreeMap::new();
    for (feed, url) in garmin::day_requests(region, &start.to_string(), &today.to_string()) {
        let mut answer = get(&url, &token.0).await?;
        if matches!(answer.0, 401 | 403) {
            // The token lapsed early: one new token, one retry.
            token = (exchange(region, key).await?, clock::now_ms() + TOKEN_MS);
            answer = get(&url, &token.0).await?;
        }
        match answer.0 {
            200 => garmin::merge(&mut merged, feed, &answer.1).map_err(|error| {
                log::warn!("garmin: {feed:?} answer unreadable: {error}");
                Failure::Unreadable
            })?,
            401 | 403 => return Err(Failure::KeyRejected),
            status => {
                log::warn!("garmin: {feed:?} answered {status}");
                return Err(Failure::Unreadable);
            }
        }
    }
    let days: BTreeMap<Day, GarminDay> = merged
        .into_values()
        .filter(|day| !day.is_empty())
        .filter_map(|day| Some((Day(day.day.parse().ok()?), day)))
        .collect();
    Ok((token, days))
}

fn write_days(connection: &Connection, days: &BTreeMap<Day, GarminDay>) -> rusqlite::Result<()> {
    let tx = connection.unchecked_transaction()?;
    let now = clock::now_ms();
    for (day, summary) in days {
        let body = serde_json::to_string(summary).unwrap_or_default();
        tx.execute(
            "INSERT INTO garmin_days (day, body, fetched_at_ms) VALUES (?1, ?2, ?3)
             ON CONFLICT (day) DO UPDATE SET body = excluded.body, fetched_at_ms = excluded.fetched_at_ms",
            params![day.to_string(), body, now],
        )?;
    }
    tx.commit()
}

/// Exchanges `key` for a token in `region`.
async fn exchange(region: Region, key: &str) -> Result<String, Failure> {
    let mut request = HttpRequest::new("POST", region.token_url())
        .header("Authorization", garmin::token_authorization(key))
        .body(Vec::new());
    request.follow_redirects = false;
    let response = fetch(request).await.map_err(|_| Failure::Network)?;
    let body = String::from_utf8_lossy(&response.body);
    match response.status() {
        200 => garmin::read_token(&body).ok_or(Failure::Unreadable),
        401 | 403 | 404 => Err(Failure::KeyRejected),
        status => {
            log::warn!("garmin: token endpoint answered {status}");
            Err(Failure::Unreadable)
        }
    }
}

async fn get(url: &str, token: &str) -> Result<(u16, String), Failure> {
    let mut request = HttpRequest::new("GET", url)
        .header("Authorization", garmin::bearer(token))
        .header("Accept", "application/json");
    request.follow_redirects = false;
    let response = fetch(request).await.map_err(|_| Failure::Network)?;
    Ok((
        response.status(),
        String::from_utf8_lossy(&response.body).into_owned(),
    ))
}
