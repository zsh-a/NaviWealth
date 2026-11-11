//! Headless UI tests: the real engine (nsh-testing) drives the app with
//! an in-memory database and the mock AI provider. These cover the phase
//! 1/2 acceptance flows that do not need a physical device.

use nsh_engine::{EngineConfig, Root};
use nsh_testing::Headless;

fn app() -> Headless {
    naviwealth_client::enable_test_mode();
    let config = EngineConfig::new(Root::of::<naviwealth_client::App>());
    let mut app = Headless::start(config).expect("headless app starts");
    app.wait_for("id:tab-accounts").unwrap();
    go_tab(&mut app, "tab-accounts");
    app
}

fn root(app: &mut Headless) {
    for _ in 0..12 {
        let back = if app.screen().matches("id:account-list-back").unwrap() {
            Some("id:account-list-back")
        } else if app.screen().matches("id:finance-back").unwrap() {
            Some("id:finance-back")
        } else {
            None
        };
        let Some(back) = back else { return };
        app.press(back).unwrap();
        app.wait(std::time::Duration::from_millis(50)).unwrap();
    }
    panic!("route stack did not return to the Finance tabs");
}
fn go_tab(app: &mut Headless, id: &str) {
    root(app);
    app.wait_for(&format!("id:{id}")).unwrap();
    app.press(&format!("id:{id}")).unwrap();
    if id == "tab-accounts" {
        app.wait_for("id:wealth-accounts").unwrap();
        app.press("id:wealth-accounts").unwrap();
        app.wait_for("id:open-account-form").unwrap();
    }
}
fn open_global(app: &mut Headless, id: &str) {
    root(app);
    app.wait_for(&format!("id:{id}")).unwrap();
    app.press(&format!("id:{id}")).unwrap();
}

#[test]
fn account_list_seeds_and_shells_render() {
    let mut app = app();
    // The shell renders with the four tabs.
    go_tab(&mut app, "tab-ledger");
    app.wait_for("text:流水").unwrap();
    open_global(&mut app, "tab-settings");
    app.wait_for("text:同步与账户").unwrap();
}

#[test]
fn create_account_and_record_expense() {
    let mut app = app();
    app.wait_for("id:open-account-form").unwrap();

    // Create a cash account with an opening balance.
    app.press("id:open-account-form").unwrap();
    app.type_text("id:account-name", "测试现金").unwrap();
    app.type_text("id:account-opening", "1000").unwrap();
    app.press("id:account-save").unwrap();
    app.wait_for("text:测试现金").unwrap();
    app.wait_for("text:1000.00 CNY").unwrap();

    // Record an expense against it (category/account auto-pick the first
    // chip: 餐饮 + 测试现金).
    app.press("id:open-record").unwrap();
    app.type_text("id:record-amount", "12.5").unwrap();
    // Wait for the pickers to load before saving.
    app.wait_for("id:record-category").unwrap();
    app.press("id:record-save").unwrap();

    // The ledger shows the new entry (the legs render as
    // "<account>  <units> <unit>" texts).
    go_tab(&mut app, "tab-ledger");
    app.wait_for("text:餐饮").unwrap();
    app.wait_for("text:-12.50").unwrap();
}

#[test]
fn mock_ai_streams_a_reply() {
    let mut app = app();
    open_global(&mut app, "tab-chat");
    app.wait_for("id:chat-input").unwrap();
    app.type_text("id:chat-input", "你好").unwrap();
    app.press("id:chat-send").unwrap();
    app.wait_for("text:已连接模拟模型（开发模式）。真实模型请在设置中配置自己的 API Key。")
        .unwrap();
}

