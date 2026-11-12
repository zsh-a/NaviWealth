use super::*;

#[test]
fn archived_original_account_allows_record_correction_but_not_new_activity_or_redirects() {
    let (mut conn, st) = setup();
    let bank = account(&conn, &st, "已归档的原账户", "CNY");
    let other = account(&conn, &st, "另一个归档账户", "CNY");
    let mut expense = draft(&st, &bank, RecordKind::Expense, 50);
    save(&mut conn, &st, None, &expense).unwrap();
    let original = all(&conn, &st)[0].clone();
    archive_account(&mut conn, &st, &bank.id, true).unwrap();
    archive_account(&mut conn, &st, &other.id, true).unwrap();
    conn.execute("DELETE FROM op_outbox", []).unwrap();

    expense.date += 86_400;
    expense.note = Some("补充历史备注".to_owned());
    save(&mut conn, &st, Some(&original.id), &expense).unwrap();
    let corrected = record(&conn, &st.owner_user_id, &original.id).unwrap();
    assert_eq!(corrected.id, original.id);
    assert_eq!(corrected.date, expense.date);
    assert_eq!(corrected.note.as_deref(), Some("补充历史备注"));
    assert_eq!(balance(&conn, &st, &bank.id), Decimal::from(-50));
    let pending = outbox::pending(&conn, 100).unwrap();
    assert_eq!(
        pending.len(),
        5,
        "entry, two tombstoned legs and two replacement legs"
    );
    assert!(pending.contains(&(
        tables::JOURNAL_ENTRIES_TABLE.to_owned(),
        original.id.clone()
    )));

    assert!(save(&mut conn, &st, None, &expense).is_err());
    expense.account_id = other.id;
    assert!(save(&mut conn, &st, Some(&original.id), &expense).is_err());
    assert_eq!(
        record(&conn, &st.owner_user_id, &original.id).unwrap(),
        corrected
    );
    assert_eq!(outbox::pending(&conn, 100).unwrap(), pending);
}

#[test]
fn archived_transfer_original_legs_can_be_corrected_without_authorizing_other_archived_legs() {
    let (mut conn, st) = setup();
    let from = account(&conn, &st, "原转出账户", "CNY");
    let to = account(&conn, &st, "原转入账户", "CNY");
    let other = account(&conn, &st, "新归档账户", "CNY");
    let mut transfer = draft(&st, &from, RecordKind::Transfer, 100);
    transfer.destination_account_id = Some(to.id.clone());
    save(&mut conn, &st, None, &transfer).unwrap();
    let id = all(&conn, &st)[0].id.clone();
    for id in [&from.id, &to.id, &other.id] {
        archive_account(&mut conn, &st, id, true).unwrap();
    }
    transfer.note = Some("更正历史转账备注".to_owned());
    save(&mut conn, &st, Some(&id), &transfer).unwrap();
    assert_eq!(balance(&conn, &st, &from.id), Decimal::from(-100));
    assert_eq!(balance(&conn, &st, &to.id), Decimal::from(100));
    transfer.destination_account_id = Some(other.id);
    assert!(save(&mut conn, &st, Some(&id), &transfer).is_err());
    assert_eq!(
        record(&conn, &st.owner_user_id, &id)
            .unwrap()
            .destination_account_id,
        Some(to.id)
    );
}

#[test]
fn large_cross_currency_transfer_keeps_full_decimal_rate_precision() {
    let (mut conn, st) = setup();
    let usd = account(&conn, &st, "USD", "USD");
    let krw = account(&conn, &st, "KRW", "KRW");
    let mut transfer = draft(&st, &usd, RecordKind::Transfer, 10_000);
    transfer.destination_account_id = Some(krw.id.clone());
    transfer.destination_amount = Some(Decimal::from(14_000_000));
    save(&mut conn, &st, None, &transfer).unwrap();
    assert_eq!(balance(&conn, &st, &usd.id), Decimal::from(-10_000));
    assert_eq!(balance(&conn, &st, &krw.id), Decimal::from(14_000_000));
}

