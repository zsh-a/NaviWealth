use super::*;
use crate::{
    daily::{self, RecordDraft, RecordFilter, RecordKind},
    models::{AccountCategory, NewAccount},
    repos::{account_repository as accounts, journal_repository as journal},
    system_accounts,
};
use crate::{planning, wealth};
fn date(text: &str) -> i64 {
    chrono::NaiveDate::parse_from_str(text, "%Y-%m-%d")
        .unwrap()
        .and_hms_opt(0, 0, 0)
        .unwrap()
        .and_utc()
        .timestamp()
}
fn setup() -> (Connection, MutationStamper, String, String) {
    let c = Connection::open_in_memory().unwrap();
    for m in [
        lifeos::db::migrations::core_migrations().steps()[0].clone(),
        crate::tables::migration(),
        crate::tables::assets_migration(),
        wealth::migration(),
        planning::migration(),
        migration(),
    ] {
        c.execute_batch(m.sql).unwrap();
    }
    let st = MutationStamper::new("owner", "device");
    system_accounts::seed_system_accounts(&c, &st).unwrap();
    let a = accounts::create(
        &c,
        &st,
        NewAccount::custody(AccountCategory::Bank, "银行", "CNY"),
    )
    .unwrap();
    let category = daily::categories(&c, "owner", RecordKind::Expense).unwrap()[0]
        .0
        .clone();
    (c, st, a.id, category)
}
fn parsed(lines: &str) -> ParsedStatement {
    parse_statement_csv(&format!("{STATEMENT_CSV_HEADER}\n{lines}")).unwrap()
}
fn ready_import(
    c: &mut Connection,
    st: &MutationStamper,
    a: &str,
    category: &str,
    lines: &str,
) -> ImportSession {
    let s = create_import(c, st, "通用CSV", &parsed(lines)).unwrap();
    assign_import_account(c, st, &s.id, a).unwrap();
    for r in import_rows(c, &st.owner_user_id, &s.id).unwrap() {
        let mut d = r.draft.unwrap();
        d.category_id = Some(category.into());
        review_import_row(c, st, &s.id, &r.id, d).unwrap();
    }
    s
}
fn count(c: &Connection, table: &str) -> i64 {
    c.query_row(&format!("SELECT COUNT(*) FROM \"{table}\""), [], |r| {
        r.get(0)
    })
    .unwrap()
}
#[test]
fn csv_validates_headers_dates_decimal_direction_and_quoted_fields() {
    let p=parse_statement_csv(&format!("\u{feff}{STATEMENT_CSV_HEADER}\r\n2026-08-01,0.000001,CNY,expense,\"A, B\",\"two\nlines\"\r\n2026-02-30,1,CNY,expense,x,n\n2026-08-01,-2,CNY,income,x,n\n2026-08-01,1,CNY,transfer,x,n\n2026-08-01,2,cny,expense,x,n\n")).unwrap();
    assert_eq!(p.rows.len(), 5);
    let d = p.rows[0].draft.as_ref().unwrap();
    assert_eq!(
        d.signed_amount,
        Decimal::from_str_exact("-0.000001").unwrap()
    );
    assert_eq!(d.counterparty, "A, B");
    assert_eq!(d.note, "two\nlines");
    assert!(
        p.rows[1..]
            .iter()
            .all(|r| r.draft.is_none() && !r.problems.is_empty())
    );
    assert!(parse_statement_csv("date,amount\n2026-08-01,10").is_err());
    assert!(parse_statement_csv(&format!("{STATEMENT_CSV_HEADER}\n\"not closed")).is_err());
    let exported = export_statement_csv(std::slice::from_ref(d)).unwrap();
    assert_eq!(
        parse_statement_csv(&exported).unwrap().rows[0]
            .draft
            .as_ref(),
        Some(d)
    );
}
#[test]
fn confirmation_requires_source_review_owner_and_same_session() {
    let (mut c, st, a, cat) = setup();
    let s = create_import(&mut c, &st, "CSV", &parsed("2026-08-01,1,CNY,expense,A,N")).unwrap();
    assert!(confirm_import(&mut c, &st, &s.id).is_err());
    let foreign = MutationStamper::new("other", "device2");
    assert!(assign_import_account(&mut c, &foreign, &s.id, &a).is_err());
    let fa = accounts::create(
        &c,
        &foreign,
        NewAccount::custody(AccountCategory::Cash, "外部", "CNY"),
    )
    .unwrap();
    assert!(assign_import_account(&mut c, &st, &s.id, &fa.id).is_err());
    assign_import_account(&mut c, &st, &s.id, &a).unwrap();
    assert!(confirm_import(&mut c, &st, &s.id).is_err());
    let s2 = create_import(&mut c, &st, "CSV2", &parsed("2026-08-02,2,CNY,expense,B,N")).unwrap();
    let r = import_rows(&c, "owner", &s.id).unwrap().remove(0);
    let mut d = r.draft.unwrap();
    d.category_id = Some(cat);
    assert!(review_import_row(&mut c, &st, &s2.id, &r.id, d).is_err());
}
#[test]
fn rejects_can_be_corrected_or_explicitly_skipped() {
    let (mut c, st, a, cat) = setup();
    let s = create_import(
        &mut c,
        &st,
        "CSV",
        &parsed("bad,1,CNY,expense,A,N\n2026-08-01,2,CNY,expense,B,N"),
    )
    .unwrap();
    assign_import_account(&mut c, &st, &s.id, &a).unwrap();
    let rows = import_rows(&c, "owner", &s.id).unwrap();
    assert!(rows[0].draft.is_none());
    exclude_import_row(
        &mut c,
        &st,
        &s.id,
        &rows[0].id,
        "原文件日期无效，回银行核实",
    )
    .unwrap();
    let mut d = rows[1].draft.clone().unwrap();
    d.category_id = Some(cat);
    review_import_row(&mut c, &st, &s.id, &rows[1].id, d).unwrap();
    let result = confirm_import(&mut c, &st, &s.id).unwrap();
    assert_eq!((result.created, result.excluded), (1, 1));
}
#[test]
fn exact_atomic_dedup_confirmation_and_batch_owned_undo() {
    let (mut c, st, a, cat) = setup();
    let s = ready_import(
        &mut c,
        &st,
        &a,
        &cat,
        "2026-08-01,0.10,CNY,expense,Coffee,N\n2026-08-01,0.100,CNY,expense,coffee,N",
    );
    let first = confirm_import(&mut c, &st, &s.id).unwrap();
    assert_eq!((first.created, first.duplicates), (1, 1));
    assert_eq!(confirm_import(&mut c, &st, &s.id).unwrap(), first);
    assert_eq!(
        balance_at(&c, "owner", &a, date("2026-09-01")).unwrap(),
        Decimal::from_str_exact("-0.10").unwrap()
    );
    let s2 = ready_import(
        &mut c,
        &st,
        &a,
        &cat,
        "2026-08-01,0.10,CNY,expense,Coffee,N",
    );
    let second = confirm_import(&mut c, &st, &s2.id).unwrap();
    assert_eq!((second.created, second.duplicates), (0, 1));
    assert_eq!(undo_import(&mut c, &st, &s2.id).unwrap(), 0);
    assert!(daily::record(&c, "owner", &first.entry_ids[0]).is_ok());
    let unrelated = ready_import(&mut c, &st, &a, &cat, "2026-08-02,3,CNY,expense,Other,N");
    let other = confirm_import(&mut c, &st, &unrelated.id).unwrap();
    assert_eq!(undo_import(&mut c, &st, &s.id).unwrap(), 1);
    assert_eq!(undo_import(&mut c, &st, &s.id).unwrap(), 0);
    assert!(daily::record(&c, "owner", &other.entry_ids[0]).is_ok());
    assert_eq!(
        journal::list_owned(&c, "owner", None, None).unwrap().len(),
        1
    );
}
#[test]
fn late_row_failure_rolls_back_journal_session_rows_and_outbox() {
    let (mut c, st, a, cat) = setup();
    let s = ready_import(
        &mut c,
        &st,
        &a,
        &cat,
        "2026-08-01,1,CNY,expense,A,N\n2026-08-02,2,USD,expense,B,N",
    );
    let before = count(&c, "op_outbox");
    assert!(confirm_import(&mut c, &st, &s.id).is_err());
    assert_eq!(count(&c, "op_outbox"), before);
    assert!(
        journal::list_owned(&c, "owner", None, None)
            .unwrap()
            .is_empty()
    );
    assert_eq!(
        import_session(&c, "owner", &s.id).unwrap().status,
        ImportStatus::Review
    );
    assert!(
        import_rows(&c, "owner", &s.id)
            .unwrap()
            .iter()
            .all(|r| r.journal_id.is_none())
    );
}
#[test]
fn undo_refuses_edited_batch_without_touching_any_created_record() {
    let (mut c, st, a, cat) = setup();
    let s = ready_import(
        &mut c,
        &st,
        &a,
        &cat,
        "2026-08-01,1,CNY,expense,A,N\n2026-08-02,2,CNY,expense,B,N",
    );
    let result = confirm_import(&mut c, &st, &s.id).unwrap();
    let r = daily::record(&c, "owner", &result.entry_ids[1]).unwrap();
    daily::save(
        &mut c,
        &st,
        Some(&r.id),
        &RecordDraft {
            kind: r.kind,
            date: r.date,
            amount: Decimal::from(9),
            account_id: a,
            category_id: Some(cat),
            destination_account_id: None,
            destination_amount: None,
            payee: r.payee,
            note: Some("用户已修改".into()),
        },
    )
    .unwrap();
    assert!(undo_import(&mut c, &st, &s.id).is_err());
    assert_eq!(
        journal::list_owned(&c, "owner", None, None).unwrap().len(),
        2
    );
    assert_eq!(
        import_session(&c, "owner", &s.id).unwrap().status,
        ImportStatus::Confirmed
    );
}
#[test]
fn reconciliation_is_balanced_stale_guarded_and_undoable() {
    let (mut c, st, a, _) = setup();
    let r = create_reconciliation(
        &mut c,
        &st,
        &a,
        date("2026-08-31"),
        Decimal::from(10),
        "余额核对",
    )
    .unwrap();
    assert_eq!(r.before, Decimal::ZERO);
    let confirmed = confirm_reconciliation(&mut c, &st, &r.id).unwrap();
    assert_eq!(confirmed.difference, Decimal::from(10));
    let entry = journal::get(&c, confirmed.journal_id.as_ref().unwrap())
        .unwrap()
        .unwrap();
    assert_eq!(
        entry.postings.iter().map(|p| p.units).sum::<Decimal>(),
        Decimal::ZERO
    );
    assert_eq!(
        balance_at(&c, "owner", &a, date("2026-09-01")).unwrap(),
        Decimal::from(10)
    );
    undo_reconciliation(&mut c, &st, &r.id).unwrap();
    assert_eq!(
        balance_at(&c, "owner", &a, date("2026-09-01")).unwrap(),
        Decimal::ZERO
    );
    let stale = create_reconciliation(
        &mut c,
        &st,
        &a,
        date("2026-08-31"),
        Decimal::from(20),
        "银行余额",
    )
    .unwrap();
    let current = create_reconciliation(
        &mut c,
        &st,
        &a,
        date("2026-08-31"),
        Decimal::from(30),
        "新核对",
    )
    .unwrap();
    confirm_reconciliation(&mut c, &st, &current.id).unwrap();
    assert!(confirm_reconciliation(&mut c, &st, &stale.id).is_err());
}
#[test]
fn inbox_notes_do_not_claim_source_problem_resolved() {
    let (mut c, st, _, _) = setup();
    let s = create_import(
        &mut c,
        &st,
        "待处理账单",
        &parsed("2026-08-01,1,CNY,expense,A,N"),
    )
    .unwrap();
    let inbox = financial_inbox(&c, "owner", date("2026-08-31")).unwrap();
    let key = format!("import:{}", s.id);
    assert!(inbox.iter().any(|i| i.key == key && i.blocking));
    note_financial_issue(
        &mut c,
        &st,
        &key,
        IssueDisposition::Resolved,
        "等待银行确认",
        date("2026-08-31"),
    )
    .unwrap();
    let still = financial_inbox(&c, "owner", date("2026-08-31"))
        .unwrap()
        .into_iter()
        .find(|i| i.key == key)
        .unwrap();
    assert!(still.blocking);
    assert!(still.note.is_some());
}
fn review_all(c: &mut Connection, st: &MutationStamper, month: &str) {
    for step in CloseStep::ALL {
        let ready = month_close_readiness(c, "owner", month).unwrap();
        let blocked = !ready
            .steps
            .iter()
            .find(|s| s.step == step)
            .unwrap()
            .blockers
            .is_empty();
        review_month_close_step(
            c,
            st,
            month,
            step,
            "已核对实际来源和计划",
            blocked.then_some("待线下核实，保留未解决事项"),
        )
        .unwrap();
    }
}
#[test]
fn monthly_close_blocks_unreconciled_and_pending_import_and_invalidates_stale_review() {
    let (mut c, st, a, cat) = setup();
    let s = create_import(
        &mut c,
        &st,
        "未确认",
        &parsed("2026-08-01,1,CNY,expense,A,N"),
    )
    .unwrap();
    let readiness = month_close_readiness(&c, "owner", "2026-08").unwrap();
    assert!(!readiness.ready);
    assert_eq!(readiness.steps.len(), 5);
    assert!(
        review_month_close_step(
            &mut c,
            &st,
            "2026-08",
            CloseStep::ImportReview,
            "看过了",
            None
        )
        .is_err()
    );
    assert!(finalize_month_close(&mut c, &st, "2026-08").is_err());
    assign_import_account(&mut c, &st, &s.id, &a).unwrap();
    let row = import_rows(&c, "owner", &s.id).unwrap().remove(0);
    let mut d = row.draft.unwrap();
    d.category_id = Some(cat.clone());
    review_import_row(&mut c, &st, &s.id, &row.id, d).unwrap();
    confirm_import(&mut c, &st, &s.id).unwrap();
    let r = create_reconciliation(&mut c, &st, &a, date("2026-08-31"), -Decimal::ONE, "").unwrap();
    confirm_reconciliation(&mut c, &st, &r.id).unwrap();
    review_all(&mut c, &st, "2026-08");
    assert!(month_close_readiness(&c, "owner", "2026-08").unwrap().ready);
    let new = ready_import(&mut c, &st, &a, &cat, "2026-08-02,2,CNY,expense,B,N");
    confirm_import(&mut c, &st, &new.id).unwrap();
    let changed = month_close_readiness(&c, "owner", "2026-08").unwrap();
    assert!(!changed.ready);
    assert!(
        changed
            .steps
            .iter()
            .find(|s| s.step == CloseStep::AccountReconcile)
            .unwrap()
            .review
            .is_none()
    );
}
#[test]
fn monthly_snapshots_use_real_money_and_previous_saved_comparison() {
    let (mut c, st, a, _) = setup();
    let r = create_reconciliation(
        &mut c,
        &st,
        &a,
        date("2026-08-31"),
        Decimal::from(100),
        "实际银行余额",
    )
    .unwrap();
    confirm_reconciliation(&mut c, &st, &r.id).unwrap();
    review_all(&mut c, &st, "2026-08");
    let august = finalize_month_close(&mut c, &st, "2026-08").unwrap();
    assert_eq!(august.accounts[0].balance, Decimal::from(100));
    assert_eq!(august.net_worth, Some(Decimal::from(100)));
    assert!(august.previous_net_worth.is_none());
    assert!(august.net_worth_change.is_none());
    let r = create_reconciliation(
        &mut c,
        &st,
        &a,
        date("2026-09-30"),
        Decimal::from(125),
        "九月实际余额",
    )
    .unwrap();
    confirm_reconciliation(&mut c, &st, &r.id).unwrap();
    review_all(&mut c, &st, "2026-09");
    let september = finalize_month_close(&mut c, &st, "2026-09").unwrap();
    assert_eq!(september.previous_month.as_deref(), Some("2026-08"));
    assert_eq!(september.net_worth_change, Some(Decimal::from(25)));
    assert_eq!(month_closes(&c, "owner").unwrap().len(), 2);
    assert_eq!(
        daily::records(&c, "owner", &RecordFilter::default(), 200, 0)
            .unwrap()
            .len(),
        2
    );
}