#[test]
fn enable_knowledge_from_settings_and_create_note() {
    let mut app = app();
    // Knowledge starts off: no 笔记 tab yet.
    open_global(&mut app, "tab-settings");
    app.wait_for("text:领域").unwrap();
    app.wait_for("id:domain-toggle-knowledge").unwrap();

    // Flip the switch: the tab appears, the switch reads 已启用.
    app.press("id:domain-toggle-knowledge").unwrap();
    app.wait_for("text:已启用").unwrap();
    // Optional domains live in the workspace picker, while Finance keeps four tabs.
    root(&mut app);
    app.press("id:domain-switcher").unwrap();
    app.wait_for("id:domain-knowledge").unwrap();
    app.press("id:domain-knowledge").unwrap();
    app.wait_for("id:open-note-form").unwrap();
    app.press("id:open-note-form").unwrap();
    app.type_text("id:note-title", "第一篇笔记").unwrap();
    app.type_text("id:note-content", "nsh 客户端第一条笔记")
        .unwrap();
    app.press("id:note-save").unwrap();

    // The note is visible in the list.
    app.wait_for("text:第一篇笔记").unwrap();
    app.wait_for("text:nsh 客户端第一条笔记").unwrap();
}

/// The scripted mock marker turns the user text into a real
/// finance_record_expense tool call, so the confirmation loop runs end to
/// end: card appears → 批准 → the entry lands in the ledger.
#[test]
fn ai_write_confirm_flow_approve_lands_in_ledger() {
    let mut app = app();

    // Create the funding account first (unique name for this test).
    app.wait_for("id:open-account-form").unwrap();
    app.press("id:open-account-form").unwrap();
    app.type_text("id:account-name", "AI确认账户").unwrap();
    app.type_text("id:account-opening", "500").unwrap();
    app.press("id:account-save").unwrap();
    app.wait_for("text:AI确认账户").unwrap();

    // The scripted marker makes the mock model call the write tool.
    open_global(&mut app, "tab-chat");
    app.wait_for("id:chat-input").unwrap();
    app.type_text("id:chat-input", "记一笔：9.9|dining|AI确认账户")
        .unwrap();
    app.press("id:chat-send").unwrap();

    // The confirmation card renders the write summary with both actions.
    app.wait_for("text:AI 写入请求 · finance_record_expense")
        .unwrap();
    app.wait_for("id:confirm-approve-0").unwrap();
    app.wait_for("id:confirm-deny-0").unwrap();

    // Approve: the card reports the write, the ledger shows the entry.
    app.press("id:confirm-approve-0").unwrap();
    app.wait_for_within(
        "text:已写入支出 9.9 CNY（餐饮，AI确认账户）",
        std::time::Duration::from_secs(5),
    )
    .unwrap();

    go_tab(&mut app, "tab-ledger");
    app.wait_for("text:-9.90").unwrap();
    app.wait_for("text:AI确认账户").unwrap();
}

/// Denying a pending write keeps the database untouched: the card shows
/// the rejection and no ledger line appears for that amount.
#[test]
fn ai_write_confirm_flow_deny_keeps_ledger_untouched() {
    let mut app = app();

    app.wait_for("id:open-account-form").unwrap();
    app.press("id:open-account-form").unwrap();
    app.type_text("id:account-name", "AI拒绝账户").unwrap();
    app.type_text("id:account-opening", "300").unwrap();
    app.press("id:account-save").unwrap();
    app.wait_for("text:AI拒绝账户").unwrap();

    open_global(&mut app, "tab-chat");
    app.wait_for("id:chat-input").unwrap();
    app.type_text("id:chat-input", "记一笔：7.7|dining|AI拒绝账户")
        .unwrap();
    app.press("id:chat-send").unwrap();
    app.wait_for("text:AI 写入请求 · finance_record_expense")
        .unwrap();
    app.wait_for("id:confirm-deny-0").unwrap();

    // Reject: the card flips to the rejected state.
    app.press("id:confirm-deny-0").unwrap();
    app.wait_for("text:已拒绝，未写入任何数据").unwrap();

    // Nothing was written: no ledger line for the denied amount.
    go_tab(&mut app, "tab-ledger");
    app.wait_for_gone(
        "text:AI拒绝账户  7.7 CNY",
        std::time::Duration::from_secs(2),
    )
    .unwrap();
}

