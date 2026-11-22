use jiff::civil::date;
use navi_finance::{
    account::{Account, AccountPurpose, defaults},
    assets,
    journal::{self, Entry, Source},
    repository::{self, BalanceCheck, Error},
};

fn db() -> navi_storage::sqlite::Connection {
    let c = navi_storage::memory(&[
        repository::SCHEMA,
        repository::BALANCE_SCHEMA,
        navi_finance::holdings::store::SCHEMA,
    ])
    .unwrap();
    repository::ensure_defaults(&c).unwrap();
    c
}
fn check(id: &str, a: &Account, actual: i64) -> BalanceCheck {
    BalanceCheck {
        id: id.into(),
        account: a.clone(),
        day: date(2026, 11, 14),
        actual,
        checked_at: date(2026, 11, 14).at(16, 0, 0, 0),
    }
}
fn entry(id: &str) -> Entry {
    Entry {
        id: id.into(),
        at: date(2026, 11, 14).at(12, 0, 0, 0),
        payee: String::new(),
        note: String::new(),
        source: Source::Manual,
    }
}

#[test]
fn backfilled_opening_rechecks_history_before_posting() {
    let c = db();
    let account = Account::parse("资产:购物卡").unwrap();
    let spend = |id, at| {
        let mut payment = entry(id);
        payment.at = at;
        journal::spend(payment, &account, &defaults::other_expense(), 950).unwrap()
    };
    repository::save(&c, &spend("first", date(2026, 11, 14).at(8, 0, 0, 0))).unwrap();
    let mut opening = check("opening", &account, 5000);
    opening.day = date(2026, 11, 13);
    repository::save(&c, &spend("backfilled", opening.day.at(18, 0, 0, 0))).unwrap();
    let tx = c.unchecked_transaction().unwrap();
    assert!(matches!(
        repository::opening::confirm(&tx, &opening),
        Err(Error::BalanceChanged)
    ));
    assert!(repository::balance_checks(&tx).unwrap().is_empty());
    opening.day = date(2026, 11, 12);
    let adjusted = repository::opening::confirm(&tx, &opening)
        .unwrap()
        .unwrap();
    assert_eq!(adjusted.amount_in(&defaults::opening()), -5000);
    let entries = repository::transactions(&tx).unwrap();
    assert_eq!(
        journal::balance_on(&entries, &account, date(2026, 11, 14)),
        3100
    );
    // Even a legacy posting with no separate observation establishes the opening.
    assert_eq!(
        repository::opening::latest_day(&account, &entries, &[], opening.day),
        None
    );
    assert!(repository::opening::confirm(&tx, &opening).is_err());
    tx.commit().unwrap();
}

#[test]
fn archiving_preserves_balances_history_and_undo_and_blocks_new_use() {
    let c = db();
    c.execute_batch(repository::ARCHIVE_SCHEMA).unwrap();
    let card = Account::parse("负债:信用卡").unwrap();
    let spend = |id| journal::spend(entry(id), &card, &defaults::expense("餐饮"), 1250).unwrap();
    let original = spend("coffee");
    repository::save(&c, &original).unwrap();
    repository::set_account_archived(&c, &card, true).unwrap();
    assert_eq!(
        repository::archived_accounts(&c).unwrap().as_slice(),
        std::slice::from_ref(&card)
    );
    assert!(repository::accounts(&c).unwrap().contains(&card));
    assert_eq!(
        repository::transactions(&c).unwrap().as_slice(),
        std::slice::from_ref(&original)
    );
    assert!(repository::save(&c, &spend("new")).is_err());
    assert!(
        repository::confirm_balance(&c, &check("archived-check", &card, -1250), -1250).is_err()
    );
    let mut edited = original;
    edited.note = "receipt".into();
    repository::save(&c, &edited).unwrap();
    let removed = repository::remove_confirmed(&c, &edited).unwrap();
    repository::restore_removed(&c, &removed).unwrap();
    let new = Account::parse("负债:旧卡").unwrap();
    let tx = c.unchecked_transaction().unwrap();
    repository::rename_account(&tx, &card, &new).unwrap();
    tx.commit().unwrap();
    assert_eq!(
        repository::archived_accounts(&c).unwrap().as_slice(),
        std::slice::from_ref(&new)
    );
    assert_eq!(
        repository::transactions(&c).unwrap()[0].amount_in(&new),
        -1250
    );
    repository::set_account_archived(&c, &new, false).unwrap();
    assert!(repository::archived_accounts(&c).unwrap().is_empty());
    repository::confirm_balance(&c, &check("active-check", &new, -1250), -1250).unwrap();
}

