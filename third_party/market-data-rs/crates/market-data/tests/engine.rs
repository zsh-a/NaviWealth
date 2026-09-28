use async_trait::async_trait;
use chrono::{NaiveDate, Utc};
use market_data_rs::{
    cache::{Cache, MemoryCache, NoCache},
    provider::{
        Capabilities, HistoryProvider, ProviderContext, ProviderInfo, QuoteProvider, QuoteResults,
    },
    *,
};
use rust_decimal::Decimal;
use std::{
    sync::{
        Arc, Mutex,
        atomic::{AtomicUsize, Ordering},
    },
    time::Duration,
};

#[derive(Clone)]
struct Fixture {
    id: &'static str,
    calls: Arc<Mutex<Vec<Vec<Symbol>>>>,
    fail: Arc<AtomicUsize>,
    adjustments: Vec<Adjustment>,
    bars: Vec<Bar>,
    actual: Adjustment,
    max_batch: usize,
    omit: Option<Symbol>,
    delay: Duration,
}
impl Fixture {
    fn new(id: &'static str) -> Self {
        Self {
            id,
            calls: Arc::default(),
            fail: Arc::new(AtomicUsize::new(0)),
            adjustments: vec![Adjustment::Raw],
            bars: bars(),
            actual: Adjustment::Raw,
            max_batch: 50,
            omit: None,
            delay: Duration::ZERO,
        }
    }
}
impl Provider for Fixture {
    fn info(&self) -> ProviderInfo {
        ProviderInfo {
            id: self.id.into(),
            capabilities: Capabilities {
                exchanges: vec![Exchange::SSE, Exchange::SZSE, Exchange::BSE],
                quotes: true,
                max_quote_batch: self.max_batch,
                daily_adjustments: self.adjustments.clone(),
            },
        }
    }
    fn quotes(&self) -> Option<&dyn QuoteProvider> {
        Some(self)
    }
    fn history(&self) -> Option<&dyn HistoryProvider> {
        Some(self)
    }
}
#[async_trait]
impl QuoteProvider for Fixture {
    async fn fetch_quotes(&self, _: &ProviderContext, symbols: &[Symbol]) -> Result<QuoteResults> {
        self.calls.lock().unwrap().push(symbols.to_vec());
        tokio::time::sleep(self.delay).await;
        if self.fail.load(Ordering::SeqCst) > 0 {
            return Err(Error::new(ErrorKind::Network, "fixture unavailable"));
        }
        Ok(symbols
            .iter()
            .filter(|s| self.omit.as_ref() != Some(s))
            .map(|s| {
                (
                    s.clone(),
                    Ok(Quote {
                        symbol: s.clone(),
                        name: "fixture".into(),
                        currency: "CNY".into(),
                        price: Decimal::new(1234, 2),
                        previous_close: Some(Decimal::from(12)),
                        observed_at: Utc::now(),
                        previous_close_only: false,
                    }),
                )
            })
            .collect())
    }
}
#[async_trait]
impl HistoryProvider for Fixture {
    async fn fetch_daily(&self, _: &ProviderContext, req: &HistoryRequest) -> Result<HistoryPage> {
        self.calls.lock().unwrap().push(vec![req.symbol.clone()]);
        Ok(HistoryPage {
            symbol: req.symbol.clone(),
            adjustment: self.actual,
            bars: self.bars.clone(),
            warnings: vec![],
        })
    }
}
fn symbol() -> Symbol {
    "600519".parse().unwrap()
}
fn date(s: &str) -> NaiveDate {
    s.parse().unwrap()
}
fn bars() -> Vec<Bar> {
    ["2026-01-05", "2026-01-06", "2026-01-07"]
        .map(|s| Bar {
            date: date(s),
            open: Decimal::from(10),
            high: Decimal::from(12),
            low: Decimal::from(9),
            close: Decimal::from(11),
            volume_shares: Decimal::from(12300),
        })
        .to_vec()
}
fn request() -> HistoryRequest {
    HistoryRequest {
        symbol: symbol(),
        from: date("2026-01-05"),
        to: date("2026-01-07"),
        adjustment: Adjustment::Raw,
        allow_partial: false,
    }
}

