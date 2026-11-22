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
    app.wait_for("label:/^Dollar bank · USD → Yuan bank, USD 100.00, Transfer/")?;
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
fn missing_fx_and_stored_provider_rates_are_visible_without_update_controls() -> Result<(), String>
{
    let dir = tempfile::tempdir().unwrap();
    seed(dir.path(), false);
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), Some(stub()));
    app.press("label:Assets")?;
    app.wait_for("Included assets")?;
    app.wait_for("Included debt")?;
    app.press("label:/^USD excluded · Missing rate, Cash accounts · Dollar bank/")?;
    app.wait_for("CNY per US dollar")?;
    assert!(!app.shows("Save rate") && !app.shows("Refresh prices and rates"));
    drop(app);
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    currency::save_rate(
        &db,
        &currency::FxRate {
            currency: Currency::USD,
            day: today().0,
            rate: 7_000_000,
            source: "frankfurter:ecb".into(),
        },
    )
    .unwrap();
    let (mut again, _) = start_in(Some(dir.path()), Vec::new(), Some(stub()));
    again.press("label:Assets")?;
    again.wait_for("label:¥7,000.00")?;
    assert!(!again.shows("Known value · CNY"));
    assert!(!again.shows("Included assets"));
    assert!(!again.shows("label:/excluded · Missing rate/"));
    again.press("label:Manage")?;
    again.press("Prices & rates")?;
    again.wait_for("text:/ECB$/")?;
    again.press("Changes")?;
    again.press("text:USD → CNY")?;
    again.wait_for("text:/^Recorded at /")?;
    Ok(())
}

#[test]
fn missing_rate_routes_to_its_pair_and_names_only_excluded_balances_and_open_positions()
-> Result<(), String> {
    use navi_finance::holdings::{self, Kind, Security, Trade, store};
    let dir = tempfile::tempdir().unwrap();
    seed(dir.path(), false);
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let long_names = [
        "Hong Kong family travel reserve wallet",
        "Hong Kong long-term savings account",
    ];
    for (i, name) in long_names.iter().enumerate() {
        let account = Account::new_in(AccountKind::Assets, name, Currency::HKD).unwrap();
        repository::create_account(&db, &account).unwrap();
        let entry = Entry {
            id: format!("hkd-wallet-{i}"),
            at: today().0.at(8, 0, 0, 0),
            payee: String::new(),
            note: String::new(),
            source: Source::Manual,
        };
        repository::save(&db, &journal::opening(entry, &account, 1000).unwrap()).unwrap();
    }
    let card = Account::new_in(AccountKind::Liabilities, "Hong Kong card", Currency::HKD).unwrap();
    let empty = Account::new_in(AccountKind::Assets, "Unused HKD wallet", Currency::HKD).unwrap();
    for a in [&card, &empty] {
        repository::create_account(&db, a).unwrap();
    }
    repository::save(
        &db,
        &journal::opening(
            Entry {
                id: "card-opening".into(),
                at: today().0.at(8, 0, 0, 0),
                payee: "".into(),
                note: "".into(),
                source: Source::Manual,
            },
            &card,
            -10_000,
        )
        .unwrap(),
    )
    .unwrap();
    let security = Security::new_in("hk", "Hong Kong fund", Currency::HKD).unwrap();
    let trade = Trade {
        id: "hk-opening".into(),
        security: security.id.clone(),
        at: today().0.at(9, 0, 0, 0),
        kind: Kind::Opening,
        quantity: holdings::SCALE,
        price: 10 * holdings::SCALE,
        amount: 0,
        fee: 0,
        cash: None,
    };
    store::add_trade(&db, Some(&security), &trade, today().0).unwrap();
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), Some(stub()));
    app.press("label:Assets")?;
    app.wait_for("label:/^USD excluded · Missing rate, Cash accounts · Dollar bank/")?;
    app.press("label:HKD excluded · Missing rate, 4 items excluded, View exchange rate")?;
    app.wait_for("CNY per HK dollar")?;
    for name in long_names
        .into_iter()
        .chain(["Hong Kong card", "Hong Kong fund"])
    {
        app.wait_for(&format!("id:excluded-fx-items >> text:{name}"))?;
    }
    assert!(!app.shows("id:excluded-fx-items >> text:Unused HKD wallet"));
    assert!(!app.shows("id:excluded-fx-items >> text:Dollar bank"));
    app.press("Changes")?;
    app.press("Rates")?;
    app.wait_for("CNY per HK dollar")?;
    app.press("label:Back")?;
    app.press("label:/^USD excluded · Missing rate/")?;
    app.wait_for("CNY per US dollar")?;
    app.wait_for("id:excluded-fx-items >> text:Dollar bank")?;
    assert!(!app.shows("id:excluded-fx-items >> text:Hong Kong card"));
    Ok(())
}

#[test]
fn short_history_names_the_first_convertible_day_in_its_change() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    seed(dir.path(), false);
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let usd = Account::parse("资产/USD:Dollar bank").unwrap();
    let start = today().plus_days(-5).0;
    let first_complete = today().plus_days(-3).0;
    // Today's USD opening is already in the fixture; before the first rate
    // this older opening made the headline partial.
    repository::save(
        &db,
        &journal::opening(
            Entry {
                id: "prior-usd".into(),
                at: start.at(8, 0, 0, 0),
                payee: "".into(),
                note: "".into(),
                source: Source::Manual,
            },
            &usd,
            500,
        )
        .unwrap(),
    )
    .unwrap();
    currency::save_rate(
        &db,
        &currency::FxRate {
            currency: Currency::USD,
            day: first_complete,
            rate: 7_000_000,
            source: "manual".into(),
        },
    )
    .unwrap();
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), Some(stub()));
    app.press("label:Assets")?;
    app.wait_for(&format!(
        "Since {} +¥7,000.00",
        first_complete.strftime("%b %-d, %Y")
    ))?;
    Ok(())
}