#[test]
fn unrepresentable_exchange_rate_returns_error_and_keeps_database_worker_usable() {
    let db = Db::open(DbOpenOptions {
        path: ":memory:".into(),
        encryption_key: None,
        migrations: core_migrations().push(tables::migration()),
    })
    .unwrap();
    db.call_sync(|conn| {
        let st = MutationStamper::new("local", "device");
        system_accounts::seed_system_accounts(conn, &st)?;
        let usd = account(conn, &st, "USD", "USD");
        let cny = account(conn, &st, "CNY", "CNY");
        let mut transfer = draft(&st, &usd, RecordKind::Transfer, 100);
        transfer.destination_account_id = Some(cny.id);
        transfer.destination_amount = Some(Decimal::new(1, 28));
        let pending = outbox::pending(conn, 100)?;
        assert!(save(conn, &st, None, &transfer).is_err());
        assert_eq!(outbox::pending(conn, 100)?, pending);
        assert!(all(conn, &st).is_empty());
        transfer.destination_amount = Some(Decimal::from(715));
        save(conn, &st, None, &transfer)?;
        Ok(())
    })
    .unwrap();
    db.call_sync(|conn| {
        assert_eq!(
            record(
                conn,
                "local",
                &all(conn, &MutationStamper::new("local", "device"))[0].id
            )?
            .amount,
            Decimal::from(100)
        );
        Ok(())
    })
    .unwrap();
}

#[test]
fn historical_hidden_or_archived_category_is_preserved_on_correction() {
    let (mut conn, st) = setup();
    let bank = account(&conn, &st, "原版表单账户", "CNY");
    let branch = system_accounts::system_account_id("local", "expense:trading");
    let build = builders::expense(
        100,
        &branch,
        &bank.id,
        Decimal::from(50),
        "CNY",
        None,
        None,
        None,
        vec![],
    )
    .unwrap();
    let previous = journal::create(
        &mut conn,
        &st,
        &|_: &Connection, _: &str, _: &str, _: i64| None,
        "CNY",
        build,
    )
    .unwrap();
    conn.execute(
        r#"UPDATE "fin:categories" SET archived=1 WHERE ledger_account_id=?1"#,
        params![branch],
    )
    .unwrap();
    assert!(
        !categories(&conn, "local", RecordKind::Expense)
            .unwrap()
            .iter()
            .any(|(id, _)| id == &branch)
    );
    let mut correction = draft(&st, &bank, RecordKind::Expense, 50);
    correction.category_id = Some(branch.clone());
    correction.date = 200;
    correction.note = Some("更正现有记录".to_owned());
    save(&mut conn, &st, Some(&previous.entry.id), &correction).unwrap();
    let corrected = record(&conn, "local", &previous.entry.id).unwrap();
    assert_eq!(corrected.category_id, Some(branch.clone()));
    assert_eq!(corrected.category_name.as_deref(), Some("交易"));
    assert_eq!(corrected.note.as_deref(), Some("更正现有记录"));
    assert_eq!(balance(&conn, &st, &bank.id), Decimal::from(-50));
    assert!(save(&mut conn, &st, None, &correction).is_err());
    correction.category_id = Some(system_accounts::system_account_id("local", "expense:tax"));
    assert!(save(&mut conn, &st, Some(&previous.entry.id), &correction).is_err());
    correction.category_id = Some(branch.clone());
    conn.execute(
        r#"UPDATE "fin:categories" SET deleted_at=1 WHERE ledger_account_id=?1"#,
        params![branch],
    )
    .unwrap();
    assert!(save(&mut conn, &st, Some(&previous.entry.id), &correction).is_err());
}

fn compound_build(date: i64, note: &str, legs: Vec<(String, i64, &str)>) -> builders::EntryBuild {
    builders::EntryBuild {
        entry: builders::EntryDraft {
            date,
            settled_on: None,
            narration: note.to_owned(),
            payee: None,
            flag: crate::models::EntryFlag::Confirmed,
            tag_ids: vec![],
        },
        postings: legs
            .into_iter()
            .enumerate()
            .map(
                |(position, (account_id, amount, unit))| builders::PostingDraft {
                    position,
                    account_id,
                    units: Decimal::from(amount),
                    unit: unit.to_owned(),
                    cost: None,
                    price: None,
                },
            )
            .collect(),
    }
}

