//! Foreground-only public multi-market refresh. Network work stays off the UI thread.
use super::{clock, db, finance};
use market_data_rs::{
    FetchOptions, MarketData, Symbol, Tencent, cache::NoCache, transport::HttpClient,
};
use navi_finance::{
    catalog,
    currency::{Currency, FxRate},
    holdings,
    market::{self, MarketQuote},
};
use nsh_core::prelude::*;
use std::{
    sync::{
        Arc, OnceLock,
        atomic::{AtomicBool, Ordering},
    },
    time::Duration,
};

mod automatic;
pub(super) use automatic::generation;
pub use automatic::start;

#[derive(Clone, Default, PartialEq, Eq)]
struct Quotes(std::rc::Rc<Vec<MarketQuote>>);

fn publish_quotes(quotes: Vec<MarketQuote>) {
    let stored = global::<Quotes>();
    if stored.with_untracked(|s| *s.0 != quotes) {
        stored.set(Quotes(quotes.into()));
    }
}

/// Resolve visible price labels from one set of bindings and sampled quotes per list.
pub struct PriceSources {
    bindings: Vec<catalog::SecurityBinding>,
    quotes: std::rc::Rc<Vec<MarketQuote>>,
}

pub enum PriceSource {
    Manual,
    Close(String),
    Sampled {
        observed_at: jiff::Timestamp,
        previous_close: bool,
    },
}

impl PriceSources {
    pub fn current() -> Self {
        Self {
            bindings: super::catalog::bindings(),
            quotes: global::<Quotes>().with(|s| s.0.clone()),
        }
    }

    pub fn binding(&self, security: &str) -> Option<&catalog::SecurityBinding> {
        self.bindings.iter().find(|b| b.security == security)
    }

    pub fn source(&self, q: &holdings::Quote) -> Option<PriceSource> {
        db::with(|c| {
            if navi_finance::history::has_manual_price(c, q).ok()? {
                return Some(PriceSource::Manual);
            }
            let binding = self.binding(&q.security)?;
            if let Some(bar) = navi_finance::history::bars(c, binding, q.day, q.day)
                .ok()?
                .into_iter()
                .find(|b| b.close == q.price)
            {
                return Some(PriceSource::Close(bar.provider));
            }
            let symbol = market::canonical_binding(binding)?;
            self.quotes
                .iter()
                .find(|mark| {
                    mark.security == q.security
                        && mark.symbol == symbol
                        && mark.currency == binding.currency
                        && mark.price == q.price
                        && mark.day() == q.day
                })
                .map(|mark| PriceSource::Sampled {
                    observed_at: mark.observed_at,
                    previous_close: mark.previous_close_only,
                })
        })
        .flatten()
    }
}
pub fn load() -> Result<(), String> {
    let quotes = db::with(market::load)
        .ok_or("database unavailable")?
        .map_err(|e| e.to_string())?;
    publish_quotes(quotes);
    automatic::invalidate();
    Ok(())
}
/// Read committed price inputs together, then publish provenance and valuations in one batch.
pub(crate) fn reload_prices() -> Result<(), String> {
    let (quotes, book, rates) = db::with(|c| -> Result<_, String> {
        let tx = c.unchecked_transaction().map_err(|e| e.to_string())?;
        let quotes = market::load(&tx).map_err(|e| e.to_string())?;
        let current = finance::holdings_snapshot();
        let manual =
            holdings::store::manual_quotes(&tx, &current.securities).map_err(|e| e.to_string())?;
        let book = holdings::Book {
            securities: current.securities.clone(),
            trades: current.trades.clone(),
            quotes: manual,
        };
        let book =
            market::valued_book_with_quotes(&tx, book, &quotes).map_err(|e| e.to_string())?;
        let rates = navi_finance::currency::rates(&tx).map_err(|e| e.to_string())?;
        tx.commit().map_err(|e| e.to_string())?;
        Ok((quotes, book, rates))
    })
    .ok_or("database unavailable")??;
    batch(|| {
        publish_quotes(quotes);
        finance::publish_prices(book, rates);
    });
    Ok(())
}

pub(super) struct Client {
    pub(super) runtime: tokio::runtime::Runtime,
    service: MarketData,
    pub(super) http: reqwest::Client,
}
/// Whether quotes and exchange rates may come from the public providers.
static LIVE: AtomicBool = AtomicBool::new(true);

/// Turns the public providers off for this process. The market transport is
/// its own HTTP client, outside the engine's network, so a headless test's
/// stub network cannot answer it; without this a test's result would depend
/// on whether the machine can reach the providers.
pub fn disable_live() {
    LIVE.store(false, Ordering::Relaxed);
}

pub(super) fn client() -> Result<&'static Client, String> {
    if !LIVE.load(Ordering::Relaxed) {
        return Err("live market data disabled".to_owned());
    }
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
type FxResult = (Currency, Result<FxRate, String>);
fn fetch_fx(currencies: Vec<Currency>, today: jiff::civil::Date) -> Result<Vec<FxResult>, String> {
    let client = client()?;
    client.runtime.block_on(async {
        let mut rows = Vec::new();
        for currency in currencies {
            let result = async {
                let response = client.http.get(format!("https://api.frankfurter.dev/v2/providers/ecb/rates?base={currency}&quotes=CNY"))
                    .timeout(Duration::from_secs(12)).send().await.map_err(|_| "FX request failed")?
                    .error_for_status().map_err(|_| "FX request rejected")?;
                let bytes = response.bytes().await.map_err(|_| "FX response failed")?;
                if bytes.len() > 16384 { return Err("FX response too large".into()); }
                market::parse_fx(std::str::from_utf8(&bytes).map_err(|_| "invalid FX response")?, currency, today).map_err(|_| "invalid FX response".into())
            }.await;
            rows.push((currency, result));
        }
        Ok(rows)
    })
}
type FetchRates = fn(Vec<Currency>, jiff::civil::Date) -> Result<Vec<FxResult>, String>;

/// Keep successful observations even when a different provider is unavailable.
async fn update(
    fetch_rates: FetchRates,
    quotes: Vec<catalog::SecurityBinding>,
    currencies: Vec<Currency>,
    day: jiff::civil::Date,
    epoch: u64,
) {
    if quotes.is_empty() && currencies.is_empty() {
        return;
    }
    let mut changed = false;
    if !quotes.is_empty() {
        match blocking(move || fetch(quotes)).await {
            Ok(Ok(rows)) if generation() == epoch => {
                for (binding, result) in rows {
                    match result.and_then(|q| {
                        db::with(|c| market::save(c, &q, jiff::Timestamp::now()))
                            .ok_or("database unavailable")?
                            .map_err(|e| e.to_string())
                    }) {
                        Ok(saved) => changed |= saved,
                        Err(e) => log::warn!("quote {}: {e}", binding.symbol),
                    }
                }
            }
            _ => log::debug!("quote update unavailable or superseded"),
        }
    }
    if !currencies.is_empty() && generation() == epoch {
        match blocking(move || fetch_rates(currencies, day)).await {
            Ok(Ok(rows)) if generation() == epoch => {
                for (currency, result) in rows {
                    match result.and_then(|r| finance::store_rates(&[r])) {
                        Ok(n) => changed |= n > 0,
                        Err(e) => log::warn!("FX {currency}: {e}"),
                    }
                }
            }
            _ => log::debug!("FX update unavailable or superseded"),
        }
    }
    if changed && let Err(e) = reload_prices() {
        log::warn!("market: cannot publish prices: {e}");
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
        for (_, rate) in fetch_fx(
            vec![Currency::HKD, Currency::USD],
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