#[test]
fn operation_wire_requires_decimal_strings_and_preserves_subminor_precision() {
    let d = parsed("2026-08-01,0.000001,CNY,expense,A,N")
        .rows
        .remove(0)
        .draft
        .unwrap();
    let mut value = encode(&d).unwrap();
    assert_eq!(value["signed_amount"], "-0.000001");
    value["signed_amount"] = json!(-1);
    assert!(decode::<RowReview>(value).is_err());
}

#[test]
fn preview_exposes_duplicates_without_writing_and_cancellation_clears_draft() {
    let (mut c, st, a, cat) = setup();
    let s = ready_import(
        &mut c,
        &st,
        &a,
        &cat,
        "2026-08-01,1,CNY,expense,Coffee,N\n2026-08-01,1,CNY,expense,Coffee,N",
    );
    let outbox_before = count(&c, "op_outbox");
    let p = preview_import(&c, "owner", &s.id).unwrap();
    assert!(p.can_confirm);
    assert_eq!((p.created, p.duplicates), (1, 1));
    assert!(
        p.rows[1]
            .duplicate_of
            .as_deref()
            .unwrap()
            .starts_with("row:")
    );
    assert_eq!(count(&c, "op_outbox"), outbox_before);
    assert!(
        journal::list_owned(&c, "owner", None, None)
            .unwrap()
            .is_empty()
    );
    cancel_import(&mut c, &st, &s.id).unwrap();
    assert!(
        !financial_inbox(&c, "owner", date("2026-08-31"))
            .unwrap()
            .iter()
            .any(|i| i.kind == IssueKind::ImportReview)
    );
    assert!(confirm_import(&mut c, &st, &s.id).is_err());
}
#[test]
fn income_import_and_storage_failure_preserve_exact_atomic_semantics() {
    let (mut c, st, a, _) = setup();
    let cat = daily::categories(&c, "owner", RecordKind::Income).unwrap()[0]
        .0
        .clone();
    let s = ready_import(
        &mut c,
        &st,
        &a,
        &cat,
        "2026-08-01,7.000001,CNY,income,Salary,N",
    );
    c.execute_batch(r#"CREATE TRIGGER reject_import_confirmation BEFORE UPDATE ON "fin:operations" WHEN NEW.kind='import_session' AND json_extract(NEW.payload_json,'$.status')='Confirmed' BEGIN SELECT RAISE(ABORT,'synthetic persistence failure'); END;"#).unwrap();
    let before = count(&c, "op_outbox");
    assert!(confirm_import(&mut c, &st, &s.id).is_err());
    assert_eq!(count(&c, "op_outbox"), before);
    assert!(
        journal::list_owned(&c, "owner", None, None)
            .unwrap()
            .is_empty()
    );
    assert!(
        import_rows(&c, "owner", &s.id).unwrap()[0]
            .journal_id
            .is_none()
    );
    c.execute_batch("DROP TRIGGER reject_import_confirmation")
        .unwrap();
    let result = confirm_import(&mut c, &st, &s.id).unwrap();
    let record = daily::record(&c, "owner", &result.entry_ids[0]).unwrap();
    assert_eq!(record.kind, RecordKind::Income);
    assert_eq!(record.amount, Decimal::from_str_exact("7.000001").unwrap());
    assert_eq!(
        balance_at(&c, "owner", &a, date("2026-09-01")).unwrap(),
        record.amount
    );
}

#[test]
fn owner_remap_repairs_opaque_operation_keys_without_forging_receipts() {
    let old = "local";
    let new = "signed-in";
    let mut close = json!({"id":format!("month-close:{}",digest(&[old,"2026-08"])),"kind":"month_close","owner_user_id":old,"payload_json":json!({"id":"old-hash","month":"2026-08","steps":[{"source_digest":"historical"}],"snapshot":{"net_worth":"123.000001"}}).to_string()});
    remap_owner_row(&mut close, old, new).unwrap();
    let payload: Value = serde_json::from_str(close["payload_json"].as_str().unwrap()).unwrap();
    assert_eq!(
        close["id"],
        format!("month-close:{}", digest(&[new, "2026-08"]))
    );
    assert_eq!(payload["id"], close["id"]);
    assert_eq!(payload["snapshot"]["net_worth"], "123.000001");
    assert_eq!(payload["steps"][0]["source_digest"], "historical");
    let once = close.clone();
    remap_owner_row(&mut close, old, new).unwrap();
    assert_eq!(close, once);
    let mut note = json!({"id":"old-note-hash","kind":"issue_note","payload_json":json!({"issue_key":"import:stable-session","note":"等待来源核验"}).to_string()});
    remap_owner_row(&mut note, old, new).unwrap();
    assert_eq!(
        note["id"],
        format!("issue-note:{}", digest(&[new, "import:stable-session"]))
    );
    let mut import = json!({"id":"stable-row","kind":"import_row","payload_json":json!({"journal_id":"stable-entry","journal_hlc":"mismatch-must-stay-mismatch","evidence_hash":"historical-owner-fingerprint"}).to_string()});
    let original = import.clone();
    remap_owner_row(&mut import, old, new).unwrap();
    assert_eq!(import, original);
}

#[test]
fn batch_undo_waits_for_all_rows_then_late_receipts_preserve_idempotency() {
    let (mut c, st, a, cat) = setup();
    let s = ready_import(
        &mut c,
        &st,
        &a,
        &cat,
        "2026-08-01,1,CNY,expense,A,N\n2026-08-02,2,CNY,expense,B,N",
    );
    confirm_import(&mut c, &st, &s.id).unwrap();
    let rows = import_rows(&c, "owner", &s.id).unwrap();
    let late = rows[1].clone();
    c.execute(r#"DELETE FROM "fin:operations" WHERE id=?1"#, [&late.id])
        .unwrap();
    let before = count(&c, "op_outbox");
    assert!(!import_undo_readiness(&c, "owner", &s.id).unwrap().can_undo);
    assert!(
        undo_import(&mut c, &st, &s.id)
            .unwrap_err()
            .to_string()
            .contains("回执尚未完整同步")
    );
    assert_eq!(count(&c, "op_outbox"), before);
    assert_eq!(
        import_session(&c, "owner", &s.id).unwrap().status,
        ImportStatus::Confirmed
    );
    assert_eq!(
        journal::list_owned(&c, "owner", None, None).unwrap().len(),
        2
    );
    assert_eq!(
        balance_at(&c, "owner", &a, date("2026-09-01")).unwrap(),
        -Decimal::from(3)
    );
    put(&c, &st, &late.id, "import_row", encode(&late).unwrap()).unwrap();
    assert!(import_undo_readiness(&c, "owner", &s.id).unwrap().can_undo);
    assert_eq!(undo_import(&mut c, &st, &s.id).unwrap(), 2);
    assert_eq!(undo_import(&mut c, &st, &s.id).unwrap(), 0);
    assert_eq!(
        balance_at(&c, "owner", &a, date("2026-09-01")).unwrap(),
        Decimal::ZERO
    );
}
#[test]
fn batch_undo_refuses_stale_row_revision_and_incomplete_or_wrong_entry_set() {
    let (mut c, st, a, cat) = setup();
    let s = ready_import(
        &mut c,
        &st,
        &a,
        &cat,
        "2026-08-01,1,CNY,expense,A,N\n2026-08-02,2,CNY,expense,B,N",
    );
    confirm_import(&mut c, &st, &s.id).unwrap();
    let rows = import_rows(&c, "owner", &s.id).unwrap();
    let original = rows[1].clone();
    let assert_untouched = |c: &mut Connection| {
        let before = count(c, "op_outbox");
        assert!(!import_undo_readiness(c, "owner", &s.id).unwrap().can_undo);
        assert!(undo_import(c, &st, &s.id).is_err());
        assert_eq!(count(c, "op_outbox"), before);
        assert_eq!(
            import_session(c, "owner", &s.id).unwrap().status,
            ImportStatus::Confirmed
        );
        assert_eq!(
            journal::list_owned(c, "owner", None, None).unwrap().len(),
            2
        );
    };
    // The row exists, but sync has only delivered its pre-confirmation revision.
    let mut stale = original.clone();
    stale.journal_id = None;
    stale.journal_hlc = None;
    stale.evidence_hash = None;
    put(&c, &st, &stale.id, "import_row", encode(&stale).unwrap()).unwrap();
    assert_untouched(&mut c);
    // Two row receipts cannot both point at the same created entry.
    let mut wrong = original.clone();
    wrong.journal_id = rows[0].journal_id.clone();
    wrong.journal_hlc = rows[0].journal_hlc.clone();
    put(&c, &st, &wrong.id, "import_row", encode(&wrong).unwrap()).unwrap();
    assert_untouched(&mut c);
    put(
        &c,
        &st,
        &original.id,
        "import_row",
        encode(&original).unwrap(),
    )
    .unwrap();
    let original_session = import_session(&c, "owner", &s.id).unwrap();
    let mut partial_session = original_session.clone();
    partial_session
        .confirmation
        .as_mut()
        .unwrap()
        .entry_ids
        .pop();
    put(
        &c,
        &st,
        &s.id,
        "import_session",
        encode(&partial_session).unwrap(),
    )
    .unwrap();
    assert_untouched(&mut c);
    put(
        &c,
        &st,
        &s.id,
        "import_session",
        encode(&original_session).unwrap(),
    )
    .unwrap();
    assert_eq!(undo_import(&mut c, &st, &s.id).unwrap(), 2);
    assert_eq!(undo_import(&mut c, &st, &s.id).unwrap(), 0);
}

#[test]
fn batch_undo_waits_for_matching_posting_and_journal_revisions() {
    let (mut c, st, a, cat) = setup();
    let s = ready_import(&mut c, &st, &a, &cat, "2026-08-01,1,CNY,expense,A,N");
    let receipt = confirm_import(&mut c, &st, &s.id).unwrap();
    let id = &receipt.entry_ids[0];
    let original = journal::get(&c, id).unwrap().unwrap();
    // Simulate sync delivering the replacement posting pair and old-posting
    // tombstones before the new journal head. Count and owner alone still match.
    let new_stamp = st.stamp(&c).unwrap();
    c.execute(
        r#"UPDATE "fin:postings" SET hlc=?1 WHERE journal_entry_id=?2 AND deleted_at IS NULL"#,
        params![new_stamp.hlc, id],
    )
    .unwrap();
    let before = count(&c, "op_outbox");
    assert!(!import_undo_readiness(&c, "owner", &s.id).unwrap().can_undo);
    assert!(
        undo_import(&mut c, &st, &s.id)
            .unwrap_err()
            .to_string()
            .contains("回执尚未完整同步")
    );
    assert_eq!(count(&c, "op_outbox"), before);
    assert_eq!(
        import_session(&c, "owner", &s.id).unwrap().status,
        ImportStatus::Confirmed
    );
    assert!(
        journal::get(&c, id)
            .unwrap()
            .unwrap()
            .entry
            .sync
            .deleted_at
            .is_none()
    );
    // Once the later edited journal head arrives, its HLC no longer matches
    // the import receipt: this remains a user edit and cannot be batch-undone.
    c.execute(
        r#"UPDATE "fin:journal_entries" SET hlc=?1 WHERE id=?2"#,
        params![new_stamp.hlc, id],
    )
    .unwrap();
    assert!(
        undo_import(&mut c, &st, &s.id)
            .unwrap_err()
            .to_string()
            .contains("已被修改")
    );
    assert_eq!(
        import_session(&c, "owner", &s.id).unwrap().status,
        ImportStatus::Confirmed
    );
    // Restoring the original consistent source pair permits normal idempotent undo.
    c.execute(
        r#"UPDATE "fin:journal_entries" SET hlc=?1 WHERE id=?2"#,
        params![original.entry.sync.hlc, id],
    )
    .unwrap();
    c.execute(
        r#"UPDATE "fin:postings" SET hlc=?1 WHERE journal_entry_id=?2 AND deleted_at IS NULL"#,
        params![original.entry.sync.hlc, id],
    )
    .unwrap();
    assert_eq!(undo_import(&mut c, &st, &s.id).unwrap(), 1);
    assert_eq!(undo_import(&mut c, &st, &s.id).unwrap(), 0);
}
