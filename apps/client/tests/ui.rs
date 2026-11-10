//! Headless UI tests: the real engine (nsh-testing) drives the app with
//! an in-memory database and the mock AI provider. These cover the phase
//! 1/2 acceptance flows that do not need a physical device.

use nsh_engine::{EngineConfig, Root};
use nsh_testing::Headless;

fn app() -> Headless {
    naviwealth_client::enable_test_mode();
    let config = EngineConfig::new(Root::of::<naviwealth_client::App>());
    Headless::start(config).expect("headless app starts")
}

#[test]
fn account_list_seeds_and_shells_render() {
    let mut app = app();
    // The shell renders with the four tabs.
    app.wait_for("id:tab-accounts").unwrap();
    app.press("id:tab-ledger").unwrap();
    app.wait_for("text:账本").unwrap();
    app.press("id:tab-settings").unwrap();
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
    app.wait_for("text:1000 CNY").unwrap();

    // Record an expense against it (category/account auto-pick the first
    // chip: 餐饮 + 测试现金).
    app.press("id:open-record").unwrap();
    app.type_text("id:record-amount", "12.5").unwrap();
    // Wait for the pickers to load before saving.
    app.wait_for("text:餐饮").unwrap();
    app.press("id:record-save").unwrap();

    // The ledger shows the new entry (the legs render as
    // "<account>  <units> <unit>" texts).
    app.press("id:tab-ledger").unwrap();
    app.wait_for("text:Expense").unwrap();
    app.wait_for("text:Dining  12.5 CNY").unwrap();
}

#[test]
fn mock_ai_streams_a_reply() {
    let mut app = app();
    app.wait_for("id:tab-chat").unwrap();
    app.press("id:tab-chat").unwrap();
    app.wait_for("id:chat-input").unwrap();
    app.type_text("id:chat-input", "你好").unwrap();
    app.press("id:chat-send").unwrap();
    app.wait_for("text:已连接模拟模型（开发模式）。真实模型请在设置中配置自己的 API Key。")
        .unwrap();
}
