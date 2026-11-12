use super::*;
use crate::{
    models::{AccountCategory, NewAccount},
    tables,
};
use lifeos::{
    db::{Db, DbOpenOptions, migrations::core_migrations},
    sync::{outbox, stamp::HLC_KEY},
};

fn setup() -> (Connection, MutationStamper) {
    let conn = Connection::open_in_memory().unwrap();
    for migration in core_migrations().push(tables::migration()).steps() {
        conn.execute_batch(migration.sql).unwrap();
    }
    let stamper = MutationStamper::new("local", "device");
    system_accounts::seed_system_accounts(&conn, &stamper).unwrap();
    (conn, stamper)
}
fn account(conn: &Connection, st: &MutationStamper, name: &str, currency: &str) -> Account {
    accounts::create(
        conn,
        st,
        NewAccount::custody(AccountCategory::Bank, name, currency),
    )
    .unwrap()
}
fn draft(st: &MutationStamper, account: &Account, kind: RecordKind, amount: i64) -> RecordDraft {
    RecordDraft {
        kind,
        date: 1_767_258_000,
        amount: Decimal::from(amount),
        account_id: account.id.clone(),
        category_id: match kind {
            RecordKind::Expense => Some(system_accounts::system_account_id(
                &st.owner_user_id,
                "expense:dining",
            )),
            RecordKind::Income => Some(system_accounts::system_account_id(
                &st.owner_user_id,
                "income:salary",
            )),
            _ => None,
        },
        destination_account_id: None,
        destination_amount: None,
        payee: None,
        note: None,
    }
}
fn all(conn: &Connection, st: &MutationStamper) -> Vec<FinanceRecord> {
    records(conn, &st.owner_user_id, &RecordFilter::default(), 200, 0).unwrap()
}
fn balance(conn: &Connection, st: &MutationStamper, id: &str) -> Decimal {
    list_accounts(conn, &st.owner_user_id, true)
        .unwrap()
        .into_iter()
        .find(|(a, _)| a.id == id)
        .unwrap()
        .1
        .and_then(|b| b.legs.first().map(|(_, v)| *v))
        .unwrap_or_default()
}