/// The chat keeps a multi-turn history: a second send produces a fresh
/// turn (its scripted tool call opens a new confirm card), and 清空会话
/// drops bubbles and cards (plus the persisted session).
#[test]
fn chat_history_multi_turn_and_clear() {
    let mut app = app();

    // The second turn's scripted write needs an account to exist.
    app.wait_for("id:open-account-form").unwrap();
    app.press("id:open-account-form").unwrap();
    app.type_text("id:account-name", "AI历史账户").unwrap();
    app.press("id:account-save").unwrap();
    app.wait_for("text:AI历史账户").unwrap();

    open_global(&mut app, "tab-chat");
    app.wait_for("id:chat-input").unwrap();

    // Turn 1: a plain mock reply.
    app.type_text("id:chat-input", "第一轮").unwrap();
    app.press("id:chat-send").unwrap();
    app.wait_for("text:已连接模拟模型（开发模式）。真实模型请在设置中配置自己的 API Key。")
        .unwrap();

    // Turn 2 (after the first turn settled): the scripted marker makes
    // the mock model call the write tool again — a new card, a new turn.
    app.wait(std::time::Duration::from_millis(300)).unwrap();
    app.type_text("id:chat-input", "记一笔：3.3|dining|AI历史账户")
        .unwrap();
    app.press("id:chat-send").unwrap();
    app.wait_for("text:AI 写入请求 · finance_record_expense")
        .unwrap();
    app.wait_for("id:confirm-approve-0").unwrap();
    app.wait_for("text:第一轮").unwrap();

    // 清空会话 drops bubbles and the pending card (nothing was written).
    app.press("id:chat-clear").unwrap();
    app.wait_for_gone("text:第一轮", std::time::Duration::from_secs(3))
        .unwrap();
    app.wait_for_gone(
        "text:AI 写入请求 · finance_record_expense",
        std::time::Duration::from_secs(3),
    )
    .unwrap();
    go_tab(&mut app, "tab-ledger");
    app.wait_for_gone(
        "text:AI历史账户  3.3 CNY",
        std::time::Duration::from_secs(2),
    )
    .unwrap();
}

fn service() -> std::sync::Arc<naviwealth_client::Services> {
    naviwealth_client::Services::shared()
}
fn account_id(name: &str) -> String {
    let s = service();
    s.runtime
        .block_on(s.account_by_id_or_name(name))
        .unwrap()
        .unwrap()
        .id
}
fn make_account(app: &mut Headless, name: &str, opening: &str) -> String {
    go_tab(app, "tab-accounts");
    app.press("id:open-account-form").unwrap();
    app.type_text("id:account-name", name).unwrap();
    if !opening.is_empty() {
        app.type_text("id:account-opening", opening).unwrap();
    }
    app.press("id:account-save").unwrap();
    app.wait_for(&format!("text:{name}")).unwrap();
    account_id(name)
}
fn pick_account(app: &mut Headless, field: &str, id: &str) {
    app.press(&format!("id:{field}")).unwrap();
    let option = format!("id:{field}-{id}");
    app.wait_for(&option).unwrap();
    app.press(&option).unwrap();
}
fn capture(
    app: &mut Headless,
    kind: &str,
    amount: &str,
    account: &str,
    destination: Option<&str>,
    note: &str,
) {
    app.press("id:open-record").unwrap();
    pick_account(app, "record-account", account);
    app.press(&format!("id:record-kind-{kind}")).unwrap();
    if kind == "收入" {
        app.wait_for("text:工资薪酬").unwrap();
    }
    if kind == "支出" {
        app.wait_for("text:餐饮").unwrap();
    }
    if let Some(destination) = destination {
        pick_account(app, "record-destination", destination);
    }
    app.type_text("id:record-amount", amount).unwrap();
    app.type_text("id:record-note", note).unwrap();
    app.press("id:record-save").unwrap();
    app.wait_for_gone("id:record-save", std::time::Duration::from_secs(5))
        .unwrap();
}
fn exact_balance(id: &str) -> rust_decimal::Decimal {
    let s = service();
    s.runtime
        .block_on(s.finance_accounts(true))
        .unwrap()
        .into_iter()
        .find(|(a, _)| a.id == id)
        .unwrap()
        .1
        .and_then(|b| b.primary().cloned())
        .map(|(_, v)| v)
        .unwrap_or_default()
}

