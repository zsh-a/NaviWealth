//! Currency boundaries through the actual editors, valuation and restart.
mod common;
use common::*;
use navi_finance::{
    account::{Account, AccountKind, defaults},
    currency::{self, Currency},
    journal::{self, Entry, Source},
    repository,
};
fn stub() -> Arc<StubNetwork> {
    Arc::new(StubNetwork::new(Vec::<(String, StubResponse)>::new()))
}
fn seed(dir: &Path, expense: bool) {
    let (app, _) = start_in(Some(dir), Vec::new(), Some(stub()));
    drop(app);
    let db = rusqlite::Connection::open(database_in(dir)).unwrap();
    let usd = Account::new_in(AccountKind::Assets, "Dollar bank", Currency::USD).unwrap();
    let cny = Account::new(AccountKind::Assets, "Yuan bank").unwrap();
    repository::create_account(&db, &usd).unwrap();
    repository::create_account(&db, &cny).unwrap();
    let entry = |id: &str, payee: &str| Entry {
        id: id.into(),
        at: today().0.at(12, 0, 0, 0),
        payee: payee.into(),
        note: "".into(),
        source: Source::Manual,
    };
    repository::save(
        &db,
        &journal::opening(entry("opening", "Opening balance"), &usd, 100_000).unwrap(),
    )
    .unwrap();
    if expense {
        repository::save(
            &db,
            &journal::spend(
                entry("lunch", "Dollar lunch"),
                &usd,
                &defaults::expense("餐饮").in_currency(Currency::USD),
                3150,
            )
            .unwrap(),
        )
        .unwrap();
    }
}
#[test]
fn editing_foreign_expense_keeps_currency_and_category_after_restart() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    seed(dir.path(), true);
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), Some(stub()));
    app.press("label:/^Dollar lunch, −USD 31.50/")?;
    app.clear("label:Amount")?;
    app.type_text("label:Amount", "42.25")?;
    app.press("Save transaction")?;
    app.wait_for_gone("Save transaction", GONE)?;
    app.wait_for("label:/^Dollar lunch, −USD 42.25/")?;
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let entries = repository::transactions(&db).unwrap();
    let t = entries.iter().find(|t| t.id == "lunch").unwrap();
    assert!(
        t.postings
            .iter()
            .all(|p| p.account.currency() == Currency::USD)
    );
    assert_eq!(
        t.amount_in(&defaults::expense("餐饮").in_currency(Currency::USD)),
        4225
    );
    drop(app);
    let (mut again, _) = start_in(Some(dir.path()), Vec::new(), Some(stub()));
    again.wait_for("label:/^Dollar lunch, −USD 42.25/")?;
    Ok(())
}
#[test]
fn cross_currency_transfer_records_both_explicit_amounts() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    seed(dir.path(), false);
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), Some(stub()));
    open_manual(&mut app, "Log transaction")?;
    app.press("Transfer")?;
    app.press("From account")?;
    app.press("Dollar bank · USD · Cash / debit")?;
    app.press("To account")?;
    app.press("Yuan bank · Cash / debit")?;
    app.type_text("label:Amount", "100.00")?;
    app.type_text("label:Amount received", "700.00")?;
    app.press("Save transaction")?;
    app.wait_for_gone("Save transaction", GONE)?;
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let entries = repository::transactions(&db).unwrap();
    let t = entries.iter().find(|t| t.id != "opening").unwrap();
    assert!(t.validate().is_ok());
    assert_eq!(t.postings.len(), 4);
    assert_eq!(
        t.amount_in(&Account::parse("资产/USD:Dollar bank").unwrap()),
        -10_000
    );
    assert_eq!(
        t.amount_in(&Account::parse("资产:Yuan bank").unwrap()),
        70_000
    );
    assert!(t.postings.iter().all(|p| !matches!(
        p.account.kind(),
        AccountKind::Expenses | AccountKind::Income
    )));
    Ok(())
}
#[test]
fn missing_fx_is_visible_and_manual_rate_completes_valuation_after_restart() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    seed(dir.path(), false);
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), Some(stub()));
    app.press("label:Assets")?;
    app.wait_for("Known value · CNY")?;
    app.press("label:Manage")?;
    app.press("Exchange rates")?;
    app.press("text:USD → CNY")?;
    app.type_text("label:CNY per unit", "7.00")?;
    app.press("Save rate")?;
    app.wait_for_gone("Save rate", GONE)?;
    app.wait_for("text:/^1 USD = 7/")?;
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let rate = currency::rate_on(&db, Currency::USD, today().0)
        .unwrap()
        .unwrap();
    assert_eq!(rate.rate, 7_000_000);
    assert_eq!(rate.source, "manual");
    drop(app);
    let (mut again, _) = start_in(Some(dir.path()), Vec::new(), Some(stub()));
    again.press("label:Assets")?;
    again.wait_for("label:¥7,000.00")?;
    assert!(!again.shows("Known value · CNY"));
    Ok(())
}