#[test]
fn split_and_other_journals_remain_readable_without_flattening_edits_or_blocking_daily_rows() {
    let (mut conn, st) = setup();
    let bank = account(&conn, &st, "银行", "CNY");
    save(
        &mut conn,
        &st,
        None,
        &draft(&st, &bank, RecordKind::Expense, 10),
    )
    .unwrap();
    let split = compound_build(
        100,
        "组合支出",
        vec![
            (
                system_accounts::system_account_id("local", "expense:dining"),
                30,
                "CNY",
            ),
            (
                system_accounts::system_account_id("local", "expense:coffee"),
                20,
                "CNY",
            ),
            (bank.id.clone(), -50, "CNY"),
        ],
    );
    let created = journal::create(
        &mut conn,
        &st,
        &|_: &Connection, _: &str, _: &str, _: i64| None,
        "CNY",
        split,
    )
    .unwrap();
    let rows = all(&conn, &st);
    assert_eq!(rows.len(), 2);
    let projected = rows.iter().find(|r| r.id == created.entry.id).unwrap();
    assert_eq!(projected.kind, RecordKind::Expense);
    assert_eq!(projected.amount, Decimal::from(50));
    assert!(!projected.editable);
    assert!(
        save(
            &mut conn,
            &st,
            Some(&created.entry.id),
            &draft(&st, &bank, RecordKind::Expense, 1)
        )
        .is_err()
    );
    assert_eq!(
        monthly_totals(&conn, "local", 0, 2_000_000_000).unwrap(),
        vec![("CNY".to_owned(), Decimal::ZERO, Decimal::from(60))]
    );

    let adjustment = builders::opening_balance(
        100,
        &bank.id,
        system_accounts::system_account_id("local", "equity:adjustments"),
        Decimal::from(5),
        "CNY",
        Some("同步来的调整"),
        None,
        vec![],
    )
    .unwrap();
    let adjustment = journal::create(
        &mut conn,
        &st,
        &|_: &Connection, _: &str, _: &str, _: i64| None,
        "CNY",
        adjustment,
    )
    .unwrap();
    let other = record(&conn, "local", &adjustment.entry.id).unwrap();
    assert_eq!(other.kind, RecordKind::Other);
    assert!(!other.editable);
    assert_eq!(other.category_name.as_deref(), Some("其他记录 · 首项金额"));
    assert_eq!(all(&conn, &st).len(), 3);
    assert_eq!(
        monthly_totals(&conn, "local", 0, 2_000_000_000).unwrap(),
        vec![("CNY".to_owned(), Decimal::ZERO, Decimal::from(60))]
    );
    delete_record(&mut conn, &st, &adjustment.entry.id).unwrap();
    assert_eq!(balance(&conn, &st, &bank.id), Decimal::from(-60));
}

#[test]
fn split_account_filter_matches_every_custody_leg_and_totals_never_mix_currencies() {
    let (mut conn, st) = setup();
    let cny = account(&conn, &st, "人民币账户", "CNY");
    let usd = account(&conn, &st, "美元账户", "USD");
    let split = compound_build(
        100,
        "多币种分录",
        vec![
            (
                system_accounts::system_account_id("local", "expense:dining"),
                30,
                "CNY",
            ),
            (
                system_accounts::system_account_id("local", "expense:coffee"),
                5,
                "USD",
            ),
            (cny.id.clone(), -30, "CNY"),
            (usd.id.clone(), -5, "USD"),
        ],
    );
    journal::create(
        &mut conn,
        &st,
        &|_: &Connection, _: &str, _: &str, _: i64| None,
        "CNY",
        split,
    )
    .unwrap();
    let filtered = records(
        &conn,
        "local",
        &RecordFilter {
            account_id: Some(usd.id),
            ..Default::default()
        },
        100,
        0,
    )
    .unwrap();
    assert_eq!(filtered.len(), 1);
    assert!(!filtered[0].editable);
    assert_eq!(filtered[0].kind, RecordKind::Other);
    assert_eq!(filtered[0].currency, "CNY");
    assert_eq!(filtered[0].amount, Decimal::from(-30));
    assert!(filtered[0].account_name.contains("人民币账户"));
    assert!(filtered[0].account_name.contains("美元账户"));
    assert_eq!(
        monthly_totals(&conn, "local", 0, 200).unwrap(),
        vec![
            ("CNY".to_owned(), Decimal::ZERO, Decimal::from(30)),
            ("USD".to_owned(), Decimal::ZERO, Decimal::from(5)),
        ]
    );
}

