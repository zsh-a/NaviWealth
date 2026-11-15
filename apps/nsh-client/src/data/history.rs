//! Bounded, single-flight backfill. Only dated market observations are persisted.
use super::{db, finance, market};
use jiff::{Timestamp, civil::Date};
use navi_finance::{
    catalog,
    currency::{self, Currency},
    history as store, history_provider as provider,
};
use nsh_core::{prelude::*, storage::Storage};
use std::time::Duration;
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Status {
    pub running: bool,
    pub updated: usize,
    pub failed: usize,
}
fn state() -> Signal<Status> {
    global::<Status>()
}
pub fn status() -> Status {
    state().with(Clone::clone)
}
#[derive(serde::Serialize, serde::Deserialize)]
struct Attempt {
    key: String,
    from: Date,
    to: Date,
    at: i64,
    rows: usize,
    failed: bool,
}
const ATTEMPTS: &str = "history.attempts.v1";
fn attempts() -> Vec<Attempt> {
    Storage::get_item(ATTEMPTS)
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}
fn fetch_due(key: &str, from: Date, to: Date) -> bool {
    !attempts().iter().any(|a| {
        a.key == key
            && a.from <= from
            && a.to >= to
            && (0..if a.failed { 300 } else { 21_600 })
                .contains(&Timestamp::now().as_second().saturating_sub(a.at))
    })
}
fn record_fetch(key: &str, from: Date, to: Date, rows: usize, failed: bool) {
    let mut all = attempts();
    all.retain(|a| a.key != key);
    all.push(Attempt {
        key: key.into(),
        from,
        to,
        at: Timestamp::now().as_second(),
        rows,
        failed,
    });
    if all.len() > 256 {
        all.drain(..all.len() - 256);
    }
    if let Ok(raw) = serde_json::to_string(&all) {
        let _ = Storage::set_item(ATTEMPTS, raw);
    }
}
async fn get(http: &reqwest::Client, url: String) -> Result<String, String> {
    for attempt in 0..2 {
        let result = async {
            let response = http
                .get(&url)
                .timeout(Duration::from_secs(12))
                .send()
                .await
                .map_err(|_| "history request failed")?
                .error_for_status()
                .map_err(|_| "history request rejected")?;
            if response.content_length().is_some_and(|n| n > 2_000_000) {
                return Err("history response too large");
            }
            let bytes = response
                .bytes()
                .await
                .map_err(|_| "history response failed")?;
            if bytes.len() > 2_000_000 {
                return Err("history response too large");
            }
            Ok(String::from_utf8_lossy(&bytes).into_owned())
        }
        .await;
        match result {
            Ok(v) => return Ok(v),
            Err(e) if attempt == 1 => return Err(e.into()),
            _ => tokio::time::sleep(Duration::from_millis(300)).await,
        }
    }
    Err("history unavailable".into())
}
fn fetch_bar(
    b: &catalog::SecurityBinding,
    from: Date,
    to: Date,
) -> Result<Vec<store::DailyBar>, String> {
    let client = market::client()?;
    let zone = if b.market == "us_stock" {
        "America/New_York"
    } else {
        "Asia/Shanghai"
    };
    let local_today = Timestamp::now()
        .to_zoned(jiff::tz::TimeZone::get(zone).map_err(|_| "market timezone unavailable")?)
        .date();
    let to = to.min(
        local_today
            .yesterday()
            .map_err(|_| "market date unavailable")?,
    );
    if from > to {
        return Ok(vec![]);
    }
    client.runtime.block_on(async {
 let mut request=provider::request_symbol(b).map_err(|e|e.to_string())?;
 if b.market=="us_stock" {
 let raw=get(&client.http,format!("https://qt.gtimg.cn/q={request}")).await?;
 request=provider::us_request_symbol(b,&raw).map_err(|e|e.to_string())?;
 }
 let raw=get(&client.http,format!("https://web.ifzq.gtimg.cn/appstock/app/fqkline/get?param={request},day,{from},{to},400,")).await?;
 provider::tencent(b,&request,&raw,from,to,Timestamp::now()).map_err(|e|e.to_string())
 })
}
fn fetch_fx(
    currency: Currency,
    from: Date,
    to: Date,
    today: Date,
) -> Result<Vec<currency::FxRate>, String> {
    let client = market::client()?;
    client.runtime.block_on(async {
 let raw=get(&client.http,format!("https://api.frankfurter.dev/v2/providers/ecb/rates?from={from}&to={to}&base={currency}&quotes=CNY")).await?;
 provider::fx(&raw,currency,from,to,today).map_err(|e|e.to_string())
 })
}
// Fetch preceding observations so a weekend range start can use Friday's close.
// Valuation still selects only bars dated on or before each displayed day.
fn bar_start(from: Date, first_trade: Date) -> Date {
    let start = from.max(first_trade);
    start
        .checked_sub(jiff::Span::new().days(10))
        .unwrap_or(start)
}
/// The requested interval is capped at one year and excludes unfinished market days.
/// Empty provider results remain missing history, never fabricated coverage.
pub async fn backfill(from: Date, to: Date, force: bool) {
    if state().with_untracked(|s| s.running) {
        return;
    }
    let today = super::clock::today().0;
    let from = from.max(
        today
            .checked_sub(jiff::Span::new().days(365))
            .unwrap_or(today),
    );
    let to = to.min(today.yesterday().unwrap_or(today));
    if from > to {
        return;
    }
    let book = finance::holdings();
    let bindings = match db::with(catalog::bindings) {
        Some(Ok(v)) => v,
        _ => {
            state().update(|s| s.failed = 1);
            return;
        }
    };
    let bindings: Vec<_> = bindings
        .into_iter()
        .filter(|b| {
            book.trades
                .iter()
                .any(|t| t.security == b.security && t.at.date() <= to)
        })
        .collect();
    state().set(Status {
        running: true,
        ..Status::default()
    });
    let mut updated = 0;
    let mut failed = 0;
    for b in bindings {
        // An earlier trade may be needed on a closed position as well as a current holding.
        let first_trade = book
            .trades
            .iter()
            .filter(|t| t.security == b.security)
            .map(|t| t.at.date())
            .min()
            .unwrap_or(from);
        if first_trade > to {
            continue;
        }
        let start = bar_start(from, first_trade);
        let key = format!("{}:{}:{}", b.market, b.symbol, b.currency);
        if !force && !fetch_due(&key, start, to) {
            continue;
        }
        let query = b.clone();
        let result = blocking(move || fetch_bar(&query, start, to)).await;
        let mut count = 0;
        let mut bad = true;
        if let Ok(Ok(rows)) = result {
            // US midnight differs from the device day. Drop unfinished local dates before save.
            let rows: Vec<_> = rows
                .into_iter()
                .filter(|r| r.validate(&b, Timestamp::now()).is_ok())
                .collect();
            if !rows.is_empty()
                && let Some(Ok(n)) = db::with(|c| store::save_bars(c, &b, &rows, Timestamp::now()))
            {
                updated += n;
                count = rows.len();
                bad = false;
            }
        }
        if bad {
            failed += 1
        }
        record_fetch(&key, start, to, count, bad);
    }
    // Warm-up supplies the last published rate before a weekend start; never forward-fill backwards.
    let warm = from.checked_sub(jiff::Span::new().days(10)).unwrap_or(from);
    for currency in [Currency::HKD, Currency::USD]
        .into_iter()
        .filter(|currency| {
            finance::accounts()
                .iter()
                .any(|a| a.currency() == *currency)
                || book.securities.iter().any(|s| s.currency() == *currency)
        })
    {
        let key = format!("fx:{currency}");
        if !force && !fetch_due(&key, warm, to) {
            continue;
        }
        let result = blocking(move || fetch_fx(currency, warm, to, today)).await;
        let mut count = 0;
        let mut bad = true;
        if let Ok(Ok(rows)) = result
            && !rows.is_empty()
            && let Some(Ok(changed)) = db::with(|c| currency::save_rates(c, &rows))
        {
            updated += changed;
            count = rows.len();
            bad = false;
        }
        if bad {
            failed += 1
        }
        record_fetch(&key, warm, to, count, bad);
    }
    if finance::load().is_err() {
        failed += 1
    }
    state().set(Status {
        running: false,
        updated,
        failed,
    });
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn daily_bar_window_includes_prior_close_before_weekend_or_first_trade() {
        let weekend: Date = "2026-10-04".parse().unwrap();
        let old_trade: Date = "2020-01-01".parse().unwrap();
        assert_eq!(
            bar_start(weekend, old_trade),
            "2026-09-24".parse::<Date>().unwrap()
        );
        let first_trade: Date = "2026-10-10".parse().unwrap();
        assert_eq!(
            bar_start(weekend, first_trade),
            "2026-09-30".parse::<Date>().unwrap()
        );
    }
    #[test]
    #[ignore = "explicit public-network smoke test"]
    fn raw_daily_and_ecb_public_tls_smoke() {
        let from = "2026-10-01".parse().unwrap();
        let to = "2026-10-15".parse().unwrap();
        for (market, symbol, currency) in [
            ("cn_a", "510300", "CNY"),
            ("hk_stock", "00700", "HKD"),
            ("us_stock", "AAPL", "USD"),
            ("us_stock", "BRK.B", "USD"),
        ] {
            let b = catalog::SecurityBinding {
                security: "smoke".into(),
                market: market.into(),
                symbol: symbol.into(),
                currency: currency.into(),
            };
            assert!(!fetch_bar(&b, from, to).unwrap().is_empty());
        }
        for c in [Currency::HKD, Currency::USD] {
            assert!(
                !fetch_fx(c, from, to, "2026-11-15".parse().unwrap())
                    .unwrap()
                    .is_empty()
            )
        }
    }
}
