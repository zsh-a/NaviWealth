use super::*;
use crate::state::Services;
use naviwealth_finance::models::{AccountCategory, NewAccount};
use nsh_engine::{EngineConfig, Root};
use nsh_testing::Headless;
fn harness(path: impl Into<String>) -> AnyElement {
    crate::enable_test_mode();
    provide_context(Services::shared());
    provide_context(crate::state::DataVersion(signal(0)));
    let routes = signal(vec![path.into()]);
    provide_context(fui::Navigation(routes));
    provide_context(fui::Feedback(signal(String::new())));
    dynamic(move || {
        super::render(
            routes
                .get()
                .last()
                .cloned()
                .unwrap_or_else(|| "/activity/import".into()),
        )
    })
    .into_element()
}
#[component]
fn ImportHarness() -> impl IntoElement {
    harness("/activity/import/new")
}
#[component]
fn ReconciliationHarness() -> impl IntoElement {
    harness("/activity/reconcile/new")
}
#[component]
fn CloseHarness() -> impl IntoElement {
    harness("/activity/close/2026-08")
}
fn service() -> std::sync::Arc<Services> {
    crate::enable_test_mode();
    Services::shared()
}
fn account(name: &str) -> String {
    let s = service();
    s.runtime
        .block_on(s.create_account(
            NewAccount::custody(AccountCategory::Bank, name, "CNY"),
            None,
        ))
        .unwrap()
        .id
}
fn pick(app: &mut Headless, field: &str, value: &str) {
    app.wait_for(&format!("id:{field}")).unwrap();
    app.press(&format!("id:{field}")).unwrap();
    app.wait_for(&format!("id:{field}-{value}")).unwrap();
    app.press(&format!("id:{field}-{value}")).unwrap();
}
fn exact_balance(id: &str) -> Decimal {
    let s = service();
    s.runtime
        .block_on(s.finance_accounts(true))
        .unwrap()
        .into_iter()
        .find(|(a, _)| a.id == id)
        .unwrap()
        .1
        .and_then(|b| b.legs.into_iter().find(|(u, _)| u == "CNY"))
        .map(|(_, a)| a)
        .unwrap_or_default()
}
#[test]
fn ui_import_review_duplicate_preview_commit_and_batch_undo() {
    let account = account("导入UI证据账户");
    let source = format!("UI导入-{}", uuid::Uuid::new_v4());
    let mut app = Headless::start(EngineConfig::new(Root::of::<ImportHarness>())).unwrap();
    app.wait_for("id:import-paste").unwrap();
    app.press("id:import-paste").unwrap();
    app.wait_for("id:import-source").unwrap();
    app.type_text("id:import-source", &source).unwrap();
    app.clear("id:import-csv").unwrap();
    app.type_text("id:import-csv",&format!("{STATEMENT_CSV_HEADER}\n2026-08-01,12.50,CNY,expense,UI Coffee,N\n2026-08-01,12.50,CNY,expense,UI Coffee,N")).unwrap();
    app.press("id:finance-form-save").unwrap();
    app.wait_for("id:import-account").unwrap();
    let s = service();
    let session = s
        .runtime
        .block_on(s.finance_imports())
        .unwrap()
        .into_iter()
        .find(|i| i.source_name == source)
        .unwrap();
    app.press("id:import-account").unwrap();
    pick(&mut app, "import-source-account", &account);
    app.press("id:finance-form-save").unwrap();
    app.wait_for("id:import-preview").unwrap();
    let rows = s
        .runtime
        .block_on(s.finance_import_rows(session.id.clone()))
        .unwrap();
    let category = s
        .runtime
        .block_on(s.finance_categories(crate::finance::RecordKind::Expense))
        .unwrap()[0]
        .0
        .clone();
    for row in rows {
        app.press(&format!("id:import-row-{}", row.id)).unwrap();
        app.wait_for("id:import-correct-row").unwrap();
        app.press("id:import-correct-row").unwrap();
        pick(&mut app, "import-expense-category", &category);
        app.press("id:finance-form-save").unwrap();
        app.wait_for("id:import-preview").unwrap();
    }
    assert_eq!(exact_balance(&account), Decimal::ZERO);
    app.press("id:import-preview").unwrap();
    app.wait_for("text:1 笔").unwrap();
    app.wait_for("text:重复 1 行 · 明确排除 0 行").unwrap();
    assert_eq!(exact_balance(&account), Decimal::ZERO);
    app.press("id:import-confirm").unwrap();
    app.wait_for("id:import-undo").unwrap();
    assert_eq!(
        exact_balance(&account),
        Decimal::from_str_exact("-12.50").unwrap()
    );
    app.press("id:import-undo").unwrap();
    app.wait_for("id:import-undo-confirm").unwrap();
    app.press("id:import-undo-confirm").unwrap();
    app.wait_for("text:已撤销").unwrap();
    assert_eq!(exact_balance(&account), Decimal::ZERO);
}
#[test]
fn ui_reconciliation_preview_confirm_and_undo_actual_balance() {
    let account = account("对账UI证据账户");
    let mut app = Headless::start(EngineConfig::new(Root::of::<ReconciliationHarness>())).unwrap();
    pick(&mut app, "reconcile-account", &account);
    app.type_text("id:reconcile-actual", "25.50").unwrap();
    app.type_text("id:reconcile-note", "已核对银行实际余额")
        .unwrap();
    app.press("id:finance-form-save").unwrap();
    app.wait_for("id:reconcile-confirm").unwrap();
    assert_eq!(exact_balance(&account), Decimal::ZERO);
    app.press("id:reconcile-confirm").unwrap();
    app.wait_for("id:reconcile-undo").unwrap();
    assert_eq!(
        exact_balance(&account),
        Decimal::from_str_exact("25.50").unwrap()
    );
    app.press("id:reconcile-undo").unwrap();
    app.wait_for("id:reconcile-undo-confirm").unwrap();
    app.press("id:reconcile-undo-confirm").unwrap();
    app.wait_for("text:此对账已撤销。需要时可重新建立实际余额预览。")
        .unwrap();
    assert_eq!(exact_balance(&account), Decimal::ZERO);
}
#[test]
fn ui_month_close_exposes_five_real_steps_and_blocked_evidence() {
    let _ = account("月结UI证据账户");
    let mut app = Headless::start(EngineConfig::new(Root::of::<CloseHarness>())).unwrap();
    for key in ["import", "inbox", "accounts", "runway", "actions"] {
        app.wait_for(&format!("id:close-step-{key}")).unwrap();
    }
    app.press("id:close-step-accounts").unwrap();
    app.wait_for("text:需要核对月末实际余额").unwrap();
    app.wait_for("id:close-review-step").unwrap();
    app.press("id:close-review-step").unwrap();
    app.wait_for("id:close-review-note").unwrap();
    app.type_text("id:close-review-note", "尚待银行月末账单")
        .unwrap();
    app.press("id:finance-form-save").unwrap();
    app.wait_for("text:此步骤存在真实阻塞，请先处理，或明确填写覆盖原因")
        .unwrap();
    let s = service();
    let ready = s
        .runtime
        .block_on(s.finance_month_close_readiness("2026-08".into()))
        .unwrap();
    assert!(!ready.ready);
    assert!(ready.saved_snapshot.is_none());
}

