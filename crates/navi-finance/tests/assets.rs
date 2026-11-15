use jiff::civil::date;
use navi_finance::{
    account::{Account, defaults},
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
