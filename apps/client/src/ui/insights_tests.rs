use super::*;
use naviwealth_finance::{daily::DailySpending, planning::Budget};
fn record(day: u32, currency: &str, amount: Decimal) -> DailySpending {
    DailySpending {
        date: date_to_secs(&format!("2026-11-{day:02}")).unwrap(),
        currency: currency.into(),
        amount,
    }
}
#[test]
fn daily_peak_uses_aggregate_days_and_currency_boundaries() {
    let rows = [
        record(9, "CNY", 4238.into()),
        record(12, "CNY", "152.9".parse().unwrap()),
        record(9, "JPY", 9000.into()),
    ];
    let daily = daily_spending(&rows, "CNY", 12).unwrap();
    assert_eq!(daily.len(), 12);
    assert_eq!(daily[0], Decimal::ZERO);
    assert_eq!(spending_peak(&daily), Some((8, 4238.into())));
    assert_eq!(daily[11], "152.9".parse().unwrap());
}
#[test]
fn unrepresentable_daily_totals_are_unavailable_not_partial_or_panicking() {
    assert!(
        daily_spending(
            &[
                record(1, "CNY", Decimal::MAX),
                record(1, "CNY", Decimal::ONE)
            ],
            "CNY",
            12
        )
        .is_none()
    );
}
#[component]
fn PeakProbe() -> impl IntoElement {
    spending_chart(&[0.into(), 5.into(), 5.into(), 3.into()], "CNY")
}
#[test]
fn empty_spending_has_no_peak_and_ties_select_only_earliest_day() {
    use nsh_engine::{EngineConfig, Root};
    use nsh_testing::Headless;
    assert_eq!(spending_peak(&[]), None);
    assert_eq!(spending_peak(&[0.into(), 0.into()]), None);
    assert_eq!(
        spending_peak(&[0.into(), 5.into(), 5.into()]),
        Some((1, 5.into()))
    );
    let mut app = Headless::start(EngineConfig::new(Root::of::<PeakProbe>())).unwrap();
    app.wait_for("id:today-spending-plot").unwrap();
    assert_eq!(
        spending_peak(&[0.into(), 5.into(), 5.into(), 3.into()]),
        Some((1, 5.into()))
    );
}
fn budget(currency: &str, spent: Decimal, limit: Decimal) -> BudgetProgress {
    BudgetProgress {
        id: String::new(),
        budget: Budget {
            month: "2026-11".into(),
            category_id: String::new(),
            currency: currency.into(),
            limit,
        },
        spent,
        remaining: limit - spent,
        entry_ids: vec![],
    }
}
#[test]
fn workspace_budget_figures_preserve_currency_families_and_exact_decimals() {
    let totals = budget_totals(&[
        budget("CNY", "768.30".parse().unwrap(), 1800.into()),
        budget("CNY", "7968.10".parse().unwrap(), 10200.into()),
        budget("JPY", 2000.into(), 5000.into()),
    ])
    .unwrap();
    assert_eq!(totals["CNY"], ("8736.40".parse().unwrap(), 12000.into()));
    assert_eq!(
        money_for(totals["CNY"].1 - totals["CNY"].0, "CNY"),
        "3,263.60"
    );
    assert_eq!(totals["JPY"], (2000.into(), 5000.into()));
    assert!(
        budget_totals(&[
            budget("CNY", Decimal::MAX, Decimal::MAX),
            budget("CNY", Decimal::ONE, Decimal::ONE)
        ])
        .is_none()
    );
}
