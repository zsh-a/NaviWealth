//! Account row identity stays stable while its name and monetary state change.
//! This catches accidentally capturing a keyed row's initial ReadSignal value.
use naviwealth_client::Services;
use nsh_engine::{EngineConfig, Root};
use nsh_testing::Headless;
use std::time::Duration;

#[test]
fn account_row_and_currency_totals_refresh_without_switching_tabs() {
    naviwealth_client::enable_test_mode();
    let mut app = Headless::start(EngineConfig::new(Root::of::<naviwealth_client::App>())).unwrap();
    app.wait_for("id:tab-accounts").unwrap();
    app.press("id:tab-accounts").unwrap();
    app.wait_for("id:wealth-accounts").unwrap();
    app.press("id:wealth-accounts").unwrap();
    app.wait_for("id:open-account-form").unwrap();
    app.press("id:open-account-form").unwrap();
    app.type_text("id:account-name", "响应式账户").unwrap();
    app.type_text("id:account-opening", "1000").unwrap();
    app.press("id:account-save").unwrap();
    app.wait_for("text:1,000.00 CNY").unwrap();
    let services = Services::shared();
    let accounts = services
        .runtime
        .block_on(services.finance_accounts(false))
        .unwrap();
    let id = accounts
        .iter()
        .find(|(a, _)| a.name == "响应式账户")
        .unwrap()
        .0
        .id
        .clone();

    // Rename preserves the account ID and its keyed list row.
    app.press(&format!("id:account-{id}")).unwrap();
    app.wait_for("id:account-details").unwrap();
    app.press("id:account-edit").unwrap();
    app.wait_for("id:account-editor").unwrap();
    app.wait_for_gone("id:account-details", Duration::from_secs(2))
        .unwrap();
    app.wait_for_gone("id:account-detail-back", Duration::from_secs(2))
        .unwrap();
    app.clear("id:account-name").unwrap();
    app.type_text("id:account-name", "更新后的账户").unwrap();
    app.press("id:account-save").unwrap();
    app.wait_for("text:更新后的账户").unwrap();
    app.wait_for_gone("text:响应式账户", Duration::from_secs(2))
        .unwrap();
    app.wait_for(&format!("id:account-{id}")).unwrap();
    app.wait_for("text:1,000.00 CNY").unwrap();

    // Cancel also returns to the account list: a native detail window must
    // never remain above or reappear over the root-level account editor.
    app.press(&format!("id:account-{id}")).unwrap();
    app.press("id:account-edit").unwrap();
    app.wait_for("id:account-editor").unwrap();
    app.wait_for_gone("id:account-details", Duration::from_secs(2))
        .unwrap();
    app.press("id:account-cancel").unwrap();
    app.wait_for_gone("id:account-editor", Duration::from_secs(2))
        .unwrap();
    assert!(!app.screen().matches("id:account-details").unwrap());

    // A write from the account screen refreshes both row and aggregate,
    // while the screen and row stay mounted throughout.
    app.press("id:open-record").unwrap();
    app.wait_for("id:record-category").unwrap();
    app.type_text("id:record-amount", "50").unwrap();
    app.press("id:record-save").unwrap();
    app.wait_for("text:950.00 CNY").unwrap();
    app.wait_for("text:950.00").unwrap();
    app.wait_for_gone("text:1,000.00 CNY", Duration::from_secs(2))
        .unwrap();
    app.wait_for(&format!("id:account-{id}")).unwrap();

    // With archived accounts visible, archiving/restoring keeps the same
    // row key and changes its status and aggregate participation in place.
    app.press("id:accounts-show-archived").unwrap();
    app.press(&format!("id:account-{id}")).unwrap();
    app.press("id:account-archive").unwrap();
    app.wait_for("text:现金 · 已归档").unwrap();
    app.wait_for("text:950.00 CNY").unwrap();
    app.press(&format!("id:account-{id}")).unwrap();
    app.press("id:account-restore").unwrap();
    app.wait_for_gone("text:现金 · 已归档", Duration::from_secs(2))
        .unwrap();
    app.wait_for("text:950.00").unwrap();

    // Another currency has its own total, never folded into CNY at 1:1.
    app.press("id:open-account-form").unwrap();
    app.type_text("id:account-name", "美元账户").unwrap();
    app.clear("id:account-currency").unwrap();
    app.type_text("id:account-currency", "USD").unwrap();
    app.type_text("id:account-opening", "25").unwrap();
    app.press("id:account-save").unwrap();
    app.wait_for("text:25.00 USD").unwrap();
    app.wait_for("text:950.00").unwrap();
    app.wait_for("text:25.00").unwrap();
}
