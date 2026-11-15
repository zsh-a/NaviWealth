//! Replaceable public catalog cache, independent from the owner’s holding identities.
use super::{clock, db};
use finance_core::catalog::{self, Catalog, Entry, SecurityBinding};
use nsh_core::{platform::HttpRequest, prelude::*, storage::Storage};
use std::rc::Rc;
const BUNDLE: &str = include_str!("../../../mobile/assets/catalog/securities.v1.ndjson");
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
    let catalog = db::with(|c| {
        // Only the header decides; the full bundle is parsed and indexed just
        // when it must be installed, so a launch indexes one catalog, not two.
        let bundled = catalog::header(BUNDLE)?;
        match catalog::current(c) {
            Ok(Some(current)) if current.header.version >= bundled.version => Ok(current),
            _ => catalog::install_prepared(c, catalog::prepare(BUNDLE.to_owned())?),
        }
    })
    .ok_or("database is not open")?
    .map_err(|e: catalog::Error| e.to_string())?;
    state().update(|s| {
        s.catalog = Some(Rc::new(catalog));
        s.revision = s.revision.wrapping_add(1);
        // A restore/reload invalidates any in-flight download or worker.
        s.generation = s.generation.wrapping_add(1);
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
    super::market::load()?;
    super::finance::load()?;
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
pub async fn refresh(force: bool) {
    if status() == Status::Updating {
        return;
    }
    let now = clock::now_ms();
    let checked = Storage::get_item(CHECKED)
        .and_then(|s| s.parse::<i64>().ok())
        .unwrap_or(0);
    if !force && now.saturating_sub(checked) < 24 * 60 * 60 * 1000 {
        return;
    }
    let generation = state().with_untracked(|s| s.generation.wrapping_add(1));
    state().update(|s| {
        s.generation = generation;
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
        let _ = Storage::set_item(CHECKED, now.to_string());
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
        Ok(status) => state().update(|s| s.status = status),
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
            .child(text("refresh").on_press(|| {
                spawn(refresh(true));
            }))
            .child(text("reload").on_press(move || {
                let before = version();
                load().unwrap();
                assert_eq!(version(), before);
                spawn(async move {
                    timer(Duration::from_millis(250)).await;
                    settled.set(true);
                });
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
        response.delay = Duration::from_millis(100);
        let mut config = EngineConfig::new(Root::of::<RefreshProbe>());
        config.storage = Some(MemoryStorage::new(Vec::new()));
        config.network = Some(Arc::new(StubNetwork::new([(
            format!("GET {BASE}catalog-manifest.json"),
            response,
        )])));
        let mut app = Headless::start(config).unwrap();
        app.wait_for("refresh").unwrap();
        app.press("refresh").unwrap();
        app.wait_for("text:/catalog Updating/").unwrap();
        app.press("reload").unwrap();
        app.wait_for("settled").unwrap();
        app.wait_for("text:/catalog Idle/").unwrap();
    }
    #[test]
    fn failed_verification_retains_offline_catalog_and_manual_retry() {
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
        config.storage = Some(MemoryStorage::new(Vec::new()));
        config.network = Some(Arc::new(StubNetwork::new([
            (format!("GET {BASE}catalog-manifest.json"), response),
            (format!("GET {BASE}catalog.gz"), corrupt),
        ])));
        let mut app = Headless::start(config).unwrap();
        let header: catalog::Header = serde_json::from_str(BUNDLE.lines().next().unwrap()).unwrap();
        app.wait_for(&format!("catalog Idle {}", header.version))
            .unwrap();
        for _ in 0..2 {
            app.press("refresh").unwrap();
            app.wait_for("text:/catalog Updating/").unwrap();
            app.wait_for(&format!("catalog Failed {}", header.version))
                .unwrap();
        }
    }
}