static PARTIAL_SESSION: std::sync::Mutex<Option<String>> = std::sync::Mutex::new(None);
#[component]
fn PartialImportHarness() -> impl IntoElement {
    harness(format!(
        "/activity/import/{}",
        PARTIAL_SESSION.lock().unwrap().as_ref().unwrap()
    ))
}
#[test]
fn ui_partial_sync_receipt_offers_refresh_before_any_batch_undo() {
    let id = account("部分同步批次UI账户");
    let s = service();
    let source = format!("UI部分同步-{}", uuid::Uuid::new_v4());
    let batch = s
        .runtime
        .block_on(s.finance_import_csv(
            source,
            format!(
                "{STATEMENT_CSV_HEADER}\n2026-08-01,1,CNY,expense,A,N\n2026-08-02,2,CNY,expense,B,N"
            ),
        ))
        .unwrap();
    s.runtime
        .block_on(s.finance_assign_import_account(batch.id.clone(), id.clone()))
        .unwrap();
    let category = s
        .runtime
        .block_on(s.finance_categories(crate::finance::RecordKind::Expense))
        .unwrap()[0]
        .0
        .clone();
    for row in s
        .runtime
        .block_on(s.finance_import_rows(batch.id.clone()))
        .unwrap()
    {
        let mut d = row.draft.unwrap();
        d.category_id = Some(category.clone());
        s.runtime
            .block_on(s.finance_review_import_row(batch.id.clone(), row.id, d))
            .unwrap();
    }
    s.runtime
        .block_on(s.finance_confirm_import(batch.id.clone()))
        .unwrap();
    let late = s
        .runtime
        .block_on(s.finance_import_rows(batch.id.clone()))
        .unwrap()
        .remove(1);
    let late_id = late.id.clone();
    let late_payload = serde_json::to_string(&late).unwrap();
    s.runtime
        .block_on(s.db.call(move |c| {
            c.execute(r#"DELETE FROM "fin:operations" WHERE id=?1"#, [late.id])?;
            Ok(())
        }))
        .unwrap();
    *PARTIAL_SESSION.lock().unwrap() = Some(batch.id.clone());
    let mut app = Headless::start(EngineConfig::new(Root::of::<PartialImportHarness>())).unwrap();
    app.wait_for("id:import-undo-retry").unwrap();
    app.wait_for(
        "text:批次确认回执尚未完整同步，暂不能撤销。请等待同步完成后刷新；未撤销任何流水。",
    )
    .unwrap();
    app.wait_for_gone("id:import-undo", std::time::Duration::from_secs(1))
        .unwrap();
    assert_eq!(exact_balance(&id), -Decimal::from(3));
    assert_eq!(
        s.runtime
            .block_on(s.finance_imports())
            .unwrap()
            .into_iter()
            .find(|b| b.id == batch.id)
            .unwrap()
            .status,
        ImportStatus::Confirmed
    );
    // The missing confirmed row then arrives. Refresh rechecks the complete
    // receipt and enables undo without having touched money during the gap.
    let stamp = s.stamper();
    s.runtime.block_on(s.db.call(move|c|{let meta=stamp.stamp(c)?;c.execute(r#"INSERT INTO "fin:operations"(id,kind,payload_json,owner_user_id,updated_at,updated_by_device,hlc) VALUES(?1,'import_row',?2,?3,?4,?5,?6)"#,rusqlite::params![late_id,late_payload,meta.owner_user_id,meta.now.div_euclid(1000),meta.device_id,meta.hlc])?;Ok(())})).unwrap();
    app.press("id:import-undo-retry").unwrap();
    app.wait_for("id:import-undo").unwrap();
    app.press("id:import-undo").unwrap();
    app.wait_for("id:import-undo-confirm").unwrap();
    app.press("id:import-undo-confirm").unwrap();
    app.wait_for("text:已撤销").unwrap();
    assert_eq!(exact_balance(&id), Decimal::ZERO);
}
