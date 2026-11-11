//! Real trades must retain investment intent when projected into daily activity.
use naviwealth_finance::{
    daily::{RecordDraft, RecordKind},
    models::{AccountCategory, NewAccount},
    wealth::{AssetDraft, OperationDraft, OperationKind},
};
use nsh_engine::{EngineConfig, Root};
use nsh_testing::Headless;
use rust_decimal::Decimal;

#[test]
fn activity_distinguishes_investment_operations_roles_and_transfer_direction() {
    naviwealth_client::enable_test_mode();
    let s = naviwealth_client::Services::shared();
    let date = chrono::Local::now()
        .date_naive()
        .and_hms_opt(0, 0, 0)
        .unwrap()
        .and_utc()
        .timestamp();
    let buy_id = s.runtime.block_on(async {
        let bank = s
            .create_account(
                NewAccount::custody(AccountCategory::Bank, "方向现金账户", "CNY"),
                Some(Decimal::from(10000)),
            )
            .await
            .unwrap();
        let broker = s
            .create_account(
                NewAccount::custody(AccountCategory::Broker, "方向持仓账户", "CNY"),
                None,
            )
            .await
            .unwrap();
        let savings = s
            .create_account(
                NewAccount::custody(AccountCategory::Bank, "方向储蓄账户", "CNY"),
                None,
            )
            .await
            .unwrap();
        let asset = s
            .save_wealth_asset(
                None,
                AssetDraft {
                    kind: "stock".into(),
                    name: "方向验收资产".into(),
                    market: None,
                    symbol: None,
                    currency: "CNY".into(),
                    note: None,
                },
            )
            .await
            .unwrap();
        let mut buy_id = String::new();
        for (kind, quantity, price, fees, dividend) in [
            (OperationKind::Opening, 2, 100, 0, 0),
            (OperationKind::Buy, 1, 110, 1, 0),
            (OperationKind::Split, 2, 0, 0, 0),
            (OperationKind::Dividend, 0, 0, 1, 12),
            (OperationKind::Sell, 2, 120, 2, 0),
        ] {
            let cash = !matches!(kind, OperationKind::Opening | OperationKind::Split);
            let op = s
                .save_wealth_operation(
                    None,
                    OperationDraft {
                        kind,
                        asset_id: asset.id.clone(),
                        account_id: broker.id.clone(),
                        cash_account_id: cash.then(|| bank.id.clone()),
                        date,
                        quantity: Decimal::from(quantity),
                        unit_price: Decimal::from(price),
                        fees: Decimal::from(fees),
                        amount: Decimal::from(dividend),
                        note: None,
                    },
                )
                .await
                .unwrap();
            let projected = s.finance_record(&op.id).await.unwrap();
            assert_eq!(projected.investment_kind, Some(kind));
            assert_eq!(projected.account_id, broker.id);
            assert_eq!(
                projected.destination_account_id,
                cash.then(|| bank.id.clone())
            );
            if kind == OperationKind::Buy {
                buy_id = op.id;
            }
        }
        s.save_finance_record(
            None,
            RecordDraft {
                kind: RecordKind::Transfer,
                date,
                amount: Decimal::from(100),
                account_id: bank.id,
                destination_account_id: Some(savings.id),
                destination_amount: None,
                category_id: None,
                payee: None,
                note: None,
            },
        )
        .await
        .unwrap();
        buy_id
    });
    let mut app = Headless::start(EngineConfig::new(Root::of::<naviwealth_client::App>())).unwrap();
    for kind in ["期初持仓", "买入", "拆股", "分红", "卖出"] {
        app.wait_for(&format!("text:{kind} · 方向验收资产"))
            .unwrap();
    }
    for value in ["成本 200.00", "-111.00", "现金 0.00", "+11.00", "+238.00"] {
        app.wait_for(&format!("text:{value}")).unwrap();
    }
    app.wait_for("text:结算 方向现金账户 · 持仓 方向持仓账户")
        .unwrap();
    app.wait_for("text:方向现金账户 → 方向储蓄账户").unwrap();
    app.wait_for_gone(
        "text:方向持仓账户 → 方向现金账户",
        std::time::Duration::from_secs(1),
    )
    .unwrap();
    app.press(&format!("id:record-{buy_id}")).unwrap();
    app.wait_for("text:流水详情").unwrap();
    app.wait_for("text:买入").unwrap();
    app.wait_for("text:持仓账户").unwrap();
    app.wait_for("text:结算账户").unwrap();
    app.wait_for("text:-111.00 CNY").unwrap();
    app.press("id:entry-source").unwrap();
    app.wait_for("text:交易详情").unwrap();
    app.wait_for("text:现金影响").unwrap();
    app.wait_for("text:-111.00 CNY").unwrap();
}
