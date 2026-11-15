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
        let bundle = catalog::parse(BUNDLE)?;
        match catalog::current(c) {
            Ok(Some(current)) if current.header.version >= bundle.header.version => Ok(current),
            _ => catalog::install(c, BUNDLE),
        }
    })
    .ok_or("database is not open")?
    .map_err(|e: catalog::Error| e.to_string())?;
    state().update(|s| {
        s.catalog = Some(Rc::new(catalog));
        s.revision = s.revision.wrapping_add(1)
    });
    Ok(())
}
pub fn search(query: &str) -> Vec<Entry> {
    state().with(|s| {
        s.catalog
            .as_ref()
            .map(|c| c.search(query, 40))
            .unwrap_or_default()
    })
}
pub fn status() -> Status {
    state().with(|s| s.status)
}
pub fn version() -> String {
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
    state().update(|s| s.status = Status::Updating);
    let result = async {
        let raw = get(&format!("{BASE}catalog-manifest.json"), 16384).await?;
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
        let raw = m.verify(&bytes).map_err(|e| e.to_string())?;
        let catalog = db::with(|c| catalog::install(c, &raw))
            .ok_or("database is not open")?
            .map_err(|e| e.to_string())?;
        state().update(|s| {
            s.catalog = Some(Rc::new(catalog));
            s.revision = s.revision.wrapping_add(1)
        });
        Ok::<_, String>(Status::Updated)
    }
    .await;
    match result {
        Ok(status) => state().update(|s| s.status = status),
        Err(e) => {
            log::warn!("catalog refresh failed; retaining offline listings: {e}");
            state().update(|s| s.status = Status::Failed)
        }
    }
}
