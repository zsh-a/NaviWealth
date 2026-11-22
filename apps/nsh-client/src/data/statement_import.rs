//! SQLite-backed import drafts; signals change only after successful writes.
use super::{db, finance};
use navi_finance::{
    import::store::{self, Draft},
    repository,
};
use nsh_core::prelude::*;
#[derive(Clone, Default, PartialEq)]
struct State {
    draft: Option<Draft>,
    report: Option<navi_finance::statement::Report>,
    rows: Vec<navi_finance::import::Candidate>,
}
impl State {
    fn new(draft: Option<Draft>) -> Self {
        let report = draft
            .as_ref()
            .map(|d| navi_finance::statement::review(&d.text, "CNY"));
        let rows = draft
            .as_ref()
            .zip(report.as_ref())
            .map(|(d, r)| d.review_report(r))
            .unwrap_or_default();
        Self {
            draft,
            report,
            rows,
        }
    }
}
fn state() -> Signal<State> {
    global::<State>()
}
pub fn has_draft() -> bool {
    state().with(|s| s.draft.is_some())
}
pub fn current() -> Option<Draft> {
    state().with(|s| s.draft.clone())
}
pub fn report() -> Option<navi_finance::statement::Report> {
    state().with(|s| s.report.clone())
}
pub fn rows() -> Vec<navi_finance::import::Candidate> {
    state().with(|s| s.rows.clone())
}
pub fn selected_count() -> usize {
    state().with(|s| {
        s.draft.as_ref().map_or(0, |d| {
            s.rows
                .iter()
                .enumerate()
                .filter(|(i, c)| d.is_selected(*i, c))
                .count()
        })
    })
}
pub fn load() -> Result<(), String> {
    let draft = db::with(store::active)
        .ok_or("database unavailable")?
        .map_err(|e| e.to_string())?;
    state().set(State::new(draft));
    Ok(())
}

pub(super) fn publish_review(draft: Draft) {
    state().set(State::new(Some(draft)));
}
pub async fn open_file(name: String, bytes: Vec<u8>) -> Result<(), String> {
    let (rules, journal) = db::with(|c| -> Result<_, repository::Error> {
        Ok((repository::rules(c)?, repository::transactions(c)?))
    })
    .ok_or("database unavailable")?
    .map_err(|e| e.to_string())?;
    let (send, receive) = futures::channel::oneshot::channel();
    std::thread::spawn(move || {
        let _ =
            send.send(store::read_file(&name, &bytes, rules, journal).map_err(|e| e.to_string()));
    });
    let mut prepared = receive
        .await
        .map_err(|_| "statement reader interrupted")??;
    db::with(|c| store::keep_prepared(c, &mut prepared))
        .ok_or("database unavailable")?
        .map_err(|e| e.to_string())?;
    state().set(State {
        draft: Some(prepared.draft),
        report: Some(prepared.report),
        rows: prepared.rows,
    });
    Ok(())
}
pub fn update(edit: impl FnOnce(&mut Draft)) -> Result<(), String> {
    let mut draft = untracked(current).ok_or("no import draft")?;
    edit(&mut draft);
    draft.prune_pending_purposes();
    db::with(|c| store::save(c, &draft))
        .ok_or("database unavailable")?
        .map_err(|e| e.to_string())?;
    let previous = untracked(|| state().get());
    let report = previous.report;
    let rows = if previous.draft.as_ref().is_some_and(|old| {
        old.rules == draft.rules
            && old.corrections == draft.corrections
            && old.journal == draft.journal
    }) {
        previous.rows
    } else {
        draft.review_report(report.as_ref().ok_or("missing import report")?)
    };
    state().set(State {
        draft: Some(draft),
        report,
        rows,
    });
    Ok(())
}
pub fn discard() -> Result<(), String> {
    db::with(store::discard)
        .ok_or("database unavailable")?
        .map_err(|e| e.to_string())?;
    state().set(State::new(None));
    Ok(())
}
/// A stale review is retained and refreshed; the owner must confirm again.
pub fn confirm() -> Result<Option<usize>, String> {
    let mut draft = untracked(current).ok_or("no import draft")?;
    let result = db::with(|c| store::confirm(c, &draft))
        .ok_or("database unavailable")?
        .map_err(|e| e.to_string())?;
    if result.is_none() {
        db::with(|c| -> Result<(), repository::Error> {
            draft.refresh(c)?;
            store::save(c, &draft)
        })
        .ok_or("database unavailable")?
        .map_err(|e| e.to_string())?;
        state().set(State::new(Some(draft)));
    } else {
        state().set(State::new(None));
        if let Err(error) = finance::load() {
            log::error!("statement import: committed; ledger mirror refresh failed: {error}");
        }
    }
    Ok(result)
}
