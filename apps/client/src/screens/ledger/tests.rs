use super::*;
#[test]
fn local_month_is_not_previous_utc_month_at_midnight() {
    let local = chrono::DateTime::parse_from_rfc3339("2026-12-01T00:30:00+08:00").unwrap();
    let (from, until, label) = month_window_for(local.date_naive(), 0);
    assert_eq!(label, "2026 年 12 月");
    assert_eq!(ui::ymd(from), "2026-12-01");
    assert_eq!(ui::ymd(until), "2027-01-01");
    assert_eq!(month_window_for(local.date_naive(), -1).2, "2026 年 11 月");
}
