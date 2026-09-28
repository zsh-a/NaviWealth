use crate::{
    cache::{Cache, MemoryCache},
    provider::{ProviderContext, ProviderInfo},
    transport::{HttpClient, HttpPolicy},
    *,
};
use chrono::Utc;
use serde::{Serialize, de::DeserializeOwned};
use std::{
    collections::{HashMap, HashSet},
    sync::{Arc, Mutex, Weak},
    time::Duration,
};
use tokio::sync::{Mutex as AsyncMutex, OwnedMutexGuard};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Operation {
    Quotes,
    DailyHistory,
}

/// Lower scores are tried first. Capability filtering happens before ranking.
pub trait RoutePolicy: Send + Sync {
    fn rank(&self, provider: &ProviderInfo, operation: Operation) -> i32;
}
#[derive(Default)]
pub struct PriorityRouting {
    pub quote_order: Vec<String>,
    pub history_order: Vec<String>,
}
impl RoutePolicy for PriorityRouting {
    fn rank(&self, provider: &ProviderInfo, operation: Operation) -> i32 {
        let order = if operation == Operation::Quotes {
            &self.quote_order
        } else {
            &self.history_order
        };
        order
            .iter()
            .position(|p| p == &provider.id)
            .map(|p| p as i32)
            .unwrap_or(1000)
    }
}

#[derive(Debug, Clone)]
pub struct Event {
    pub provider: Option<String>,
    pub operation: Operation,
    pub kind: &'static str,
}
/// Callbacks must be fast and non-blocking. No prices, credentials or URLs are emitted.
pub trait Observer: Send + Sync {
    fn observe(&self, event: Event);
}
struct NoObserver;
impl Observer for NoObserver {
    fn observe(&self, _: Event) {}
}

#[derive(Debug, Clone)]
pub struct ServiceConfig {
    pub request_timeout: Duration,
    pub quote_ttl: Duration,
    pub history_ttl: Duration,
    pub max_stale_age: Duration,
    pub max_quote_batch: usize,
}
impl Default for ServiceConfig {
    fn default() -> Self {
        Self {
            request_timeout: Duration::from_secs(30),
            quote_ttl: Duration::from_secs(30),
            history_ttl: Duration::from_secs(3600),
            max_stale_age: Duration::from_secs(7 * 86400),
            max_quote_batch: 100,
        }
    }
}

struct Entry {
    provider: Arc<dyn Provider>,
    info: ProviderInfo,
    context: ProviderContext,
}
struct Inner {
    entries: Vec<Entry>,
    cache: Arc<dyn Cache>,
    config: ServiceConfig,
    routing: Arc<dyn RoutePolicy>,
    observer: Arc<dyn Observer>,
    locks: Mutex<HashMap<String, Weak<AsyncMutex<()>>>>,
    http: Arc<HttpClient>,
}
#[derive(Clone)]
pub struct MarketData(Arc<Inner>);