#[test]
fn finance_daily_loop_create_income_expense_transfer_edit_delete_archive() {
    let mut app = app();
    let source = make_account(&mut app, "闭环主账户", "1000");
    let destination = make_account(&mut app, "闭环储蓄账户", "");
    capture(&mut app, "收入", "200", &source, None, "UI闭环收入");
    capture(&mut app, "支出", "50", &source, None, "UI闭环支出");
    capture(
        &mut app,
        "转账",
        "100",
        &source,
        Some(&destination),
        "UI闭环转账",
    );
    assert_eq!(exact_balance(&source), "1050".parse().unwrap());
    assert_eq!(exact_balance(&destination), "100".parse().unwrap());
    let s = service();
    let record = s
        .runtime
        .block_on(s.finance_records(
            naviwealth_client::finance::RecordFilter {
                query: "UI闭环支出".to_owned(),
                ..Default::default()
            },
            10,
            0,
        ))
        .unwrap()
        .remove(0);
    go_tab(&mut app, "tab-ledger");
    app.type_text("id:ledger-search", "UI闭环支出").unwrap();
    app.wait_for(&format!("id:record-{}", record.id)).unwrap();
    app.press(&format!("id:record-{}", record.id)).unwrap();
    app.wait_for("text:UI闭环支出").unwrap();
    app.press("id:record-edit").unwrap();
    app.wait_for("id:record-ready").unwrap();
    app.clear("id:record-amount").unwrap();
    app.type_text("id:record-amount", "75").unwrap();
    app.press("id:record-save").unwrap();
    app.wait_for("text:-75.00").unwrap();
    assert_eq!(exact_balance(&source), "1025".parse().unwrap());
    app.press(&format!("id:record-{}", record.id)).unwrap();
    app.press("id:record-delete").unwrap();
    app.wait_for("text:删除这笔记录？").unwrap();
    app.press("id:record-delete-cancel").unwrap();
    assert_eq!(exact_balance(&source), "1025".parse().unwrap());
    app.press("id:record-delete").unwrap();
    app.press("id:record-delete-confirm").unwrap();
    app.wait_for_gone(
        &format!("id:record-{}", record.id),
        std::time::Duration::from_secs(5),
    )
    .unwrap();
    assert_eq!(exact_balance(&source), "1100".parse().unwrap());
    go_tab(&mut app, "tab-accounts");
    app.press(&format!("id:account-{source}")).unwrap();
    app.press("id:account-archive").unwrap();
    app.wait_for_gone(
        &format!("id:account-{source}"),
        std::time::Duration::from_secs(5),
    )
    .unwrap();
    app.press("id:accounts-show-archived").unwrap();
    app.wait_for(&format!("id:account-{source}")).unwrap();
    app.press(&format!("id:account-{source}")).unwrap();
    app.press("id:account-restore").unwrap();
    app.wait_for("text:账户已恢复").unwrap();
    assert_eq!(exact_balance(&source), "1100".parse().unwrap());
}

#[test]
fn dirty_record_can_be_kept_or_discarded_with_calendar_and_amount_validation() {
    let mut app = app();
    let source = make_account(&mut app, "草稿校验账户", "");
    app.press("id:open-record").unwrap();
    pick_account(&mut app, "record-account", &source);
    app.type_text("id:record-amount", "0").unwrap();
    app.press("id:record-save").unwrap();
    app.wait_for("text:请输入有效金额，收入、支出和转账金额须大于 0")
        .unwrap();
    app.clear("id:record-amount").unwrap();
    app.type_text("id:record-amount", "123").unwrap();
    app.press("id:record-date").unwrap();
    let date = chrono::Local::now().format("%Y-%m-01").to_string();
    app.wait_for(&format!("label:{date}")).unwrap();
    app.press(&format!("label:{date}")).unwrap();
    app.wait_for(&format!("text:{date}")).unwrap();
    app.press("id:record-cancel").unwrap();
    app.wait_for("text:放弃未保存的修改？").unwrap();
    app.press("id:record-keep").unwrap();
    app.wait_for("id:record-amount").unwrap();
    app.press("id:record-cancel").unwrap();
    app.press("id:record-discard").unwrap();
    app.wait_for_gone("id:record-save", std::time::Duration::from_secs(5))
        .unwrap();
    assert_eq!(exact_balance(&source), rust_decimal::Decimal::ZERO);
}