#[test]
fn symbols_preserve_exchange_and_reject_invalid_unicode() {
    for s in ["600519", "sh600519", "600519.SH", "600519.SS"] {
        assert_eq!(s.parse::<Symbol>().unwrap(), symbol());
    }
    assert_ne!(
        "000001".parse::<Symbol>().unwrap(),
        "sh000001".parse::<Symbol>().unwrap()
    );
    assert_eq!(
        "920002".parse::<Symbol>().unwrap().exchange(),
        Exchange::BSE
    );
    for s in [
        "",
        "AAPL",
        "600519.HK",
        "9",
        "股票12345",
        "999999",
        "sh000001.SH",
    ] {
        assert!(s.parse::<Symbol>().is_err(), "{s}");
    }
}
#[tokio::test]
async fn external_provider_works_without_engine_changes_and_prices_are_strings() {
    let engine = MarketData::builder()
        .register(Fixture::new("fourth-provider"))
        .build()
        .unwrap();
    let data = engine
        .quote(symbol(), FetchOptions::default())
        .await
        .unwrap();
    assert_eq!(data.source, "fourth-provider");
    assert_eq!(
        serde_json::to_value(data).unwrap()["data"]["price"],
        "12.34"
    );
}
#[tokio::test]
async fn batch_deduplicates_and_retries_only_missing_symbols() {
    let a = symbol();
    let b: Symbol = "000001".parse().unwrap();
    let mut primary = Fixture::new("primary");
    primary.omit = Some(b.clone());
    let backup = Fixture::new("backup");
    let engine = MarketData::builder()
        .register(primary.clone())
        .register(backup.clone())
        .build()
        .unwrap();
    let result = engine
        .quotes(
            vec![a.clone(), b.clone(), a.clone()],
            FetchOptions::default(),
        )
        .await
        .unwrap();
    assert_eq!(result.len(), 3);
    assert_eq!(result[0].symbol, a);
    assert_eq!(result[2].symbol, a);
    assert_eq!(result[0].result.as_ref().unwrap().source, "primary");
    assert_eq!(result[1].result.as_ref().unwrap().source, "backup");
    assert_eq!(primary.calls.lock().unwrap()[0].len(), 2);
    assert_eq!(backup.calls.lock().unwrap()[0], vec![b]);
    assert_eq!(
        result[1].result.as_ref().unwrap().attempts[0].kind,
        ErrorKind::NoData
    );
}
#[tokio::test]
async fn batch_respects_provider_maximum() {
    let mut p = Fixture::new("small");
    p.max_batch = 1;
    let engine = MarketData::builder().register(p.clone()).build().unwrap();
    engine
        .quotes(
            vec![symbol(), "000001".parse().unwrap()],
            FetchOptions::default(),
        )
        .await
        .unwrap();
    assert_eq!(p.calls.lock().unwrap().len(), 2);
}
#[tokio::test]
async fn canonical_cache_and_concurrent_single_flight() {
    let mut p = Fixture::new("fixture");
    p.delay = Duration::from_millis(30);
    let engine = MarketData::builder().register(p.clone()).build().unwrap();
    let (a, b) = tokio::join!(
        engine.quote(symbol(), FetchOptions::default()),
        engine.quote("SH600519".parse().unwrap(), FetchOptions::default())
    );
    assert!(a.is_ok() && b.is_ok());
    assert_eq!(p.calls.lock().unwrap().len(), 1);
    assert_eq!(
        engine
            .quote(symbol(), FetchOptions::default())
            .await
            .unwrap()
            .freshness,
        Freshness::Cached
    );
}
#[tokio::test]
async fn stale_requires_explicit_opt_in_and_preserves_source_time() {
    let p = Fixture::new("fixture");
    let engine = MarketData::builder()
        .register(p.clone())
        .config(ServiceConfig {
            quote_ttl: Duration::ZERO,
            ..Default::default()
        })
        .build()
        .unwrap();
    let original = engine
        .quote(symbol(), FetchOptions::default())
        .await
        .unwrap();
    p.fail.store(1, Ordering::SeqCst);
    assert!(
        engine
            .quote(symbol(), FetchOptions::default())
            .await
            .is_err()
    );
    let stale = engine
        .quote(
            symbol(),
            FetchOptions {
                allow_stale: true,
                ..Default::default()
            },
        )
        .await
        .unwrap();
    assert_eq!(stale.freshness, Freshness::Stale);
    assert_eq!(stale.fetched_at, original.fetched_at);
    assert!(!stale.attempts.is_empty());
}
#[tokio::test]
async fn unsupported_adjustment_is_filtered_before_call() {
    let p = Fixture::new("raw-only");
    let engine = MarketData::builder().register(p.clone()).build().unwrap();
    let mut req = request();
    req.adjustment = Adjustment::Forward;
    assert_eq!(
        engine
            .history(req, FetchOptions::default())
            .await
            .unwrap_err()
            .kind,
        ErrorKind::Unsupported
    );
    assert!(p.calls.lock().unwrap().is_empty());
}
#[tokio::test]
async fn lying_adjustment_cannot_succeed() {
    let mut p = Fixture::new("lying");
    p.adjustments.push(Adjustment::Forward);
    let engine = MarketData::builder().register(p).build().unwrap();
    let mut req = request();
    req.adjustment = Adjustment::Forward;
    let error = engine
        .history(req, FetchOptions::default())
        .await
        .unwrap_err();
    assert_eq!(error.causes[0].kind, ErrorKind::Parse);
}
#[tokio::test]
async fn partial_history_falls_back_and_does_not_splice() {
    let partial = Fixture::new("partial");
    let mut full = Fixture::new("full");
    full.bars = (0..30)
        .map(|day| {
            let mut b = bars()[0].clone();
            b.date = date("2026-01-01") + chrono::Duration::days(day);
            b
        })
        .collect();
    let engine = MarketData::builder()
        .register(partial)
        .register(full)
        .build()
        .unwrap();
    let mut req = request();
    req.from = date("2026-01-01");
    req.to = date("2026-01-30");
    let data = engine.history(req, FetchOptions::default()).await.unwrap();
    assert_eq!(data.source, "full");
    assert_eq!(data.data.bars.len(), 30);
    assert_eq!(data.attempts[0].kind, ErrorKind::Incomplete);
}
#[tokio::test]
async fn partial_opt_in_does_not_pollute_strict_cache() {
    let engine = MarketData::builder()
        .register(Fixture::new("partial"))
        .build()
        .unwrap();
    let mut req = request();
    req.to = date("2026-02-01");
    req.allow_partial = true;
    assert!(
        !engine
            .history(req.clone(), FetchOptions::default())
            .await
            .unwrap()
            .data
            .coverage
            .boundary_check_passed
    );
    req.allow_partial = false;
    assert!(engine.history(req, FetchOptions::default()).await.is_err());
}
#[tokio::test]
async fn malformed_ohlc_and_conflicting_duplicates_fail() {
    for duplicate in [false, true] {
        let mut p = Fixture::new("broken");
        if duplicate {
            let mut b = p.bars[0].clone();
            b.close = Decimal::from(12);
            p.bars.push(b);
        } else {
            p.bars[0].high = Decimal::from(1);
        }
        let e = MarketData::builder()
            .register(p)
            .build()
            .unwrap()
            .history(request(), FetchOptions::default())
            .await
            .unwrap_err();
        assert_eq!(e.causes[0].kind, ErrorKind::Parse);
    }
}
#[tokio::test]
async fn deadline_cancels_work_and_releases_single_flight_lock() {
    let mut p = Fixture::new("slow");
    p.delay = Duration::from_millis(100);
    let engine = MarketData::builder()
        .register(p.clone())
        .cache(Arc::new(NoCache))
        .config(ServiceConfig {
            request_timeout: Duration::from_millis(15),
            ..Default::default()
        })
        .build()
        .unwrap();
    for _ in 0..2 {
        assert_eq!(
            engine
                .quote(symbol(), FetchOptions::default())
                .await
                .unwrap_err()
                .kind,
            ErrorKind::Timeout
        );
    }
    assert_eq!(p.calls.lock().unwrap().len(), 2);
}
#[tokio::test]
async fn memory_cache_is_bounded() {
    let cache = MemoryCache::new(1);
    cache.put("a", vec![1]).await.unwrap();
    cache.put("b", vec![2]).await.unwrap();
    assert!(cache.get("a").await.unwrap().is_none());
    assert_eq!(cache.get("b").await.unwrap(), Some(vec![2]));
}
#[test]
fn duplicate_provider_ids_are_rejected() {
    assert!(
        MarketData::builder()
            .register(Fixture::new("same"))
            .register(Fixture::new("same"))
            .build()
            .is_err()
    );
}