pub struct MarketDataBuilder {
    providers: Vec<Arc<dyn Provider>>,
    cache: Arc<dyn Cache>,
    config: ServiceConfig,
    routing: Arc<dyn RoutePolicy>,
    observer: Arc<dyn Observer>,
    http: Option<Arc<HttpClient>>,
    policies: HashMap<String, HttpPolicy>,
    quota_keys: HashMap<String, String>,
}
impl Default for MarketDataBuilder {
    fn default() -> Self {
        Self {
            providers: vec![],
            cache: Arc::new(MemoryCache::default()),
            config: ServiceConfig::default(),
            routing: Arc::new(PriorityRouting::default()),
            observer: Arc::new(NoObserver),
            http: None,
            policies: HashMap::new(),
            quota_keys: HashMap::new(),
        }
    }
}
impl MarketDataBuilder {
    pub fn new() -> Self {
        Self::default()
    }
    pub fn register(mut self, provider: impl Provider + 'static) -> Self {
        self.providers.push(Arc::new(provider));
        self
    }
    pub fn cache(mut self, cache: Arc<dyn Cache>) -> Self {
        self.cache = cache;
        self
    }
    pub fn config(mut self, config: ServiceConfig) -> Self {
        self.config = config;
        self
    }
    pub fn routing(mut self, routing: Arc<dyn RoutePolicy>) -> Self {
        self.routing = routing;
        self
    }
    pub fn observer(mut self, observer: Arc<dyn Observer>) -> Self {
        self.observer = observer;
        self
    }
    pub fn http(mut self, http: Arc<HttpClient>) -> Self {
        self.http = Some(http);
        self
    }
    pub fn quota(mut self, provider_id: &str, quota_key: &str) -> Self {
        self.quota_keys.insert(provider_id.into(), quota_key.into());
        self
    }
    pub fn http_policy(mut self, quota_key: &str, policy: HttpPolicy) -> Self {
        self.policies.insert(quota_key.into(), policy);
        self
    }
    pub fn build(self) -> Result<MarketData> {
        if self.config.request_timeout.is_zero()
            || self.config.max_quote_batch == 0
            || self.config.max_quote_batch > 1000
        {
            return Err(Error::new(
                ErrorKind::InvalidRequest,
                "invalid service limits",
            ));
        }
        let http = match self.http {
            Some(http) => http,
            None => Arc::new(HttpClient::new()?),
        };
        let mut entries = Vec::new();
        let mut ids = HashSet::new();
        for provider in self.providers {
            let info = provider.info();
            if info.id.is_empty()
                || !ids.insert(info.id.clone())
                || (info.capabilities.quotes
                    && (provider.quotes().is_none() || info.capabilities.max_quote_batch == 0))
                || (!info.capabilities.daily_adjustments.is_empty() && provider.history().is_none())
            {
                return Err(Error::new(
                    ErrorKind::InvalidRequest,
                    "duplicate provider id or inconsistent capabilities",
                ));
            }
            let key = self
                .quota_keys
                .get(&info.id)
                .cloned()
                .unwrap_or_else(|| info.id.clone());
            http.register(&key, self.policies.get(&key).cloned().unwrap_or_default())?;
            entries.push(Entry {
                provider,
                info,
                context: ProviderContext {
                    http: http.clone(),
                    quota_key: key,
                },
            });
        }
        if entries.is_empty() {
            return Err(Error::new(
                ErrorKind::InvalidRequest,
                "register at least one provider",
            ));
        }
        Ok(MarketData(Arc::new(Inner {
            entries,
            cache: self.cache,
            config: self.config,
            routing: self.routing,
            observer: self.observer,
            locks: Mutex::new(HashMap::new()),
            http,
        })))
    }
}

impl MarketData {
    pub fn builder() -> MarketDataBuilder {
        MarketDataBuilder::new()
    }
    pub fn public_sources() -> Result<Self> {
        Self::builder()
            .register(Tencent)
            .register(Sina)
            .register(Eastmoney)
            .routing(Arc::new(PriorityRouting {
                quote_order: vec!["tencent".into(), "sina".into()],
                history_order: vec!["tencent".into(), "eastmoney".into(), "sina".into()],
            }))
            // Eastmoney frequently disconnects: fail fast instead of amplifying load.
            .http_policy(
                "eastmoney",
                HttpPolicy {
                    max_attempts: 1,
                    ..Default::default()
                },
            )
            .build()
    }
    pub fn providers(&self) -> Vec<ProviderInfo> {
        self.0.entries.iter().map(|e| e.info.clone()).collect()
    }
    pub async fn http_stats(&self) -> HashMap<String, crate::transport::HttpStats> {
        self.0.http.stats().await
    }

