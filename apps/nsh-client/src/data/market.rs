//! Foreground-only public multi-market refresh. Network work stays off the UI thread.
use super::{clock, db, finance};
use finance_core::{
    catalog, holdings,
    market::{self, MarketQuote},
};
use market_data_rs::{
    FetchOptions, MarketData, Symbol, Tencent, cache::NoCache, transport::HttpClient,
};
use nsh_core::prelude::*;
use std::{
    sync::{Arc, OnceLock},
    time::Duration,
};

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Status {
    pub refreshing: bool,
    pub failed: usize,
    pub updated: usize,
}
#[derive(Clone, Default, PartialEq, Eq)]
struct State {
    quotes: Vec<MarketQuote>,
    status: Status,
    attempted_at: Option<jiff::Timestamp>,
}
fn state() -> Signal<State> {
    global::<State>()
}
pub fn status() -> Status {
    state().with(|s| s.status.clone())
}
pub fn quote(security: &str) -> Option<MarketQuote> {
    let binding = super::catalog::bindings()
        .into_iter()
        .find(|b| b.security == security)?;
    let canonical = market::canonical_binding(&binding)?;
    state().with(|s| {
        s.quotes
            .iter()
            .filter(|q| {
                q.security == security && q.symbol == canonical && q.currency == binding.currency
            })
            .max_by_key(|q| q.observed_at)
            .cloned()
    })
}
/// Provenance for an effective network mark, excluding manual ties.
pub fn effective_quote(effective: &holdings::Quote) -> Option<MarketQuote> {
    let manual = db::with(holdings::store::load)?.ok()?;
    if manual
        .quotes
        .iter()
        .any(|q| q.security == effective.security && q.day >= effective.day)
    {
        return None;
    }
    quote(&effective.security).filter(|q| q.day() == effective.day && q.price == effective.price)
}
pub fn load() -> Result<(), String> {
    let quotes = db::with(market::load)
        .ok_or("database unavailable")?
        .map_err(|e| e.to_string())?;
    state().update(|s| s.quotes = quotes);
    Ok(())
}
pub(super) struct Client {
    pub(super) runtime: tokio::runtime::Runtime,
    service: MarketData,
    pub(super) http: reqwest::Client,
}
pub(super) fn client() -> Result<&'static Client, String> {
    static CLIENT: OnceLock<Result<Client, String>> = OnceLock::new();
    CLIENT
        .get_or_init(|| {
            let runtime = tokio::runtime::Builder::new_multi_thread()
                .worker_threads(2)
                .enable_all()
                .build()
                .map_err(|_| "market runtime unavailable".to_owned())?;
            let _guard = runtime.enter();
            // NSH has no JNI JavaVM. Use bundled public roots, retaining hostname
            // and certificate verification instead of Android's platform verifier.
            let roots =
                rustls::RootCertStore::from_iter(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
            let tls = rustls::ClientConfig::builder_with_provider(Arc::new(
                rustls::crypto::ring::default_provider(),
            ))
            .with_safe_default_protocol_versions()
            .map_err(|_| "TLS configuration unavailable".to_owned())?
            .with_root_certificates(roots)
            .with_no_client_auth();
            let http = reqwest::Client::builder()
                .tls_backend_preconfigured(tls)
                .redirect(reqwest::redirect::Policy::none())
                .connect_timeout(Duration::from_secs(5))
                .user_agent("NaviWealth/0.6")
                .build()
                .map_err(|_| "market transport unavailable".to_owned())?;
            let service = MarketData::builder()
                .register(Tencent)
                .cache(Arc::new(NoCache))
                .http(Arc::new(HttpClient::with_client(http.clone())))
                .build()
                .map_err(|_| "market provider unavailable".to_owned())?;
            drop(_guard);
            Ok(Client {
                runtime,
                service,
                http,
            })
        })
        .as_ref()
        .map_err(Clone::clone)
}
type QuoteResult = (catalog::SecurityBinding, Result<MarketQuote, String>);
fn fetch(bindings: Vec<catalog::SecurityBinding>) -> Result<Vec<QuoteResult>, String> {
    let client = client()?;
    client.runtime.block_on(async {
        let mut out = Vec::new();
        // SDK enforces batches, quotas, retries and per-symbol failures.
        for batch in bindings.chunks(100) {
            let mut valid = Vec::new();
            for b in batch {
                if b.market != "cn_a" {
                    let code = match b.market.as_str() {
                        "hk_stock" => format!(
                            "hk{}",
                            market::hong_kong_code(&b.symbol).unwrap_or_default()
                        ),
                        "us_stock" => format!("us{}", b.symbol),
                        _ => {
                            out.push((b.clone(), Err("unsupported market".into())));
                            continue;
                        }
                    };
                    let result = async {
                        b.validate().map_err(|_| "unsupported binding".to_owned())?;
                        let response = client
                            .http
                            .get(format!("https://qt.gtimg.cn/q={code}"))
                            .timeout(Duration::from_secs(12))
                            .send()
                            .await
                            .map_err(|_| "quote request failed")?
                            .error_for_status()
                            .map_err(|_| "quote request rejected")?;
                        let bytes = response
                            .bytes()
                            .await
                            .map_err(|_| "quote response failed")?;
                        if bytes.len() > 16384 {
                            return Err("quote response too large".into());
                        }
                        market::parse_tencent(
                            b,
                            &String::from_utf8_lossy(&bytes),
                            jiff::Timestamp::now(),
                        )
                        .map_err(|_| "quote identity invalid".into())
                    }
                    .await;
                    out.push((b.clone(), result));
                    continue;
                }
                match b.symbol.parse::<Symbol>() {
                    Ok(s) => valid.push((b.clone(), s)),
                    Err(_) => out.push((b.clone(), Err("unsupported symbol".into()))),
                }
            }
            if valid.is_empty() {
                continue;
            }
            let results = client
                .service
                .quotes(
                    valid.iter().map(|(_, s)| s.clone()).collect(),
                    FetchOptions {
                        refresh: true,
                        allow_stale: false,
                    },
                )
                .await;
            match results {
                Err(_) => {
                    for (b, _) in valid {
                        out.push((b, Err("quote refresh failed".into())));
                    }
                }
                Ok(results) => {
                    for ((binding, symbol), outcome) in valid.into_iter().zip(results) {
                        if outcome.symbol != symbol {
                            out.push((binding, Err("quote identity invalid".into())));
                            continue;
                        }
                        let result = outcome
                            .result
                            .map_err(|_| "quote unavailable".to_owned())
                            .and_then(|data| {
                                if data.data.validate(&symbol).is_err() || data.source != "tencent"
                                {
                                    return Err("quote identity invalid".into());
                                }
                                let price =
                                    holdings::parse_units(&data.data.price.normalize().to_string())
                                        .filter(|p| *p > 0)
                                        .ok_or("quote price invalid")?;
                                Ok(MarketQuote {
                                    security: binding.security.clone(),
                                    symbol: data.data.symbol.to_string(),
                                    currency: data.data.currency,
                                    provider: data.source,
                                    price,
                                    observed_at: data
                                        .data
                                        .observed_at
                                        .to_rfc3339()
                                        .parse()
                                        .map_err(|_| "quote time invalid")?,
                                    fetched_at: data
                                        .fetched_at
                                        .to_rfc3339()
                                        .parse()
                                        .map_err(|_| "fetch time invalid")?,
                                    previous_close_only: data.data.previous_close_only,
                                })
                            });
                        out.push((binding, result));
                    }
                }
            }
        }
        Ok(out)
    })
}
fn fetch_fx(
    today: jiff::civil::Date,
) -> Result<Vec<Result<finance_core::currency::FxRate, String>>, String> {
    use finance_core::currency::Currency;
    let client = client()?;
    client.runtime.block_on(async {
        let mut rows = Vec::new();
        for currency in [Currency::HKD, Currency::USD] {
            let result = async {
                let response = client.http.get(format!("https://api.frankfurter.dev/v2/providers/ecb/rates?base={currency}&quotes=CNY"))
                    .timeout(Duration::from_secs(12)).send().await.map_err(|_| "FX request failed")?
                    .error_for_status().map_err(|_| "FX request rejected")?;
                let bytes = response.bytes().await.map_err(|_| "FX response failed")?;
                if bytes.len() > 16384 { return Err("FX response too large".into()); }
                market::parse_fx(std::str::from_utf8(&bytes).map_err(|_| "invalid FX response")?, currency, today).map_err(|_| "invalid FX response".into())
            }.await;
            rows.push(result);
        }
        Ok(rows)
    })
}
/// Single-flight with a five-minute foreground TTL. Force bypasses TTL only.
pub async fn refresh(force: bool) {
    let now = jiff::Timestamp::now();
    if state().with_untracked(|s| {
        s.status.refreshing
            || (!force
                && s.attempted_at
                    .is_some_and(|t| now.as_second() - t.as_second() < 300))
    }) {
        return;
    }
    let book = finance::holdings();
    let bindings = match db::with(catalog::bindings) {
        Some(Ok(v)) => v,
        _ => {
            state().update(|s| s.status.failed = 1);
            return;
        }
    };
    let bindings: Vec<_> = bindings
        .into_iter()
        .filter(|b| {
            book.securities
                .iter()
                .find(|s| s.id == b.security)
                .is_some_and(|s| {
                    book.position(s, clock::today().0)
                        .is_ok_and(|p| p.quantity > 0)
                })
        })
        .collect();
    if !force
        && bindings.is_empty()
        && !finance::accounts()
            .iter()
            .any(|a| a.currency() != finance_core::currency::Currency::CNY)
    {
        if !finance::transactions().is_empty()
            && let Err(error) = super::valuation::capture(false)
        {
            log::warn!("market: cash valuation capture failed: {error}");
        }
        return;
    }
    let today = clock::today().0;
    state().update(|s| {
        s.status = Status {
            refreshing: true,
            ..Status::default()
        };
        s.attempted_at = Some(now)
    });
    let result = blocking(move || fetch(bindings)).await;
    let mut failed = 0;
    let mut updated = 0;
    let mut succeeded = 0;
    match result {
        Ok(Ok(rows)) => {
            for (_, result) in rows {
                match result {
                    Ok(q) => match db::with(|c| market::save(c, &q, jiff::Timestamp::now())) {
                        Some(Ok(changed)) => {
                            updated += usize::from(changed);
                            succeeded += 1;
                        }
                        _ => failed += 1,
                    },
                    Err(_) => failed += 1,
                }
            }
        }
        _ => failed += 1,
    }
    // Independent requests preserve successful quotes when a currency provider fails.
    match blocking(move || fetch_fx(today)).await {
        Ok(Ok(rows)) => {
            for result in rows {
                match result {
                    Ok(rate) => {
                        let saved = db::with(|c| {
                            use finance_core::currency;
                            if currency::rates(c)?.iter().any(|r| {
                                r.currency == rate.currency
                                    && r.day == rate.day
                                    && r.source == "manual"
                            }) {
                                return Ok::<_, currency::FxError>(false);
                            }
                            Ok(currency::save_rates(c, std::slice::from_ref(&rate))? > 0)
                        });
                        match saved {
                            Some(Ok(changed)) => {
                                updated += usize::from(changed);
                                succeeded += 1;
                            }
                            _ => failed += 1,
                        }
                    }
                    Err(_) => failed += 1,
                }
            }
        }
        _ => failed += 1,
    }
    if succeeded > 0
        && let Err(error) = super::valuation::capture(false)
    {
        log::warn!("market: valuation capture failed: {error}");
    }
    if load().is_err() || finance::load().is_err() {
        failed += 1
    }
    state().update(|s| {
        s.status = Status {
            refreshing: false,
            failed,
            updated,
        }
    });
    if succeeded > 0 {
        let from = today
            .checked_sub(jiff::Span::new().days(29))
            .unwrap_or(today);
        super::history::backfill(from, today, false).await;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    #[ignore = "explicit public-network smoke test"]
    fn foreign_quotes_and_ecb_fx_public_tls_smoke() {
        let bindings = [
            ("hk_stock", "00700", "HKD"),
            ("us_stock", "AAPL", "USD"),
            ("us_stock", "BRK.B", "USD"),
        ]
        .map(|(market, symbol, currency)| catalog::SecurityBinding {
            security: "smoke".into(),
            market: market.into(),
            symbol: symbol.into(),
            currency: currency.into(),
        });
        for (binding, result) in fetch(bindings.into()).unwrap() {
            let q = result.expect("valid foreign quote");
            q.validate(&binding, jiff::Timestamp::now()).unwrap();
            assert_eq!(q.currency, binding.currency);
        }
        for rate in fetch_fx(
            jiff::Timestamp::now()
                .to_zoned(jiff::tz::TimeZone::UTC)
                .date(),
        )
        .unwrap()
        {
            assert!(rate.expect("dated ECB rate").rate > 0);
        }
    }
    #[test]
    #[ignore = "explicit public-network smoke test"]
    fn tencent_public_quote_tls_smoke() {
        let binding = catalog::SecurityBinding {
            security: "smoke".into(),
            market: "cn_a".into(),
            symbol: "510300".into(),
            currency: "CNY".into(),
        };
        let rows = fetch(vec![binding.clone()]).expect("public request completes");
        assert_eq!(rows.len(), 1);
        let q = rows[0].1.as_ref().expect("provider returns a valid quote");
        q.validate(&binding, jiff::Timestamp::now()).unwrap();
        assert_eq!(q.symbol, "510300.SH");
        assert!(q.price > 0);
    }
}
