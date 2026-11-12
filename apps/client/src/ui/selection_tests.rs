use super::*;
use nsh_engine::{EngineConfig, Root};
use nsh_testing::Headless;
#[component]
fn SelectionProbe() -> impl IntoElement {
    let s = crate::state::Services::shared();
    let mut a = s
        .runtime
        .block_on(s.finance_accounts(true))
        .unwrap()
        .into_iter()
        .find(|(a, _)| a.name == "归档银行卡")
        .unwrap()
        .0;
    a.archived = true;
    view()
        .child(select_field(
            "基金",
            signal(vec![SelectOption::new("etf", "沪深300 · ETF")]),
            signal("etf".into()),
            "etf",
        ))
        .child(compact_select_field(
            "账户",
            signal(vec![SelectOption::account(&a)]),
            signal(a.id),
            "archived",
        ))
}
#[test]
fn select_preserves_etf_label_and_explicit_archived_currency() {
    crate::enable_test_mode();
    let s = crate::state::Services::shared();
    s.runtime
        .block_on(s.create_account(
            naviwealth_finance::models::NewAccount::custody(
                naviwealth_finance::models::AccountCategory::Bank,
                "归档银行卡",
                "USD",
            ),
            None,
        ))
        .unwrap();
    let plain = SelectOption::new("etf", "沪深300 · ETF");
    assert_eq!(plain.currency, None);
    assert_eq!(plain.display_label(), "沪深300 · ETF");
    let mut app = Headless::start(EngineConfig::new(Root::of::<SelectionProbe>())).unwrap();
    app.wait_for("text:沪深300 · ETF").unwrap();
    app.wait_for("text:归档银行卡 · 已归档").unwrap();
    app.wait_for("text:USD").unwrap();
    app.press("id:etf").unwrap();
    app.wait_for("id:etf-etf").unwrap();
    app.press("id:etf-etf").unwrap();
    app.press("id:archived").unwrap();
    app.wait_for("text:归档银行卡 · 已归档 · USD").unwrap();
}