    pub async fn quote(&self, symbol: Symbol, options: FetchOptions) -> Result<Data<Quote>> {
        self.quotes(vec![symbol], options).await?.remove(0).result
    }
    /// Input order and duplicate occurrences are preserved. Upstream requests are deduplicated.
    /// Deadline/invalid input fails the operation; provider errors are per-symbol outcomes.
    pub async fn quotes(
        &self,
        symbols: Vec<Symbol>,
        options: FetchOptions,
    ) -> Result<Vec<QuoteOutcome>> {
        if symbols.is_empty() || symbols.len() > self.0.config.max_quote_batch {
            return Err(Error::new(
                ErrorKind::InvalidRequest,
                "quote batch is empty or too large",
            ));
        }
        self.deadline(self.quotes_inner(symbols, options)).await
    }
    async fn quotes_inner(
        &self,
        symbols: Vec<Symbol>,
        options: FetchOptions,
    ) -> Result<Vec<QuoteOutcome>> {
        let started = Utc::now();
        let mut unique = symbols.clone();
        unique.sort_by_key(ToString::to_string);
        unique.dedup();
        let keys: Vec<_> = unique.iter().map(quote_key).collect();
        let _guards = self.lock_keys(keys).await;
        let mut results: HashMap<Symbol, Result<Data<Quote>>> = HashMap::new();
        let mut stale = HashMap::new();
        let mut causes: HashMap<Symbol, Vec<Error>> = HashMap::new();
        for symbol in &unique {
            if let Some(data) = self
                .read::<Quote>(&quote_key(symbol), Operation::Quotes)
                .await
                && data.data.validate(symbol).is_ok()
                && self.source_registered(&data.source)
            {
                if self.fresh(&data, self.0.config.quote_ttl, options, started) {
                    self.event(None, Operation::Quotes, "cache_hit");
                    results.insert(
                        symbol.clone(),
                        Ok(Data {
                            freshness: Freshness::Cached,
                            ..data
                        }),
                    );
                } else {
                    stale.insert(symbol.clone(), data);
                }
            }
        }
        for entry in self.ranked(Operation::Quotes) {
            if !entry.info.capabilities.quotes {
                continue;
            }
            let pending: Vec<_> = unique
                .iter()
                .filter(|s| {
                    !results.contains_key(*s)
                        && entry.info.capabilities.exchanges.contains(&s.exchange())
                })
                .cloned()
                .collect();
            for batch in pending.chunks(entry.info.capabilities.max_quote_batch) {
                self.event(Some(&entry.info.id), Operation::Quotes, "provider_attempt");
                let response = entry
                    .provider
                    .quotes()
                    .unwrap()
                    .fetch_quotes(&entry.context, batch)
                    .await;
                for symbol in batch {
                    let result = match &response {
                        Ok(map) => map.get(symbol).cloned().unwrap_or_else(|| {
                            Err(Error::new(
                                ErrorKind::NoData,
                                "provider omitted requested symbol",
                            ))
                        }),
                        Err(e) => Err(e.clone()),
                    }
                    .and_then(|quote| {
                        quote.validate(symbol)?;
                        Ok(quote)
                    });
                    match result {
                        Ok(quote) => {
                            let mut data = Data {
                                data: quote,
                                source: entry.info.id.clone(),
                                fetched_at: Utc::now(),
                                freshness: Freshness::Network,
                                warnings: vec![],
                                attempts: causes.remove(symbol).unwrap_or_default(),
                            };
                            if data.data.previous_close_only {
                                data.warnings
                                    .push("current price unavailable; using previous close".into());
                            }
                            self.write(&quote_key(symbol), &mut data, Operation::Quotes)
                                .await;
                            results.insert(symbol.clone(), Ok(data));
                        }
                        Err(error) => {
                            let error = error.at(&entry.info.id);
                            if error.kind == ErrorKind::InvalidRequest {
                                results.insert(symbol.clone(), Err(error));
                            } else {
                                causes.entry(symbol.clone()).or_default().push(error);
                            }
                        }
                    }
                }
            }
        }
        for symbol in unique {
            if results.contains_key(&symbol) {
                continue;
            }
            let errors = causes.remove(&symbol).unwrap_or_default();
            let value = if let Some(data) = stale
                .remove(&symbol)
                .filter(|d| options.allow_stale && self.within_age(d, self.0.config.max_stale_age))
            {
                self.event(None, Operation::Quotes, "stale_fallback");
                Ok(Data {
                    freshness: Freshness::Stale,
                    attempts: errors,
                    ..data
                })
            } else {
                Err(if errors.is_empty() {
                    Error::new(
                        ErrorKind::Unsupported,
                        "no provider supports this quote request",
                    )
                } else {
                    Error::unavailable(errors)
                })
            };
            results.insert(symbol, value);
        }
        Ok(symbols
            .into_iter()
            .map(|symbol| QuoteOutcome {
                result: results[&symbol].clone(),
                symbol,
            })
            .collect())
    }
    pub async fn history(
        &self,
        request: HistoryRequest,
        options: FetchOptions,
    ) -> Result<Data<History>> {
        request.validate()?;
        self.deadline(self.history_inner(request, options)).await
    }
    async fn history_inner(
        &self,
        request: HistoryRequest,
        options: FetchOptions,
    ) -> Result<Data<History>> {
        let started = Utc::now();
        let key = history_key(&request);
        let _guards = self.lock_keys(vec![key.clone()]).await;
        let cached = self
            .read::<History>(&key, Operation::DailyHistory)
            .await
            .filter(|d| {
                self.source_registered(&d.source) && valid_cached_history(&d.data, &request)
            });
        if let Some(data) = cached
            .as_ref()
            .filter(|d| self.fresh(d, self.0.config.history_ttl, options, started))
        {
            self.event(None, Operation::DailyHistory, "cache_hit");
            return Ok(Data {
                freshness: Freshness::Cached,
                ..data.clone()
            });
        }
        let mut errors = Vec::new();
        let mut partial: Option<Data<History>> = None;
        for entry in self.ranked(Operation::DailyHistory) {
            let caps = &entry.info.capabilities;
            if !caps.exchanges.contains(&request.symbol.exchange())
                || !caps.daily_adjustments.contains(&request.adjustment)
            {
                continue;
            }
            self.event(
                Some(&entry.info.id),
                Operation::DailyHistory,
                "provider_attempt",
            );
            let response = entry
                .provider
                .history()
                .unwrap()
                .fetch_daily(&entry.context, &request)
                .await
                .and_then(|p| normalize_history(p, &request));
            match response {
                Ok(history) => {
                    let mut data = Data {
                        data: history,
                        source: entry.info.id.clone(),
                        fetched_at: Utc::now(),
                        freshness: Freshness::Network,
                        warnings: vec![],
                        attempts: errors.clone(),
                    };
                    if !data.data.coverage.boundary_check_passed {
                        errors.push(
                            Error::new(
                                ErrorKind::Incomplete,
                                "history fails conservative boundary/gap screening",
                            )
                            .at(&entry.info.id),
                        );
                        // Keep one whole provider series; never splice price bases.
                        if partial
                            .as_ref()
                            .is_none_or(|old| old.data.bars.len() < data.data.bars.len())
                        {
                            partial = Some(data);
                        }
                        continue;
                    }
                    self.write(&key, &mut data, Operation::DailyHistory).await;
                    return Ok(data);
                }
                Err(error) => {
                    if error.kind == ErrorKind::InvalidRequest {
                        return Err(error.at(&entry.info.id));
                    }
                    errors.push(error.at(&entry.info.id));
                }
            }
        }
        if request.allow_partial
            && let Some(mut data) = partial
        {
            data.attempts = errors;
            data.warnings.push("partial history explicitly accepted; unsuitable for complete-range return calculations".into());
            // Do not cache partial results as a fresh success that would suppress recovery.
            return Ok(data);
        }
        if let Some(data) = cached
            .filter(|d| options.allow_stale && self.within_age(d, self.0.config.max_stale_age))
        {
            return Ok(Data {
                freshness: Freshness::Stale,
                attempts: errors,
                ..data
            });
        }
        Err(if errors.is_empty() {
            Error::new(
                ErrorKind::Unsupported,
                "no provider supports this history capability",
            )
        } else {
            Error::unavailable(errors)
        })
    }
    async fn deadline<T>(&self, future: impl std::future::Future<Output = Result<T>>) -> Result<T> {
        tokio::time::timeout(self.0.config.request_timeout, future)
            .await
            .unwrap_or_else(|_| {
                Err(Error::new(
                    ErrorKind::Timeout,
                    "total deadline exceeded, including queue/retries/fallback",
                ))
            })
    }
    fn ranked(&self, operation: Operation) -> Vec<&Entry> {
        let mut entries: Vec<_> = self.0.entries.iter().collect();
        entries.sort_by_key(|e| self.0.routing.rank(&e.info, operation));
        entries
    }
    fn source_registered(&self, source: &str) -> bool {
        self.0.entries.iter().any(|e| e.info.id == source)
    }
    fn within_age<T>(&self, data: &Data<T>, duration: Duration) -> bool {
        (Utc::now() - data.fetched_at)
            .to_std()
            .is_ok_and(|age| age <= duration)
    }
    fn fresh<T>(
        &self,
        data: &Data<T>,
        ttl: Duration,
        options: FetchOptions,
        started: chrono::DateTime<Utc>,
    ) -> bool {
        self.within_age(data, ttl) && (!options.refresh || data.fetched_at >= started)
    }
    async fn read<T: DeserializeOwned>(&self, key: &str, operation: Operation) -> Option<Data<T>> {
        match self.0.cache.get(key).await {
            Ok(Some(bytes)) => match serde_json::from_slice(&bytes) {
                Ok(data) => Some(data),
                Err(_) => {
                    self.event(None, operation, "cache_corrupt");
                    None
                }
            },
            Ok(None) => None,
            Err(_) => {
                self.event(None, operation, "cache_read_failed");
                None
            }
        }
    }
    async fn write<T: Serialize>(&self, key: &str, data: &mut Data<T>, operation: Operation) {
        let bytes = match serde_json::to_vec(data) {
            Ok(b) => b,
            Err(_) => {
                data.warnings.push("cache serialization failed".into());
                return;
            }
        };
        if self.0.cache.put(key, bytes).await.is_err() {
            self.event(None, operation, "cache_write_failed");
            data.warnings
                .push("cache write failed; network data remains usable".into());
        }
    }
    fn event(&self, provider: Option<&str>, operation: Operation, kind: &'static str) {
        self.0.observer.observe(Event {
            provider: provider.map(str::to_owned),
            operation,
            kind,
        });
    }
    async fn lock_keys(&self, mut keys: Vec<String>) -> Vec<OwnedMutexGuard<()>> {
        keys.sort();
        keys.dedup();
        let locks: Vec<_> = {
            let mut map = self.0.locks.lock().unwrap();
            map.retain(|_, v| v.strong_count() > 0);
            keys.iter()
                .map(|key| {
                    if let Some(lock) = map.get(key).and_then(Weak::upgrade) {
                        return lock;
                    }
                    let lock = Arc::new(AsyncMutex::new(()));
                    map.insert(key.clone(), Arc::downgrade(&lock));
                    lock
                })
                .collect()
        };
        let mut guards = Vec::new();
        for lock in locks {
            guards.push(lock.lock_owned().await);
        }
        guards
    }
}