#[test]
fn purposes_are_optional_owned_metadata_and_follow_the_account_identity() {
    let db = db();
    db.execute_batch(repository::PURPOSE_SCHEMA).unwrap();
    let old = Account::parse("资产:储蓄卡").unwrap();
    repository::create_account(&db, &old).unwrap();
    assert!(repository::account_purposes(&db).unwrap().is_empty());
    assert!(repository::set_account_purpose(&db, &old, Some(AccountPurpose::Credit)).is_err());
    assert!(
        repository::set_account_purpose(
            &db,
            &defaults::other_expense(),
            Some(AccountPurpose::Wallet)
        )
        .is_err()
    );
    repository::set_account_purpose(&db, &old, Some(AccountPurpose::Bank)).unwrap();
    let renamed = Account::parse("资产:新名称").unwrap();
    let tx = db.unchecked_transaction().unwrap();
    repository::rename_account(&tx, &old, &renamed).unwrap();
    assert!(
        !repository::create_if_new_with_purpose(&tx, &renamed, AccountPurpose::Wallet).unwrap()
    );
    tx.commit().unwrap();
    assert_eq!(
        repository::account_purposes(&db)
            .unwrap()
            .into_iter()
            .collect::<Vec<_>>(),
        [(renamed.clone(), AccountPurpose::Bank)]
    );
    repository::set_account_purpose(&db, &renamed, Some(AccountPurpose::Brokerage)).unwrap();
    assert_eq!(
        repository::account_purposes(&db).unwrap()[&renamed],
        AccountPurpose::Brokerage
    );
    repository::set_account_purpose(&db, &renamed, None).unwrap();
    assert!(repository::account_purposes(&db).unwrap().is_empty());
}

#[test]
fn debt_reconciliation_is_exact_atomic_and_never_spending() {
    let c = db();
    let cash = Account::parse("资产:现金").unwrap();
    let card = Account::parse("负债:信用卡").unwrap();
    repository::create_account(&c, &cash).unwrap();
    repository::create_account(&c, &card).unwrap();
    repository::confirm_balance(&c, &check("cash", &cash, 100000), 0).unwrap();
    repository::confirm_balance(&c, &check("card", &card, -20000), 0).unwrap();
    repository::save(
        &c,
        &journal::spend(entry("lunch"), &card, &defaults::expense("餐饮"), 3150).unwrap(),
    )
    .unwrap();
    repository::save(
        &c,
        &journal::transfer(entry("repay"), &cash, &card, 10000).unwrap(),
    )
    .unwrap();
    let rows = repository::transactions(&c).unwrap();
    assert_eq!(
        assets::snapshot(&rows, date(2026, 11, 14)),
        assets::Snapshot {
            assets: 90000,
            debt: 13150,
            net: 76850
        }
    );
    assert!(matches!(
        repository::confirm_balance(&c, &check("stale", &card, -13000), -20000),
        Err(Error::BalanceChanged)
    ));
    c.execute_batch("CREATE TRIGGER reject_adjustment BEFORE INSERT ON finance_postings BEGIN SELECT RAISE(ABORT,'full disk'); END;").unwrap();
    assert!(repository::confirm_balance(&c, &check("adjust", &card, -13000), -13150).is_err());
    assert_eq!(repository::balance_checks(&c).unwrap().len(), 2);
    assert_eq!(repository::transactions(&c).unwrap(), rows);
    c.execute_batch("DROP TRIGGER reject_adjustment").unwrap();
    repository::confirm_balance(&c, &check("adjust", &card, -13000), -13150).unwrap();
    let same = check("verified", &card, -13000);
    assert!(
        repository::confirm_balance(&c, &same, -13000)
            .unwrap()
            .is_none()
    );
    assert!(repository::confirm_balance(&c, &same, -13000).is_err());
    let rows = repository::transactions(&c).unwrap();
    assert_eq!(rows.len(), 5);
    assert_eq!(
        journal::spending(&rows, date(2026, 11, 14), date(2026, 11, 14))
            [&defaults::expense("餐饮")],
        3150
    );
    assert_eq!(assets::snapshot(&rows, date(2026, 11, 14)).net, 77000);
    assert_eq!(
        assets::trend(&rows, date(2026, 11, 1), date(2026, 11, 15)),
        vec![(date(2026, 11, 14), 77000), (date(2026, 11, 15), 77000)]
    );
    assert_eq!(assets::book_value(&card, 20000), Some(-20000));
    assert_eq!(assets::book_value(&card, -500), Some(500));
}

#[test]
fn rename_moves_history_checks_and_mapping_without_merging_accounts() {
    let c = db();
    let old = Account::parse("资产:旧名").unwrap();
    let new = Account::parse("资产:新名").unwrap();
    repository::create_account(&c, &old).unwrap();
    repository::confirm_balance(&c, &check("zero", &old, 0), 0).unwrap();
    repository::save(
        &c,
        &journal::receive(entry("pay"), &old, &defaults::income("工资"), 12345).unwrap(),
    )
    .unwrap();
    let mut rules = navi_finance::import::Rules::default();
    rules.remember_method(
        navi_finance::statement::Provider::Alipay,
        "余额",
        old.clone(),
    );
    repository::save_rules(&c, &rules).unwrap();
    let tx = c.unchecked_transaction().unwrap();
    repository::rename_account(&tx, &old, &new).unwrap();
    tx.commit().unwrap();
    repository::validate(&c).unwrap();
    assert!(!repository::accounts(&c).unwrap().contains(&old));
    assert_eq!(
        journal::balance_on(
            &repository::transactions(&c).unwrap(),
            &new,
            date(2026, 11, 14)
        ),
        12345
    );
    assert_eq!(repository::balance_checks(&c).unwrap()[0].account, new);
    let mapped: String = c
        .query_row("SELECT account FROM finance_mapping_rules", [], |r| {
            r.get(0)
        })
        .unwrap();
    assert_eq!(mapped, new.as_str());
    repository::create_account(&c, &old).unwrap();
    let tx = c.unchecked_transaction().unwrap();
    assert!(matches!(
        repository::rename_account(&tx, &new, &old),
        Err(Error::AccountExists)
    ));
    drop(tx);
    assert_eq!(repository::balance_checks(&c).unwrap()[0].account, new);
}
