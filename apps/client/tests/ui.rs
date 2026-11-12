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
    if matches!(id, "tab-chat" | "tab-settings") {
        app.press("id:workspace-more").unwrap();
    }
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
    if matches!(id, "tab-chat" | "tab-settings") {
        app.press("id:workspace-more").unwrap();
    }
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
    app.wait_for("text:1,000.00 CNY").unwrap();

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

#[path = "ui/secondary_flows.rs"]
mod secondary_flows;

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
    app.press("id:ledger-search-toggle").unwrap();
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
    let short_date = chrono::NaiveDate::parse_from_str(&date, "%Y-%m-%d")
        .unwrap()
        .format("%-m月%-d日")
        .to_string();
    let short_date = if date == chrono::Local::now().format("%Y-%m-%d").to_string() {
        format!("今天 · {short_date}")
    } else {
        short_date
    };
    app.wait_for(&format!("text:{short_date}")).unwrap();
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

#[test]
fn undo_created_record_survives_tab_switch_and_updates_balance() {
    let mut app = app();
    let source = make_account(&mut app, "跨页撤销账户", "100");
    go_tab(&mut app, "tab-ledger");
    capture(&mut app, "支出", "12", &source, None, "撤销测试");
    assert_eq!(exact_balance(&source), "88".parse().unwrap());
    go_tab(&mut app, "tab-accounts");
    root(&mut app);
    app.wait_for("id:finance-undo-action").unwrap();
    app.press("id:finance-undo-action").unwrap();
    app.wait_for_gone("id:finance-undo-action", std::time::Duration::from_secs(5))
        .unwrap();
    assert_eq!(exact_balance(&source), "100".parse().unwrap());
    let services = service();
    assert!(
        services
            .runtime
            .block_on(services.finance_records(
                naviwealth_client::finance::RecordFilter {
                    query: "撤销测试".into(),
                    account_id: Some(source),
                    ..Default::default()
                },
                10,
                0
            ))
            .unwrap()
            .is_empty()
    );
}

#[test]
fn today_capture_stays_in_place_with_receipt_and_delete_undo() {
    let mut app = app();
    let source = make_account(&mut app, "今日就地账户", "100");
    go_tab(&mut app, "tab-today");
    capture(&mut app, "支出", "13", &source, None, "今日就地回执");
    let services = service();
    let record = services
        .runtime
        .block_on(services.finance_records(
            naviwealth_client::finance::RecordFilter {
                query: "今日就地回执".into(),
                ..Default::default()
            },
            10,
            0,
        ))
        .unwrap()
        .remove(0);
    app.wait_for(&format!("id:today-record-{}", record.id))
        .unwrap();
    app.wait_for("id:finance-changed-fact").unwrap();
    app.wait_for(&format!("id:record-highlight-{}", record.id))
        .unwrap();
    app.press(&format!("id:today-record-{}", record.id))
        .unwrap();
    app.wait_for("id:entry-delete").unwrap();
    app.press("id:entry-delete").unwrap();
    app.wait_for("id:finance-confirm-submit").unwrap();
    app.press("id:finance-confirm-submit").unwrap();
    app.wait_for("id:finance-undo-action").unwrap();
    assert_eq!(exact_balance(&source), "100".parse().unwrap());
    app.press("id:finance-undo-action").unwrap();
    app.wait_for_gone("id:finance-undo-action", std::time::Duration::from_secs(5))
        .unwrap();
    assert_eq!(exact_balance(&source), "87".parse().unwrap());
    assert!(
        services
            .runtime
            .block_on(services.finance_record(&record.id))
            .is_ok()
    );
}

#[test]
fn category_selection_is_announced_and_enter_submits() {
    let mut app = app();
    let source = make_account(&mut app, "键盘分类账户", "100");
    go_tab(&mut app, "tab-ledger");
    app.press("id:open-record").unwrap();
    app.wait_for("id:record-ready").unwrap();
    pick_account(&mut app, "record-account", &source);
    let services = service();
    let categories = services
        .runtime
        .block_on(services.finance_categories(naviwealth_client::finance::RecordKind::Expense))
        .unwrap();
    let selector = format!("id:record-category-{}", categories[1].0);
    app.press(&selector).unwrap();
    assert!(app.screen().selected(&selector).unwrap());
    app.type_text("id:record-amount", "7").unwrap();
    app.submit("id:record-amount").unwrap();
    app.wait_for_gone("id:record-save", std::time::Duration::from_secs(5))
        .unwrap();
    assert_eq!(exact_balance(&source), "93".parse().unwrap());
}

#[test]
fn record_money_echo_groups_without_rounding_the_saved_decimal() {
    let mut app = app();
    let source = make_account(&mut app, "精确金额回显账户", "10000");
    go_tab(&mut app, "tab-ledger");
    app.press("id:open-record").unwrap();
    app.wait_for("id:record-ready").unwrap();
    pick_account(&mut app, "record-account", &source);
    app.type_text("id:record-amount", "1234.567").unwrap();
    // Reopening the real account picker dismisses the amount input focus.
    pick_account(&mut app, "record-account", &source);
    assert_eq!(
        app.screen().input_text("id:record-amount").unwrap(),
        Some("1,234.567")
    );
    app.press("id:record-save").unwrap();
    app.wait_for_gone("id:record-save", std::time::Duration::from_secs(5))
        .unwrap();
    assert_eq!(exact_balance(&source), "8765.433".parse().unwrap());
}
