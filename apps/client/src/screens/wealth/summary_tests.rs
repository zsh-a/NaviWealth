use super::*;
use nsh_engine::{EngineConfig, Root};
use nsh_testing::Headless;
fn holding(currency: &str, value: Option<Decimal>) -> Holding {
    Holding {
        asset_id: format!("{currency}-{value:?}"),
        account_id: "broker".into(),
        name: "指数基金".into(),
        currency: currency.into(),
        quantity: 1.into(),
        cost_basis: 50.into(),
        market_price: value,
        price_as_of: None,
        market_value: value,
        base_value: None,
        unrealized_pnl: None,
        realized_pnl: 0.into(),
        dividends: 0.into(),
    }
}
fn partial() -> WealthSnapshot {
    WealthSnapshot {
        as_of: 500 * 86400,
        base_currency: "CNY".into(),
        holdings: vec![
            holding("USD", Some(100.into())),
            holding("USD", None),
            holding("JPY", None),
        ],
        currencies: vec![CurrencyWealth {
            currency: "USD".into(),
            assets: 350.into(),
            liabilities: 40.into(),
            net: 310.into(),
        }],
        missing_prices: vec!["unpriced".into()],
        missing_fx: vec![],
        net_worth: None,
    }
}
#[component]
fn PartialProbe() -> impl IntoElement {
    view().children(
        allocations(&partial())
            .unwrap()
            .into_iter()
            .map(super::super::overview::allocation),
    )
}
#[test]
fn partial_prices_keep_known_currency_assets_and_debt() {
    let groups = allocations(&partial()).unwrap();
    let usd = groups.iter().find(|g| g.wealth.currency == "USD").unwrap();
    assert_eq!(
        (usd.investment, usd.cash, usd.missing),
        (100.into(), 250.into(), 1)
    );
    assert_eq!(usd.wealth.liabilities, 40.into());
    assert!(partial().net_worth.is_none());
    let mut app = Headless::start(EngineConfig::new(Root::of::<PartialProbe>())).unwrap();
    app.wait_for("text:资产构成 · USD · 部分缺价").unwrap();
    app.wait_for("text:已知资产 350.00 USD · 1 项持仓缺价")
        .unwrap();
    app.wait_for("text:40.00").unwrap();
}
#[test]
fn unpriced_only_currency_is_retained() {
    let groups = allocations(&partial()).unwrap();
    let jpy = groups.iter().find(|g| g.wealth.currency == "JPY").unwrap();
    assert_eq!(jpy.missing, 1);
    assert_eq!(jpy.investment, Decimal::ZERO);
    let mut app = Headless::start(EngineConfig::new(Root::of::<PartialProbe>())).unwrap();
    app.wait_for("text:资产构成 · JPY · 部分缺价").unwrap();
    app.wait_for("text:已知资产 0 JPY · 1 项持仓缺价").unwrap();
}
fn history() -> Vec<WealthHistoryPoint> {
    [100, 200, 300, 490]
        .into_iter()
        .map(|d| WealthHistoryPoint {
            as_of: d * 86400,
            net_worth: Some(Decimal::from(d * 10)),
            missing_prices: vec![],
            missing_fx: vec![],
        })
        .collect()
}
#[component]
fn SparseHistoryProbe() -> impl IntoElement {
    let window = history_window(history(), 500 * 86400);
    fui::history_chart(
        window
            .points
            .into_iter()
            .map(|p| (ui::ymd(p.as_of), p.net_worth))
            .collect(),
        format!("净资产 · {}", window.label),
        "CNY".into(),
    )
}
#[test]
fn sparse_recent_history_falls_back_to_all_recorded_points() {
    let all = history_window(history(), 500 * 86400);
    assert_eq!(all.label, "全部历史");
    assert_eq!(all.points.len(), 4);
    let mut app = Headless::start(EngineConfig::new(Root::of::<SparseHistoryProbe>())).unwrap();
    app.wait_for("id:finance-trend-plot").unwrap();
    app.wait_for("text:净资产 · 全部历史").unwrap();
    app.wait_for("text:1,000.00 CNY").unwrap();
    app.wait_for("text:4,900.00 CNY").unwrap();
}
#[test]
fn three_complete_recent_points_keep_thirty_day_view_and_missing_gaps() {
    let mut points = history();
    for d in [480, 485] {
        points.push(WealthHistoryPoint {
            as_of: d * 86400,
            net_worth: Some(10.into()),
            missing_prices: vec![],
            missing_fx: vec![],
        });
    }
    points.push(WealthHistoryPoint {
        as_of: 486 * 86400,
        net_worth: None,
        missing_prices: vec!["x".into()],
        missing_fx: vec![],
    });
    points.sort_by_key(|p| p.as_of);
    let recent = history_window(points, 500 * 86400);
    assert_eq!(recent.label, "近30天");
    assert_eq!(recent.points.len(), 4);
    assert!(recent.points.iter().any(|p| p.net_worth.is_none()));
}
