//! The review category opens the matching journal and edits the original row.
mod common;
use common::*;
use finance_core::{
    account::{Account, AccountKind, defaults},
    journal::{self, Entry, Source},
    repository,
};
#[test]
fn category_drilldown_edits_the_original_transaction() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (app, _) = start_in(Some(dir.path()), vec![], None);
    drop(app);
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let cash = Account::new(AccountKind::Assets, "Cash").unwrap();
    for (id, category, amount) in [("Lunch shop", "餐饮", 3150), ("Bus", "交通", 200)] {
        let entry = Entry {
            id: id.into(),
            at: today().0.at(12, 0, 0, 0),
            payee: id.into(),
            note: String::new(),
            source: Source::Manual,
        };
        repository::save(
            &db,
            &journal::spend(entry, &cash, &defaults::expense(category), amount).unwrap(),
        )
        .unwrap();
    }
    drop(db);
    let (mut app, _) = start_in(Some(dir.path()), vec![], None);
    app.press("label:Review")?;
    app.wait_for("Recorded spending")?;
    app.wait_for("text:¥33.50")?;
    app.press("text:Dining")?;
    app.wait_for("label:/^Lunch shop, −31.50 CNY/")?;
    assert!(!app.shows("label:/^Bus, /"));
    app.press("label:/^Lunch shop, −31.50 CNY/")?;
    app.clear("label:Amount")?;
    app.type_text("label:Amount", "42.00")?;
    app.press("Save transaction")?;
    app.wait_for_gone("Save transaction", GONE)?;
    app.wait_for("label:/^Lunch shop, −42.00 CNY/")?;
    Ok(())
}
#[test]
fn health_only_review_does_not_invent_financial_zero() -> Result<(), String> {
    let (mut app, _) = start(pasta_today(), None);
    app.press("label:Review")?;
    app.wait_for("text:300")?;
    assert!(!app.shows("Recorded spending"));
    assert!(!app.shows("text:¥0.00"));
    Ok(())
}

#[test]
fn current_month_compares_only_elapsed_days() -> Result<(), String> {
    let today = today();
    let previous = today
        .0
        .first_of_month()
        .checked_sub(jiff::Span::new().days(1))
        .unwrap();
    if today.0.day() >= previous.day() || today.0 == today.0.last_of_month() {
        return Ok(());
    }
    let dir = tempfile::tempdir().unwrap();
    let (app, _) = start_in(Some(dir.path()), vec![], None);
    drop(app);
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let cash = Account::new(AccountKind::Assets, "Cash").unwrap();
    for (id, day) in [("Current", today.0), ("After comparison cutoff", previous)] {
        let e = Entry {
            id: id.into(),
            at: day.at(12, 0, 0, 0),
            payee: id.into(),
            note: String::new(),
            source: Source::Manual,
        };
        repository::save(
            &db,
            &journal::spend(e, &cash, &defaults::expense("餐饮"), 3150).unwrap(),
        )
        .unwrap();
    }
    drop(db);
    let (mut app, _) = start_in(Some(dir.path()), vec![], None);
    app.press("label:Review")?;
    app.press("This month")?;
    app.wait_for("No spending recorded in the comparison period")?;
    Ok(())
}