fn quote_key(symbol: &Symbol) -> String {
    format!("v1:quote:{symbol}")
}
fn history_key(req: &HistoryRequest) -> String {
    format!(
        "v1:daily:{}:{}:{}:{:?}",
        req.symbol, req.from, req.to, req.adjustment
    )
}
fn valid_cached_history(h: &History, req: &HistoryRequest) -> bool {
    h.symbol == req.symbol
        && h.adjustment == req.adjustment
        && h.coverage.requested_from == req.from
        && h.coverage.requested_to == req.to
        && h.coverage.boundary_check_passed
        && !h.bars.is_empty()
        && h.bars
            .iter()
            .all(|b| b.date >= req.from && b.date <= req.to && b.validate().is_ok())
}

fn normalize_history(page: HistoryPage, req: &HistoryRequest) -> Result<History> {
    if page.symbol != req.symbol || page.adjustment != req.adjustment {
        return Err(Error::new(
            ErrorKind::Parse,
            "provider returned a different security or adjustment",
        ));
    }
    let mut bars: Vec<_> = page
        .bars
        .into_iter()
        .filter(|b| b.date >= req.from && b.date <= req.to)
        .collect();
    if bars.is_empty() {
        return Err(Error::new(
            ErrorKind::NoData,
            "no daily bars in requested range (not authoritative absence)",
        ));
    }
    bars.sort_by_key(|b| b.date);
    for bar in &bars {
        bar.validate()?;
    }
    for pair in bars.windows(2) {
        if pair[0].date == pair[1].date
            && (pair[0].open != pair[1].open
                || pair[0].high != pair[1].high
                || pair[0].low != pair[1].low
                || pair[0].close != pair[1].close
                || pair[0].volume_shares != pair[1].volume_shares)
        {
            return Err(Error::new(
                ErrorKind::Parse,
                "conflicting duplicate history dates",
            ));
        }
    }
    bars.dedup_by_key(|b| b.date);
    let first = bars[0].date;
    let last = bars.last().unwrap().date;
    // This is explicitly NOT a trading-calendar completeness certificate. Long closures,
    // IPOs and suspensions can fail conservatively; callers may opt into partial history.
    let passed = (first - req.from).num_days() <= 7
        && (req.to - last).num_days() <= 7
        && !bars
            .windows(2)
            .any(|p| (p[1].date - p[0].date).num_days() > 14);
    let mut warnings = page.warnings;
    let china_today = Utc::now()
        .with_timezone(&chrono::FixedOffset::east_opt(8 * 3600).unwrap())
        .date_naive();
    if last == china_today {
        warnings.push("current trading-day bar may be unfinished; exclude it from completed-day return calculations".into());
    }
    warnings.push("coverage is calendar-gap screening, not verified against exchange sessions or listing/suspension dates".into());
    if !passed {
        warnings
            .push("requested window may be truncated, suspended or beyond listing history".into());
    }
    Ok(History {
        symbol: req.symbol.clone(),
        adjustment: req.adjustment,
        bars,
        coverage: Coverage {
            requested_from: req.from,
            requested_to: req.to,
            first,
            last,
            boundary_check_passed: passed,
            warnings,
        },
    })
}
