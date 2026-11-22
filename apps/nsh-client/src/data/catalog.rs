//! Replaceable public catalog cache, independent from the owner’s holding identities.
use super::{clock, db};
use navi_finance::catalog::{self, Catalog, Entry, SecurityBinding};
use nsh_core::{platform::HttpRequest, prelude::*, storage::Storage};
use std::rc::Rc;
const BASE: &str = "https://github.com/zsh-a/NaviWealth/releases/download/securities-catalog/";
const CHECKED: &str = "catalog.checked.v1";
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum Status {
    #[default]
    Idle,
    Updating,
    Current,
    Updated,
    Failed,
}
#[derive(Clone, Default)]
struct State {
    catalog: Option<Rc<Catalog>>,
    status: Status,
    revision: u64,
    generation: u64,
    attempted: Option<i64>,
}
impl PartialEq for State {
    fn eq(&self, o: &Self) -> bool {
        self.revision == o.revision && self.status == o.status
    }
}
fn state() -> Signal<State> {
    global::<State>()
}
pub fn load() -> Result<(), String> {
    // Read the seed before entering the database thread: the ambient data
    // directory is not available there.
    let seed = db::catalog_seed();
    let catalog = db::with(|c| match catalog::current(c) {
        Ok(Some(current)) => Ok(Some(current)),
        // A seed beside the database bootstraps an empty install — tests and
        // manual recovery drop one there; the rolling release replaces it.
        Ok(None) => match seed {
            Some(body) => catalog::install_prepared(c, catalog::prepare(body)?).map(Some),
            None => Ok(None),
        },
        Err(e) => Err(e),
    })
    .ok_or("database is not open")?
    .map_err(|e: catalog::Error| e.to_string())?;
    state().update(|s| {
        s.catalog = catalog.map(Rc::new);
        s.revision = s.revision.wrapping_add(1);
        // A restore/reload invalidates any in-flight download or worker.
        s.generation = s.generation.wrapping_add(1);
        s.attempted = None;
        s.status = Status::Idle;
    });
    Ok(())
}
pub fn search_page(query: &str, offset: usize, limit: usize) -> Vec<Entry> {
    state().with(|s| {
        s.catalog
            .as_ref()
            .map(|c| c.search_page(query, offset, limit))
            .unwrap_or_default()
    })
}
pub(super) fn installed() -> Option<Rc<Catalog>> {
    state().with(|s| s.catalog.clone())
}
pub fn available() -> bool {
    state().with(|s| s.catalog.is_some())
}
pub fn status() -> Status {
    state().with(|s| s.status)
}
#[cfg(test)]
fn version() -> String {
    state().with(|s| {
        s.catalog
            .as_ref()
            .map(|c| c.header.version.clone())
            .unwrap_or_default()
    })
}
pub fn bindings() -> Vec<SecurityBinding> {
    let _ = state().get();
    db::with(catalog::bindings)
        .and_then(Result::ok)
        .unwrap_or_default()
}
pub fn bind(binding: &SecurityBinding) -> Result<(), String> {
    db::with(|c| catalog::bind(c, binding))
        .ok_or("database is not open")?
        .map_err(|e| e.to_string())?;
    // A re-link removed obsolete provider marks in the same database savepoint.
    // Reload reactive mirrors before showing this holding under its new identity.
    super::market::reload_prices()?;
    state().update(|s| s.revision = s.revision.wrapping_add(1));
    Ok(())
}
async fn get(url: &str, limit: usize) -> Result<Vec<u8>, String> {
    let response = fetch(HttpRequest::new("GET", url))
        .await
        .map_err(|e| format!("{e:?}"))?;
    if response.status() != 200 || response.body.len() > limit {
        return Err("catalog response is invalid".into());
    }
    Ok(response.body)
}
pub async fn refresh() {
    if status() == Status::Updating {
        return;
    }
    let now = clock::now_ms();
    let checked = Storage::get_item(CHECKED)
        .and_then(|s| s.parse::<i64>().ok())
        .unwrap_or(0);
    if (0..86_400_000).contains(&now.saturating_sub(checked))
        || state().with_untracked(|s| {
            s.attempted
                .is_some_and(|at| (0..300_000).contains(&(now - at)))
        })
    {
        return;
    }
    let generation = state().with_untracked(|s| s.generation.wrapping_add(1));
    state().update(|s| {
        s.generation = generation;
        s.attempted = Some(now);
        s.status = Status::Updating;
    });
    let current = || state().with_untracked(|s| s.generation == generation);
    let result = async {
        let raw = get(&format!("{BASE}catalog-manifest.json"), 16384).await?;
        if !current() {
            return Ok(Status::Current);
        }
        let m =
            catalog::Manifest::parse(std::str::from_utf8(&raw).map_err(|_| "invalid manifest")?)
                .map_err(|e| e.to_string())?;
        let newer =
            state().with_untracked(|s| s.catalog.as_ref().is_none_or(|c| m.newer(&c.header)));
        if !newer {
            return Ok(Status::Current);
        }
        let bytes = get(&format!("{BASE}{}", m.asset), catalog::MAX_DOWNLOAD).await?;
        if !current() {
            return Ok(Status::Current);
        }
        // Public catalog verification/decompression/indexing belongs on a
        // worker; SQLite remains exclusively on its owning engine thread.
        let prepared = blocking(move || m.prepare(&bytes))
            .await
            .map_err(|_| "catalog verification worker failed")?
            .map_err(|e| e.to_string())?;
        if !current() {
            return Ok(Status::Current);
        }
        let catalog = db::with(|c| catalog::install_prepared(c, prepared))
            .ok_or("database is not open")?
            .map_err(|e| e.to_string())?;
        state().update(|s| {
            s.catalog = Some(Rc::new(catalog));
            s.revision = s.revision.wrapping_add(1)
        });
        Ok::<_, String>(Status::Updated)
    }
    .await;
    if !current() {
        return;
    }
    match result {
        Ok(status) => {
            let _ = Storage::set_item(CHECKED, now.to_string());
            state().update(|s| s.status = status)
        }
        Err(e) => {
            log::warn!("catalog refresh failed; retaining offline listings: {e}");
            state().update(|s| s.status = Status::Failed)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use nsh_engine::{EngineConfig, Root};
    use nsh_testing::{Headless, MemoryStorage, StubNetwork, StubResponse};
    use std::{sync::Arc, time::Duration};

    #[component]
    fn RefreshProbe() -> impl IntoElement {
        db::open().unwrap();
        load().unwrap();
        let settled = signal(false);
        view()
            .child(text(|| format!("catalog {:?} {}", status(), version())))
            .child(text(
                move || if settled.get() { "settled" } else { "waiting" },
            ))
            .child(text("refresh").on_press(move || {
                settled.set(false);
                spawn(async move {
                    refresh().await;
                    settled.set(true);
                });
            }))
            .child(text("reload").on_press(move || {
                let before = version();
                load().unwrap();
                assert_eq!(version(), before);
            }))
    }

    #[test]
    fn reload_invalidates_an_inflight_refresh_without_overwriting_status_or_catalog() {
        let manifest = serde_json::json!({
            "schema": 1, "version": "v1.20990101", "checksum": "0000000000000000", "count": 1,
            "sha256": "0".repeat(64), "gzip_sha256": "0".repeat(64), "gzip_size": 1,
            "asset": "catalog.gz",
        });
        let mut response = StubResponse::default();
        response.status = 200;
        response.body = manifest.to_string().into_bytes();
        // Release the response only after reload, independent of renderer timing.
        let (waiting, pending) = std::sync::mpsc::channel();
        let mut config = EngineConfig::new(Root::of::<RefreshProbe>());
        config.storage = Some(MemoryStorage::new(Vec::new()));
        config.network = Some(Arc::new(StubNetwork::new([(
            format!("GET {BASE}catalog-manifest.json"),
            nsh_testing::StubRoute::Handler(Arc::new(move |_, reply| {
                waiting.send(reply).unwrap();
            })),
        )])));
        let mut app = Headless::start(config).unwrap();
        app.wait_for("refresh").unwrap();
        app.press("refresh").unwrap();
        app.wait_for("text:/catalog Updating/").unwrap();
        app.press("reload").unwrap();
        pending
            .recv_timeout(Duration::from_secs(1))
            .unwrap()
            .send(response);
        app.wait_for("settled").unwrap();
        app.wait_for("text:/catalog Idle/").unwrap();
    }
    #[test]
    fn failed_verification_retries_after_the_short_cooldown() {
        let manifest = serde_json::json!({
            "schema": 1, "version": "v1.20990101", "checksum": "0000000000000000", "count": 1,
            "sha256": "0".repeat(64), "gzip_sha256": "0".repeat(64), "gzip_size": 1,
            "asset": "catalog.gz",
        });
        let mut response = StubResponse::default();
        response.status = 200;
        response.body = manifest.to_string().into_bytes();
        response.delay = Duration::from_millis(200);
        let mut corrupt = StubResponse::default();
        corrupt.status = 200;
        corrupt.body = vec![0];
        let mut config = EngineConfig::new(Root::of::<RefreshProbe>());
        let now = std::time::SystemTime::now();
        config.clock = nsh_core::time::Clock::manual(now);
        config.storage = Some(MemoryStorage::new(Vec::new()));
        config.network = Some(Arc::new(StubNetwork::new([
            (format!("GET {BASE}catalog-manifest.json"), response),
            (format!("GET {BASE}catalog.gz"), corrupt),
        ])));
        let mut app = Headless::start(config).unwrap();
        app.wait_for("text:/catalog Idle/").unwrap();
        for attempt in 0..2 {
            if attempt == 1 {
                app.set_system_time(now + Duration::from_secs(301)).unwrap();
            }
            app.press("refresh").unwrap();
            app.wait_for("text:/catalog Updating/").unwrap();
            app.wait_for("text:/catalog Failed/").unwrap();
        }
    }
}
