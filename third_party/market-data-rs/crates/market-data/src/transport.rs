//! All provider HTTP requests (including pages/retries) pass through a shared quota bucket.
//! Buckets are process-local. Separate instances may share an Arc<HttpClient>.
use crate::{Error, ErrorKind, Result};
use futures_util::StreamExt;
use reqwest::{Client, StatusCode};
use serde::Serialize;
use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
    time::Duration,
};
use tokio::{
    sync::{Mutex as AsyncMutex, Semaphore},
    time::{Instant, sleep},
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HttpPolicy {
    pub min_interval: Duration,
    pub max_concurrent: usize,
    pub timeout: Duration,
    pub max_attempts: usize,
    pub circuit_failures: usize,
    pub circuit_cooldown: Duration,
    pub max_body_bytes: usize,
}
impl Default for HttpPolicy {
    fn default() -> Self {
        Self {
            min_interval: Duration::from_millis(500),
            max_concurrent: 2,
            timeout: Duration::from_secs(10),
            max_attempts: 2,
            circuit_failures: 3,
            circuit_cooldown: Duration::from_secs(30),
            max_body_bytes: 4 * 1024 * 1024,
        }
    }
}
impl HttpPolicy {
    pub fn validate(&self) -> Result<()> {
        if self.max_concurrent == 0
            || self.max_concurrent > 64
            || self.timeout.is_zero()
            || self.max_attempts == 0
            || self.max_attempts > 5
            || self.circuit_failures == 0
            || self.max_body_bytes == 0
            || self.circuit_cooldown.is_zero()
        {
            return Err(Error::new(ErrorKind::InvalidRequest, "invalid HTTP policy"));
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Default, Serialize)]
pub struct HttpStats {
    pub attempts: u64,
    pub successes: u64,
    pub failures: u64,
    pub circuit_rejections: u64,
}

/// Optional shared/distributed token quota. Called for every physical attempt.
/// Implementations should honor cancellation and keep credentials out of keys.
#[async_trait::async_trait]
pub trait QuotaLimiter: Send + Sync {
    async fn acquire(&self, quota_key: &str, cost: u32) -> Result<()>;
}

#[derive(Clone)]
pub struct HttpRequest {
    pub method: reqwest::Method,
    pub url: String,
    pub query: Vec<(String, String)>,
    pub headers: Vec<(String, String)>,
    pub json_body: Option<serde_json::Value>,
    /// Non-idempotent POSTs must leave this false.
    pub retry_safe: bool,
    pub cost: u32,
}
impl HttpRequest {
    pub fn get(url: impl Into<String>) -> Self {
        Self {
            method: reqwest::Method::GET,
            url: url.into(),
            query: vec![],
            headers: vec![],
            json_body: None,
            retry_safe: true,
            cost: 1,
        }
    }
}

struct Gate {
    next: Instant,
    open_until: Option<Instant>,
    failures: usize,
    generation: u64,
    stats: HttpStats,
}
struct Bucket {
    policy: HttpPolicy,
    permits: Semaphore,
    probe: Semaphore,
    gate: AsyncMutex<Gate>,
}

pub struct HttpClient {
    client: Client,
    buckets: Mutex<HashMap<String, Arc<Bucket>>>,
    limiter: Option<Arc<dyn QuotaLimiter>>,
}

impl HttpClient {
    pub fn new() -> Result<Self> {
        let client = Client::builder()
            .connect_timeout(Duration::from_secs(5))
            .redirect(reqwest::redirect::Policy::none())
            .user_agent("market-data-rs/0.1 (+A-share research client)")
            .build()
            .map_err(|_| Error::new(ErrorKind::Network, "cannot initialize HTTP client"))?;
        Ok(Self::with_client(client))
    }
    /// Inject a platform TLS/proxy-aware client. Policy deadlines still apply.
    pub fn with_client(client: Client) -> Self {
        Self {
            client,
            buckets: Mutex::new(HashMap::new()),
            limiter: None,
        }
    }

    pub fn with_limiter(mut self, limiter: Arc<dyn QuotaLimiter>) -> Self {
        self.limiter = Some(limiter);
        self
    }

    /// Quota keys can represent a provider, credential or shared upstream account.
    /// Register once; reuse the same key to share its limiter, concurrency and circuit.
    pub fn register(&self, key: &str, policy: HttpPolicy) -> Result<()> {
        policy.validate()?;
        let mut buckets = self.buckets.lock().unwrap();
        if let Some(bucket) = buckets.get(key) {
            return if bucket.policy == policy {
                Ok(())
            } else {
                Err(Error::new(
                    ErrorKind::InvalidRequest,
                    "conflicting policies for shared quota key",
                ))
            };
        }
        buckets.insert(
            key.into(),
            Arc::new(Bucket {
                permits: Semaphore::new(policy.max_concurrent),
                probe: Semaphore::new(1),
                policy,
                gate: AsyncMutex::new(Gate {
                    next: Instant::now(),
                    open_until: None,
                    failures: 0,
                    generation: 0,
                    stats: HttpStats::default(),
                }),
            }),
        );
        Ok(())
    }
    fn bucket(&self, key: &str) -> Result<Arc<Bucket>> {
        self.buckets
            .lock()
            .unwrap()
            .get(key)
            .cloned()
            .ok_or_else(|| Error::new(ErrorKind::InvalidRequest, "unregistered quota key"))
    }
    pub async fn stats(&self) -> HashMap<String, HttpStats> {
        let buckets: Vec<_> = self
            .buckets
            .lock()
            .unwrap()
            .iter()
            .map(|(k, v)| (k.clone(), v.clone()))
            .collect();
        let mut result = HashMap::new();
        for (key, bucket) in buckets {
            result.insert(key, bucket.gate.lock().await.stats.clone());
        }
        result
    }

    /// Safe read-only GET. URL/headers are never included in public errors.
    pub async fn get(
        &self,
        quota: &str,
        url: &str,
        params: &[(&str, String)],
        headers: &[(&str, &str)],
    ) -> Result<Vec<u8>> {
        let mut request = HttpRequest::get(url);
        request.query = params
            .iter()
            .map(|(k, v)| (k.to_string(), v.clone()))
            .collect();
        request.headers = headers
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect();
        self.send(quota, &request).await
    }

    /// Managed GET/POST transport for authenticated or custom providers.
    pub async fn send(&self, quota: &str, spec: &HttpRequest) -> Result<Vec<u8>> {
        if spec.cost == 0 || spec.cost > 1000 {
            return Err(Error::new(
                ErrorKind::InvalidRequest,
                "request cost must be 1..=1000",
            ));
        }
        let bucket = self.bucket(quota)?;
        for attempt in 0..bucket.policy.max_attempts {
            let mut _probe_permit = None;
            let permit = bucket
                .permits
                .acquire()
                .await
                .map_err(|_| Error::new(ErrorKind::Unavailable, "scheduler closed"))?;
            // Serialize admission, not the entire request; cancellation releases both guards.
            let generation = loop {
                let mut gate = bucket.gate.lock().await;
                let now = Instant::now();
                if gate.open_until.is_some_and(|until| until > now) {
                    gate.stats.circuit_rejections += 1;
                    return Err(Error::new(
                        ErrorKind::CircuitOpen,
                        "upstream circuit is cooling down",
                    ));
                }
                let wait = gate.next.saturating_duration_since(now);
                if !wait.is_zero() {
                    drop(gate);
                    sleep(wait).await;
                    continue;
                }
                // One half-open probe, including external quota waits; cancellation
                // drops its permit without leaving a permanent probing state.
                if gate.open_until.is_some() {
                    _probe_permit = Some(bucket.probe.try_acquire().map_err(|_| {
                        gate.stats.circuit_rejections += 1;
                        Error::new(
                            ErrorKind::CircuitOpen,
                            "upstream recovery probe in progress",
                        )
                    })?);
                    gate.generation += 1;
                    gate.failures = bucket.policy.circuit_failures - 1;
                }
                gate.next = Instant::now() + bucket.policy.min_interval * spec.cost;
                break gate.generation;
            };
            if let Some(limiter) = &self.limiter {
                limiter.acquire(quota, spec.cost).await?;
            }
            bucket.gate.lock().await.stats.attempts += 1;
            let mut request = self
                .client
                .request(spec.method.clone(), &spec.url)
                .query(&spec.query);
            for (name, value) in &spec.headers {
                request = request.header(name.as_str(), value.as_str());
            }
            if let Some(body) = &spec.json_body {
                request = request.json(body);
            }
            let response = tokio::time::timeout(bucket.policy.timeout, async {
                let response = request.send().await.map_err(map_network)?;
                let status = response.status();
                if !status.is_success() {
                    let retry_after = response
                        .headers()
                        .get("retry-after")
                        .and_then(|h| h.to_str().ok())
                        .and_then(parse_retry_after);
                    if let Some(delay) = retry_after.filter(|_| {
                        status == StatusCode::TOO_MANY_REQUESTS
                            || status == StatusCode::SERVICE_UNAVAILABLE
                    }) {
                        let mut gate = bucket.gate.lock().await;
                        gate.next = gate.next.max(Instant::now() + delay);
                    }
                    return Err(Error::new(
                        match status.as_u16() {
                            429 => ErrorKind::RateLimited,
                            404 => ErrorKind::NoData,
                            _ => ErrorKind::Http,
                        },
                        format!("upstream HTTP {}", status.as_u16()),
                    )
                    .with_http_status(status.as_u16()));
                }
                if response
                    .content_length()
                    .is_some_and(|n| n > bucket.policy.max_body_bytes as u64)
                {
                    return Err(Error::new(
                        ErrorKind::Parse,
                        "upstream response exceeds body limit",
                    ));
                }
                let mut stream = response.bytes_stream();
                let mut body = Vec::new();
                while let Some(chunk) = stream.next().await {
                    let chunk = chunk.map_err(map_network)?;
                    if body.len().saturating_add(chunk.len()) > bucket.policy.max_body_bytes {
                        return Err(Error::new(
                            ErrorKind::Parse,
                            "upstream response exceeds body limit",
                        ));
                    }
                    body.extend_from_slice(&chunk);
                }
                Ok(body)
            })
            .await
            .unwrap_or_else(|_| {
                Err(Error::new(
                    ErrorKind::Timeout,
                    "upstream request deadline exceeded",
                ))
            });
            drop(permit);
            let mut gate = bucket.gate.lock().await;
            match response {
                Ok(body) => {
                    // A request admitted before a later circuit opening must not close it.
                    if generation == gate.generation {
                        gate.failures = 0;
                        gate.open_until = None;
                    }
                    gate.stats.successes += 1;
                    return Ok(body);
                }
                Err(error) => {
                    gate.stats.failures += 1;
                    let retryable = matches!(
                        error.kind,
                        ErrorKind::Network | ErrorKind::Timeout | ErrorKind::RateLimited
                    ) || error
                        .http_status
                        .is_some_and(|status| (500..600).contains(&status));
                    if retryable && generation == gate.generation {
                        gate.failures += 1;
                        if gate.failures >= bucket.policy.circuit_failures {
                            gate.generation += 1;
                            gate.open_until = Some(Instant::now() + bucket.policy.circuit_cooldown);
                        }
                    }
                    if !retryable
                        || !spec.retry_safe
                        || attempt + 1 == bucket.policy.max_attempts
                        || gate.open_until.is_some()
                    {
                        return Err(error);
                    }
                    drop(gate);
                    // Small process-local jitter avoids synchronized retry waves.
                    let jitter = std::time::SystemTime::now()
                        .duration_since(std::time::UNIX_EPOCH)
                        .unwrap_or_default()
                        .subsec_millis()
                        % 150;
                    sleep(Duration::from_millis(
                        250 * (1 << attempt) + u64::from(jitter),
                    ))
                    .await;
                }
            }
        }
        unreachable!("validated nonzero attempt budget")
    }
}

fn map_network(error: reqwest::Error) -> Error {
    Error::new(
        if error.is_timeout() {
            ErrorKind::Timeout
        } else {
            ErrorKind::Network
        },
        "upstream transport failed",
    )
}
fn parse_retry_after(value: &str) -> Option<Duration> {
    if let Ok(seconds) = value.trim().parse::<u64>() {
        return Some(Duration::from_secs(seconds.min(86400)));
    }
    chrono::DateTime::parse_from_rfc2822(value)
        .ok()
        .map(|date| {
            (date.with_timezone(&chrono::Utc) - chrono::Utc::now())
                .to_std()
                .unwrap_or_default()
                .min(Duration::from_secs(86400))
        })
}