#[cfg(feature = "sqlite")]
#[tokio::test]
async fn sqlite_cache_survives_reopening() {
    let path = std::env::temp_dir().join(format!(
        "market-data-test-{}-{}.sqlite",
        std::process::id(),
        Utc::now().timestamp_nanos_opt().unwrap()
    ));
    {
        let c = market_data_rs::cache::SqliteCache::open(&path, 10).unwrap();
        c.put("persist", vec![1, 2, 3]).await.unwrap();
    }
    {
        let c = market_data_rs::cache::SqliteCache::open(&path, 10).unwrap();
        assert_eq!(c.get("persist").await.unwrap(), Some(vec![1, 2, 3]));
    }
    let _ = std::fs::remove_file(path);
}

/// Manual live smoke only; offline CI never depends on public provider availability.
#[tokio::test]
#[ignore = "requires public market endpoints"]
async fn live_public_quote_and_history() {
    let engine = MarketData::public_sources().unwrap();
    let quotes = engine
        .quotes(
            vec![
                symbol(),
                "000001".parse().unwrap(),
                "920002".parse().unwrap(),
            ],
            FetchOptions::default(),
        )
        .await
        .unwrap();
    for q in quotes {
        assert!(q.result.is_ok(), "{q:?}");
    }
    let to = Utc::now().date_naive();
    let data = engine
        .history(
            HistoryRequest {
                symbol: symbol(),
                from: to - chrono::Duration::days(40),
                to,
                adjustment: Adjustment::Forward,
                allow_partial: false,
            },
            FetchOptions::default(),
        )
        .await
        .unwrap();
    assert!(data.data.bars.len() > 10);
}