#[test]
fn income_expense_transfer_edit_delete_reconcile_to_exact_balance() {
    let (mut conn, st) = setup();
    let bank = account(&conn, &st, "工资卡", "CNY");
    let cash = account(&conn, &st, "零钱", "CNY");
    let equity = system_accounts::system_account_id(&st.owner_user_id, "equity:openingBalance");
    let opening = builders::opening_balance(
        0,
        &bank.id,
        equity,
        Decimal::from(1000),
        "CNY",
        None,
        None,
        vec![],
    )
    .unwrap();
    journal::create(
        &mut conn,
        &st,
        &|_: &Connection, _: &str, _: &str, _: i64| None,
        "CNY",
        opening,
    )
    .unwrap();
    save(
        &mut conn,
        &st,
        None,
        &draft(&st, &bank, RecordKind::Income, 500),
    )
    .unwrap();
    let mut expense = draft(&st, &bank, RecordKind::Expense, 25);
    expense.note = Some("午餐".into());
    save(&mut conn, &st, None, &expense).unwrap();
    let expense_id = all(&conn, &st)
        .into_iter()
        .find(|r| r.kind == RecordKind::Expense)
        .unwrap()
        .id;
    let mut transfer = draft(&st, &bank, RecordKind::Transfer, 100);
    transfer.destination_account_id = Some(cash.id.clone());
    save(&mut conn, &st, None, &transfer).unwrap();
    assert_eq!(balance(&conn, &st, &bank.id), Decimal::from(1375));
    assert_eq!(balance(&conn, &st, &cash.id), Decimal::from(100));
    let totals = monthly_totals(&conn, &st.owner_user_id, 1, 2_000_000_000).unwrap();
    assert_eq!(
        totals,
        vec![("CNY".into(), Decimal::from(500), Decimal::from(25))]
    );
    expense.amount = Decimal::from(40);
    save(&mut conn, &st, Some(&expense_id), &expense).unwrap();
    assert_eq!(
        record(&conn, &st.owner_user_id, &expense_id)
            .unwrap()
            .amount,
        Decimal::from(40)
    );
    assert_eq!(balance(&conn, &st, &bank.id), Decimal::from(1360));
    assert_eq!(conn.query_row(r#"SELECT count(*) FROM "fin:postings" WHERE journal_entry_id=?1 AND deleted_at IS NOT NULL"#,params![expense_id],|r|r.get::<_,i64>(0)).unwrap(),2);
    delete_record(&mut conn, &st, &expense_id).unwrap();
    assert!(record(&conn, &st.owner_user_id, &expense_id).is_err());
    assert_eq!(balance(&conn, &st, &bank.id), Decimal::from(1400));
    assert!(
        outbox::pending(&conn, 1000)
            .unwrap()
            .iter()
            .any(|(table, id)| table == tables::JOURNAL_ENTRIES_TABLE && id == &expense_id)
    );
}

#[test]
fn failed_edit_rolls_back_old_legs_entry_clock_and_outbox() {
    let (mut conn, st) = setup();
    let bank = account(&conn, &st, "现金", "CNY");
    let mut entry = draft(&st, &bank, RecordKind::Expense, 5);
    save(&mut conn, &st, None, &entry).unwrap();
    let original = all(&conn, &st)[0].clone();
    let pending = outbox::pending(&conn, 1000).unwrap();
    let clock = lifeos::db::settings::get_setting(&conn, HLC_KEY).unwrap();
    conn.execute_batch(r#"CREATE TRIGGER refuse_insert BEFORE INSERT ON "fin:postings" WHEN NEW.units = '-13' BEGIN SELECT RAISE(ABORT,'injected failure'); END;"#).unwrap();
    entry.amount = Decimal::from(13);
    entry.note = Some("must roll back".into());
    assert!(save(&mut conn, &st, Some(&original.id), &entry).is_err());
    assert_eq!(
        record(&conn, &st.owner_user_id, &original.id).unwrap(),
        original
    );
    assert_eq!(balance(&conn, &st, &bank.id), Decimal::from(-5));
    assert_eq!(outbox::pending(&conn, 1000).unwrap(), pending);
    assert_eq!(
        lifeos::db::settings::get_setting(&conn, HLC_KEY).unwrap(),
        clock
    );
    assert_eq!(
        conn.query_row(
            r#"SELECT count(*) FROM "fin:postings" WHERE deleted_at IS NOT NULL"#,
            [],
            |r| r.get::<_, i64>(0)
        )
        .unwrap(),
        0
    );
}

#[test]
fn owner_isolation_covers_reads_records_categories_and_account_mutations() {
    let (mut conn, st) = setup();
    let own = account(&conn, &st, "本人", "CNY");
    let other = MutationStamper::new("other", "other-device");
    system_accounts::seed_system_accounts(&conn, &other).unwrap();
    let foreign = account(&conn, &other, "其他用户", "CNY");
    save(
        &mut conn,
        &other,
        None,
        &draft(&other, &foreign, RecordKind::Income, 20),
    )
    .unwrap();
    let other_id = all(&conn, &other)[0].id.clone();
    assert_eq!(
        list_accounts(&conn, &st.owner_user_id, true).unwrap().len(),
        1
    );
    assert!(all(&conn, &st).is_empty());
    assert!(record(&conn, &st.owner_user_id, &other_id).is_err());
    assert!(delete_record(&mut conn, &st, &other_id).is_err());
    assert!(update_account(&mut conn, &st, &foreign.id, "changed".into(), None, None).is_err());
    assert!(archive_account(&mut conn, &st, &foreign.id, true).is_err());
    assert!(delete_account(&mut conn, &st, &foreign.id).is_err());
    assert!(
        save(
            &mut conn,
            &st,
            None,
            &draft(&st, &foreign, RecordKind::Expense, 10)
        )
        .is_err()
    );
    let mut invalid = draft(&st, &own, RecordKind::Expense, 10);
    invalid.category_id = Some(system_accounts::system_account_id(
        "other",
        "expense:dining",
    ));
    assert!(save(&mut conn, &st, None, &invalid).is_err());
    assert_eq!(balance(&conn, &other, &foreign.id), Decimal::from(20));
}

#[test]
fn archived_accounts_preserve_history_and_restore_to_record_picker() {
    let (mut conn, st) = setup();
    let bank = account(&conn, &st, "原名", "CNY");
    save(
        &mut conn,
        &st,
        None,
        &draft(&st, &bank, RecordKind::Income, 100),
    )
    .unwrap();
    update_account(
        &mut conn,
        &st,
        &bank.id,
        " 新名称 ".into(),
        Some(" 招行 ".into()),
        None,
    )
    .unwrap();
    archive_account(&mut conn, &st, &bank.id, true).unwrap();
    assert!(
        list_accounts(&conn, &st.owner_user_id, false)
            .unwrap()
            .is_empty()
    );
    assert_eq!(all(&conn, &st)[0].account_name, "新名称");
    assert!(
        save(
            &mut conn,
            &st,
            None,
            &draft(&st, &bank, RecordKind::Expense, 10)
        )
        .is_err()
    );
    assert!(delete_account(&mut conn, &st, &bank.id).is_err());
    archive_account(&mut conn, &st, &bank.id, false).unwrap();
    save(
        &mut conn,
        &st,
        None,
        &draft(&st, &bank, RecordKind::Expense, 10),
    )
    .unwrap();
    assert_eq!(balance(&conn, &st, &bank.id), Decimal::from(90));
}

#[test]
fn deletion_retains_history_and_allows_only_never_used_accounts() {
    let (mut conn, st) = setup();
    let unused = account(&conn, &st, "unused", "CNY");
    delete_account(&mut conn, &st, &unused.id).unwrap();
    assert!(
        list_accounts(&conn, &st.owner_user_id, true)
            .unwrap()
            .is_empty()
    );
    let used = account(&conn, &st, "used", "CNY");
    save(
        &mut conn,
        &st,
        None,
        &draft(&st, &used, RecordKind::Expense, 1),
    )
    .unwrap();
    let id = all(&conn, &st)[0].id.clone();
    delete_record(&mut conn, &st, &id).unwrap();
    assert!(delete_account(&mut conn, &st, &used.id).is_err());
    assert_eq!(
        list_accounts(&conn, &st.owner_user_id, true).unwrap().len(),
        1
    );
}

#[test]
fn cross_currency_transfer_requires_received_amount_and_preserves_units() {
    let (mut conn, st) = setup();
    let usd = account(&conn, &st, "美元", "USD");
    let cny = account(&conn, &st, "人民币", "CNY");
    let mut transfer = draft(&st, &usd, RecordKind::Transfer, 100);
    transfer.destination_account_id = Some(cny.id.clone());
    assert!(save(&mut conn, &st, None, &transfer).is_err());
    transfer.destination_amount = Some(Decimal::from(715));
    save(&mut conn, &st, None, &transfer).unwrap();
    let row = all(&conn, &st)[0].clone();
    assert_eq!(row.currency, "USD");
    assert_eq!(row.destination_currency.as_deref(), Some("CNY"));
    assert_eq!(row.destination_amount, Some(Decimal::from(715)));
    assert_eq!(balance(&conn, &st, &usd.id), Decimal::from(-100));
    assert_eq!(balance(&conn, &st, &cny.id), Decimal::from(715));
    transfer.destination_account_id = Some(usd.id.clone());
    assert!(save(&mut conn, &st, None, &transfer).is_err());
}

#[test]
fn search_kind_date_account_filters_and_pagination_include_more_than_100_records() {
    let (mut conn, st) = setup();
    let bank = account(&conn, &st, "银行卡", "CNY");
    for i in 0..105 {
        let mut expense = draft(&st, &bank, RecordKind::Expense, i + 1);
        expense.date = 1000 + i;
        expense.note = Some(format!("午餐 {i}"));
        save(&mut conn, &st, None, &expense).unwrap();
    }
    assert_eq!(
        records(&conn, &st.owner_user_id, &RecordFilter::default(), 100, 0)
            .unwrap()
            .len(),
        100
    );
    assert_eq!(
        records(&conn, &st.owner_user_id, &RecordFilter::default(), 100, 100)
            .unwrap()
            .len(),
        5
    );
    let filter = RecordFilter {
        category_id: None,
        query: "午餐 10".into(),
        kind: Some(RecordKind::Expense),
        account_id: Some(bank.id),
        from: Some(1100),
        until: Some(1105),
    };
    let matched = records(&conn, &st.owner_user_id, &filter, 100, 0).unwrap();
    assert_eq!(matched.len(), 5);
    assert_eq!(matched[0].amount, Decimal::from(105));
    assert!(
        records(
            &conn,
            &st.owner_user_id,
            &RecordFilter {
                kind: Some(RecordKind::Income),
                ..Default::default()
            },
            100,
            0
        )
        .unwrap()
        .is_empty()
    );
}

#[test]
fn file_backed_records_survive_reopen_after_edit_and_delete() {
    let path = std::env::temp_dir().join(format!("finance-daily-{}.db", lifeos::ids::new_id()));
    let options = || DbOpenOptions {
        path: path.clone(),
        encryption_key: None,
        migrations: core_migrations().push(tables::migration()),
    };
    let db = Db::open(options()).unwrap();
    let (account_id, record_id) = db
        .call_sync(|conn| {
            let st = MutationStamper::new("local", "device");
            system_accounts::seed_system_accounts(conn, &st)?;
            let bank = account(conn, &st, "持久账户", "CNY");
            let mut item = draft(&st, &bank, RecordKind::Income, 100);
            save(conn, &st, None, &item)?;
            let id = all(conn, &st)[0].id.clone();
            item.amount = Decimal::from(120);
            save(conn, &st, Some(&id), &item)?;
            Ok((bank.id, id))
        })
        .unwrap();
    drop(db);
    let reopened = Db::open(options()).unwrap();
    reopened
        .call_sync(move |conn| {
            let st = MutationStamper::new("local", "device");
            assert_eq!(
                record(conn, "local", &record_id)?.amount,
                Decimal::from(120)
            );
            assert_eq!(balance(conn, &st, &account_id), Decimal::from(120));
            delete_record(conn, &st, &record_id)?;
            Ok(())
        })
        .unwrap();
    drop(reopened);
    let final_db = Db::open(options()).unwrap();
    final_db
        .call_sync(|conn| {
            assert!(records(conn, "local", &RecordFilter::default(), 100, 0)?.is_empty());
            Ok(())
        })
        .unwrap();
}

#[test]
fn opening_balance_edit_keeps_account_and_preserves_entry_metadata() {
    let (mut conn, st) = setup();
    let bank = account(&conn, &st, "初始账户", "CNY");
    let other = account(&conn, &st, "其他账户", "CNY");
    let mut opening = builders::opening_balance(
        0,
        &bank.id,
        system_accounts::system_account_id(&st.owner_user_id, "equity:openingBalance"),
        Decimal::from(100),
        "CNY",
        None,
        Some(77),
        vec!["saved-tag".to_owned()],
    )
    .unwrap();
    opening.entry.flag = crate::models::EntryFlag::Pending;
    let created = journal::create(
        &mut conn,
        &st,
        &|_: &Connection, _: &str, _: &str, _: i64| None,
        "CNY",
        opening,
    )
    .unwrap();
    let mut edited = draft(&st, &bank, RecordKind::OpeningBalance, 150);
    edited.date = 10;
    save(&mut conn, &st, Some(&created.entry.id), &edited).unwrap();
    let row = journal::get(&conn, &created.entry.id).unwrap().unwrap();
    assert_eq!(row.entry.id, created.entry.id);
    assert_eq!(row.entry.settled_on, Some(77));
    assert_eq!(row.entry.tag_ids, vec!["saved-tag"]);
    assert_eq!(row.entry.flag, crate::models::EntryFlag::Pending);
    assert_eq!(balance(&conn, &st, &bank.id), Decimal::from(150));
    edited.account_id = other.id;
    assert!(save(&mut conn, &st, Some(&created.entry.id), &edited).is_err());
    assert_eq!(balance(&conn, &st, &bank.id), Decimal::from(150));
}

#[test]
fn capture_categories_follow_taxonomy_order_and_exclude_branches() {
    let (conn, st) = setup();
    let expenses = categories(&conn, &st.owner_user_id, RecordKind::Expense).unwrap();
    assert_eq!(
        expenses[0],
        (
            system_accounts::system_account_id("local", "expense:dining"),
            "餐饮".to_owned()
        )
    );
    assert!(!expenses.iter().any(|(id, _)| id
        == &system_accounts::system_account_id("local", "expense:trading")
        || id == &system_accounts::system_account_id("local", "expense:tax")));
    let income = categories(&conn, &st.owner_user_id, RecordKind::Income).unwrap();
    assert_eq!(
        income[0],
        (
            system_accounts::system_account_id("local", "income:salary"),
            "工资薪酬".to_owned()
        )
    );
}

#[path = "tests_more.rs"]
mod more;
