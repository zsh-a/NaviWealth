use finance_core::{catalog::SecurityBinding, currency::Currency, history_provider as p};
use jiff::{Timestamp, civil::Date};
fn b() -> SecurityBinding {
    SecurityBinding {
        security: "s".into(),
        market: "hk_stock".into(),
        symbol: "00700".into(),
        currency: "HKD".into(),
    }
}
fn d(s: &str) -> Date {
    s.parse().unwrap()
}
fn fixture() -> serde_json::Value {
    let mut qt = vec![serde_json::json!(""); 76];
    qt[2] = serde_json::json!("00700");
    qt[75] = serde_json::json!("HKD");
    serde_json::json!({"code":0,"data":{"hk00700":{"day":[["2026-10-02","422.000","421.200","425.000","419.800","19108045.000"]],"qt":{"hk00700":qt}}}})
}
fn parse(
    v: &serde_json::Value,
) -> Result<Vec<finance_core::history::DailyBar>, finance_core::history::Error> {
    p::tencent(
        &b(),
        "hk00700",
        &v.to_string(),
        d("2026-10-01"),
        d("2026-10-05"),
        "2026-10-06T00:00:00Z".parse::<Timestamp>().unwrap(),
    )
}
#[test]
fn strict_raw_prices_identity_currency_and_dates() {
    let v = fixture();
    let rows = parse(&v).unwrap();
    assert_eq!(rows[0].close, 421_200_000);
    assert_eq!(rows[0].volume, Some(19_108_045));
    let mut wrong = v.clone();
    wrong["data"]["hk00700"]["qt"]["hk00700"][2] = serde_json::json!("00941");
    assert!(parse(&wrong).is_err());
    let mut wrong = v.clone();
    wrong["data"]["hk00700"]["qt"]["hk00700"][75] = serde_json::json!("USD");
    assert!(parse(&wrong).is_err());
    let mut wrong = v.clone();
    wrong["data"]["hk00700"]["qfqday"] = wrong["data"]["hk00700"]["day"].take();
    assert!(parse(&wrong).is_err());
    let mut wrong = v.clone();
    wrong["data"]["hk00700"]["day"][0][0] = serde_json::json!("2026-10-06");
    assert!(parse(&wrong).is_err());
    let mut wrong = v.clone();
    wrong["data"]["hk00700"]["day"][0][3] = serde_json::json!("420");
    assert!(parse(&wrong).is_err());
    let mut wrong = v.clone();
    let row = wrong["data"]["hk00700"]["day"][0].clone();
    wrong["data"]["hk00700"]["day"]
        .as_array_mut()
        .unwrap()
        .push(row);
    assert!(parse(&wrong).is_err());
}
#[test]
fn fx_has_exact_dates_and_never_uses_future_or_wrong_currency() {
    let raw = r#"[{"date":"2026-10-02","base":"USD","quote":"CNY","rate":6.7046}]"#;
    let from = d("2026-10-01");
    let to = d("2026-10-05");
    let rows = p::fx(raw, Currency::USD, from, to, to).unwrap();
    assert_eq!(rows[0].rate, 6_704_600);
    assert_eq!(rows[0].day, d("2026-10-02"));
    assert!(p::fx(raw, Currency::HKD, from, to, to).is_err());
    assert!(p::fx(raw, Currency::USD, from, to, from).is_err());
    assert!(p::fx(raw, Currency::USD, d("2026-10-03"), to, to).is_err());
}

#[test]
fn fetched_fx_batch_persists_atomically_and_preserves_manual() {
    use finance_core::currency::{self, FxRate};
    let db = lifeos_core::memory(&[currency::SCHEMA]).unwrap();
    let day = d("2026-10-02");
    let rate = FxRate {
        currency: Currency::USD,
        day,
        rate: 7_000_000,
        source: "manual".into(),
    };
    currency::save_rate(&db, &rate).unwrap();
    let provider = FxRate {
        source: "frankfurter:ecb".into(),
        rate: 6_704_600,
        ..rate.clone()
    };
    let next = FxRate {
        day: day.tomorrow().unwrap(),
        ..provider.clone()
    };
    assert_eq!(
        currency::save_rates(&db, &[provider.clone(), next.clone()]).unwrap(),
        1
    );
    assert_eq!(
        currency::save_rates(&db, &[provider.clone(), next.clone()]).unwrap(),
        0
    );
    assert_eq!(
        currency::rate_on(&db, Currency::USD, day).unwrap().unwrap(),
        rate
    );
    assert_eq!(
        currency::rate_on(&db, Currency::USD, next.day)
            .unwrap()
            .unwrap(),
        next
    );
    let fresh = FxRate {
        day: next.day.tomorrow().unwrap(),
        ..provider.clone()
    };
    let invalid = FxRate {
        rate: 0,
        ..fresh.clone()
    };
    assert!(currency::save_rates(&db, &[fresh.clone(), invalid]).is_err());
    assert_eq!(currency::rates(&db).unwrap().len(), 2);
}
