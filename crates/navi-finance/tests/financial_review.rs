use navi_finance::{
    account::{Account, AccountKind, defaults},
    journal::{self, Entry, Posting, Source, Transaction},
    review,
};
fn date(s: &str) -> jiff::civil::Date {
    s.parse().unwrap()
}
fn expense(id: &str, day: &str, category: &str, amount: i64) -> Transaction {
    let cash = Account::new(AccountKind::Assets, "Cash").unwrap();
    journal::spend(
        Entry {
            id: id.into(),
            at: format!("{day}T12:00:00").parse().unwrap(),
            payee: id.into(),
            note: String::new(),
            source: Source::Manual,
        },
        &cash,
        &defaults::expense(category),
        amount,
    )
    .unwrap()
}
#[test]
fn refunds_reduce_totals_and_drilldown_contains_exact_expense_rows() {
    let food = expense("food", "2026-11-15", "餐饮", 5000);
    let mut refund = food.clone();
    refund.id = "refund".into();
    for p in &mut refund.postings {
        p.amount = -p.amount / 2;
    }
    let shopping = expense("shop", "2026-11-14", "购物", 3000);
    let mut transfer = food.clone();
    transfer.id = "transfer".into();
    transfer.postings[0] = Posting {
        account: Account::new(AccountKind::Assets, "Other").unwrap(),
        amount: 5000,
    };
    let future = expense("future", "2026-11-16", "购物", 90000);
    let rows = vec![food, refund, shopping, transfer, future];
    let spending = review::spending(&rows, date("2026-11-01"), date("2026-11-15"));
    assert_eq!((spending.total, spending.records), (5500, 3));
    assert_eq!(
        spending.categories,
        vec![("支出:购物".into(), 3000), ("支出:餐饮".into(), 2500)]
    );
    let details = review::transactions(
        &rows,
        date("2026-11-01"),
        date("2026-11-15"),
        Some("支出:餐饮"),
    );
    assert_eq!(
        details.iter().map(|t| t.id.as_str()).collect::<Vec<_>>(),
        ["food", "refund"]
    );
    let empty = review::spending(&rows, date("2026-10-01"), date("2026-10-31"));
    assert_eq!(empty.records, 0);
}
#[test]
fn elapsed_days_and_completed_calendar_months_compare_fairly() {
    assert_eq!(
        review::comparison_end(
            date("2026-11-01"),
            date("2026-11-30"),
            date("2026-10-01"),
            date("2026-10-31"),
            date("2026-11-15")
        ),
        date("2026-10-15")
    );
    assert_eq!(
        review::comparison_end(
            date("2026-03-01"),
            date("2026-03-31"),
            date("2026-02-01"),
            date("2026-02-28"),
            date("2026-03-30")
        ),
        date("2026-02-28")
    );
    assert_eq!(
        review::comparison_end(
            date("2026-11-01"),
            date("2026-11-30"),
            date("2026-10-01"),
            date("2026-10-31"),
            date("2026-12-01")
        ),
        date("2026-10-31")
    );
}
