//! Bounded, single-flight backfill. Only dated market observations are persisted.
use super::{db, finance, market};
use jiff::{Timestamp, civil::Date};
use navi_finance::{
    catalog,
    currency::{self, Currency},
    history as store, history_provider as provider,
};
use nsh_core::{prelude::*, storage::Storage};
use std::{rc::Rc, time::Duration};
mod queue;
mod range;
pub(super) use queue::{binding_changed, request_default, resume};
pub(crate) use queue::{request_gap, request_range};
pub(crate) use range::HistoryScope;
#[derive(Clone, Default, PartialEq)]
struct Revision(u64);

pub fn watch() {
    global::<Revision>().with(|_| ());
}
fn invalidate() {
    global::<Revision>().update(|rev| rev.0 = rev.0.wrapping_add(1));
}
pub fn daily_history(
    security: Option<&str>,
    limit: i64,
) -> Result<Vec<Vec<store::DailyBar>>, String> {
    db::with(|c| store::daily_history(c, security, limit))
        .ok_or("database unavailable")?
        .map_err(|e| e.to_string())
}

pub fn changes(security: Option<&str>, limit: i64) -> Result<Vec<store::PriceChange>, String> {
    let book = finance::holdings_snapshot();
    db::with(|c| {
        store::audit_rows(c, security, limit)?
            .into_iter()
            .map(|row| row.price_change(&book.securities))
            .collect::<Result<Vec<_>, store::Error>>()
    })
    .ok_or("database unavailable")?
    .map_err(|e| e.to_string())
}

#[derive(Clone, PartialEq, serde::Serialize, serde::Deserialize)]
struct Attempt {
    key: String,
    from: Date,
    to: Date,
    at: i64,
    rows: usize,
    failed: bool,
}
const ATTEMPTS: &str = "history.attempts.v1";
#[derive(Clone, Default, PartialEq)]
struct Recent(Option<Rc<Vec<Attempt>>>);

pub(super) fn clear_attempts() {
    queue::reset();
    global::<Recent>().set(Recent::default());
    Storage::remove_item(ATTEMPTS);
    invalidate();
}
fn attempts() -> Rc<Vec<Attempt>> {
    let cache = global::<Recent>();
    if let Some(records) = cache.with_untracked(|s| s.0.clone()) {
        return records;
    }
    let records = Rc::new(
        Storage::get_item(ATTEMPTS)
            .and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or_default(),
    );
    cache.set(Recent(Some(Rc::clone(&records))));
    records
}
impl Attempt {
    fn fresh(&self, now: i64) -> bool {
        (0..if self.failed || self.rows == 0 {
            300
        } else {
            21_600
        })
            .contains(&now.saturating_sub(self.at))
    }
}
fn record_fetch(key: &str, from: Date, to: Date, rows: usize, failed: bool) {
    let now = Timestamp::now().as_second();
    let mut all = (*attempts()).clone();
    all.retain(|a| a.fresh(now) && !(a.key == key && from <= a.from && a.to <= to));
    all.push(Attempt {
        key: key.into(),
        from,
        to,
        at: now,
        rows,
        failed,
    });
    // Keep the complete live session cache even if preference storage is full.
    let saved = &all[all.len().saturating_sub(2048)..];
    if let Ok(raw) = serde_json::to_string(saved) {
        let _ = Storage::set_item(ATTEMPTS, raw);
    }
    global::<Recent>().set(Recent(Some(Rc::new(all))));
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
fn last_finished_day(binding: &catalog::SecurityBinding, now: Timestamp) -> Option<Date> {
    let zone = if binding.market == "us_stock" {
        "America/New_York"
    } else {
        "Asia/Shanghai"
    };
    now.to_zoned(jiff::tz::TimeZone::get(zone).ok()?)
        .date()
        .yesterday()
        .ok()
}

fn fetch_bar(
    b: &catalog::SecurityBinding,
    from: Date,
    to: Date,
) -> Result<Vec<store::DailyBar>, String> {
    let client = market::client()?;
    let to = to.min(last_finished_day(b, Timestamp::now()).ok_or("market date unavailable")?);
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
#[cfg(test)]
mod tests {
    use super::*;
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
