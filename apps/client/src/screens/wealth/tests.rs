use super::*;
use crate::{
    finance_ui::{Feedback, Navigation},
    state::{DataVersion, Services},
};
use naviwealth_finance::models::{AccountCategory, NewAccount};
use nsh_engine::{EngineConfig, Root};
use nsh_testing::Headless;

#[component]
fn WealthJourney() -> impl IntoElement {
    provide_context(Services::shared());
    provide_context(DataVersion(signal(0)));
    let routes = signal(vec!["/wealth/assets/new".to_owned()]);
    let feedback = signal(String::new());
    provide_context(Navigation(routes));
    provide_context(Feedback(feedback));
    view()
        .flex_1()
        .child(dynamic(move || {
            render(
                routes
                    .get()
                    .last()
                    .cloned()
                    .unwrap_or_else(|| "/wealth/assets".into()),
            )
        }))
        .child(text(move || feedback.get()))
}

#[test]
fn native_asset_opening_price_and_correction_keep_quantity_and_return_to_live_detail() {
    crate::enable_test_mode();
    let services = Services::shared();
    let broker = services
        .runtime
        .block_on(services.create_account(
            NewAccount::custody(AccountCategory::Broker, "持仓交互账户", "CNY"),
            None,
        ))
        .unwrap();
    let mut app = Headless::start(EngineConfig::new(Root::of::<WealthJourney>())).unwrap();
    app.wait_for("id:wealth-asset-name").unwrap();
    app.type_text("id:wealth-asset-name", "海图交互资产")
        .unwrap();
    app.press("id:finance-form-save").unwrap();
    app.wait_for("text:海图交互资产").unwrap();
    app.wait_for("id:wealth-record").unwrap();
    let asset = services
        .runtime
        .block_on(services.wealth_assets(false))
        .unwrap()
        .into_iter()
        .find(|a| a.details.name == "海图交互资产")
        .unwrap();
    app.press("id:wealth-record").unwrap();
    app.wait_for("id:wealth-trade-kind").unwrap();
    app.press("id:wealth-trade-kind").unwrap();
    app.press("id:wealth-trade-kind-opening").unwrap();
    app.press("id:wealth-trade-account").unwrap();
    app.press(&format!("id:wealth-trade-account-{}", broker.id))
        .unwrap();
    app.type_text("id:wealth-trade-quantity", "2").unwrap();
    app.type_text("id:wealth-trade-price", "100").unwrap();
    app.press("id:finance-form-save").unwrap();
    app.wait_for("id:wealth-price").unwrap();
    app.wait_for("text:数量 2 · 成本 200.00 CNY").unwrap();
    for price in ["120", "130"] {
        app.press("id:wealth-price").unwrap();
        app.wait_for("id:wealth-price-value").unwrap();
        app.clear("id:wealth-price-value").unwrap();
        app.type_text("id:wealth-price-value", price).unwrap();
        app.press("id:finance-form-save").unwrap();
        app.wait_for("id:wealth-record").unwrap();
        app.wait_for("text:数量 2 · 成本 200.00 CNY").unwrap();
    }
    let snapshot = services
        .runtime
        .block_on(services.wealth_snapshot(lifeos::ids::now_secs(), "CNY".into()))
        .unwrap();
    let h = snapshot
        .holdings
        .iter()
        .find(|h| h.asset_id == asset.id)
        .unwrap();
    assert_eq!(h.quantity, Decimal::from(2));
    assert_eq!(h.market_value, Some(Decimal::from(260)));
    assert_eq!(h.cost_basis, Decimal::from(200));
    assert_eq!(
        services
            .runtime
            .block_on(services.wealth_operations(Some(asset.id.clone())))
            .unwrap()
            .len(),
        1
    );
    let operation = services
        .runtime
        .block_on(services.wealth_operations(Some(asset.id.clone())))
        .unwrap()
        .remove(0);
    app.press(&format!("id:wealth-operation-{}", operation.id))
        .unwrap();
    app.press("id:wealth-edit-operation").unwrap();
    app.wait_for("id:wealth-trade-quantity").unwrap();
    app.clear("id:wealth-trade-quantity").unwrap();
    app.type_text("id:wealth-trade-quantity", "3").unwrap();
    app.press("id:finance-form-save").unwrap();
    app.wait_for("text:数量 3 · 成本 300.00 CNY").unwrap();
    app.press(&format!("id:wealth-operation-{}", operation.id))
        .unwrap();
    app.press("id:wealth-edit-operation").unwrap();
    app.wait_for("id:wealth-trade-quantity").unwrap();
    app.clear("id:wealth-trade-quantity").unwrap();
    app.type_text("id:wealth-trade-quantity", "4").unwrap();
    app.press("id:finance-form-cancel").unwrap();
    app.wait_for("id:finance-form-discard").unwrap();
    app.press("id:finance-form-discard").unwrap();
    app.wait_for("text:3").unwrap();
    app.press("id:wealth-delete-operation").unwrap();
    app.wait_for("id:finance-confirm-submit").unwrap();
    app.press("id:finance-confirm-submit").unwrap();
    app.wait_for("id:wealth-record").unwrap();
    assert!(
        services
            .runtime
            .block_on(services.wealth_operations(Some(asset.id)))
            .unwrap()
            .is_empty()
    );
}