#[test]
fn undo_delete_after_edit_restores_only_current_legs() {
    let (mut conn, st) = setup();
    let bank = account(&conn, &st, "撤销账户", "CNY");
    let mut entry = draft(&st, &bank, RecordKind::Expense, 25);
    let id = save(&mut conn, &st, None, &entry).unwrap();
    entry.amount = Decimal::from(40);
    assert_eq!(save(&mut conn, &st, Some(&id), &entry).unwrap(), id);
    delete_record(&mut conn, &st, &id).unwrap();
    assert_eq!(balance(&conn, &st, &bank.id), Decimal::ZERO);
    let deletion = journal::get(&conn, &id).unwrap().unwrap().entry.sync.hlc;
    restore_record(&mut conn, &st, &id).unwrap();
    assert_eq!(balance(&conn, &st, &bank.id), Decimal::from(-40));
    let restored = journal::get(&conn, &id).unwrap().unwrap();
    assert_eq!(restored.postings.len(), 2);
    assert!(restored.entry.sync.hlc > deletion);
    assert!(
        restored
            .postings
            .iter()
            .all(|p| p.sync.hlc == restored.entry.sync.hlc)
    );
    restore_record(&mut conn, &st, &id).unwrap();
    assert_eq!(balance(&conn, &st, &bank.id), Decimal::from(-40));
}

#[test]
fn undo_delete_rejects_foreign_owner_missing_legs_and_deleted_accounts() {
    let (mut conn, st) = setup();
    let bank = account(&conn, &st, "恢复保护", "CNY");
    let id = save(
        &mut conn,
        &st,
        None,
        &draft(&st, &bank, RecordKind::Expense, 25),
    )
    .unwrap();
    delete_record(&mut conn, &st, &id).unwrap();
    let other = MutationStamper::new("other", "other-device");
    assert!(restore_record(&mut conn, &other, &id).is_err());
    conn.execute(
        r#"UPDATE "fin:accounts" SET deleted_at = 1 WHERE id = ?1"#,
        params![bank.id],
    )
    .unwrap();
    assert!(restore_record(&mut conn, &st, &id).is_err());
    conn.execute(
        r#"UPDATE "fin:accounts" SET deleted_at = NULL WHERE id = ?1"#,
        params![bank.id],
    )
    .unwrap();
    conn.execute(
        r#"DELETE FROM "fin:postings" WHERE journal_entry_id = ?1 AND account_id = ?2"#,
        params![id, bank.id],
    )
    .unwrap();
    let pending = outbox::pending(&conn, 1000).unwrap();
    assert!(restore_record(&mut conn, &st, &id).is_err());
    assert!(
        journal::get(&conn, &id)
            .unwrap()
            .unwrap()
            .entry
            .sync
            .deleted_at
            .is_some()
    );
    assert_eq!(outbox::pending(&conn, 1000).unwrap(), pending);
}

#[test]
fn undo_refuses_structured_wealth_record() {
    let (mut conn, st) = setup();
    let bank = account(&conn, &st, "来源守卫", "CNY");
    let id = save(
        &mut conn,
        &st,
        None,
        &draft(&st, &bank, RecordKind::Expense, 25),
    )
    .unwrap();
    delete_record(&mut conn, &st, &id).unwrap();
    conn.execute(
        r#"UPDATE "fin:journal_entries" SET tag_ids_json = '["wealth:trade"]' WHERE id = ?1"#,
        params![id],
    )
    .unwrap();
    let pending = outbox::pending(&conn, 1000).unwrap();
    assert!(restore_record(&mut conn, &st, &id).is_err());
    assert!(
        journal::get(&conn, &id)
            .unwrap()
            .unwrap()
            .entry
            .sync
            .deleted_at
            .is_some()
    );
    assert_eq!(outbox::pending(&conn, 1000).unwrap(), pending);
}
