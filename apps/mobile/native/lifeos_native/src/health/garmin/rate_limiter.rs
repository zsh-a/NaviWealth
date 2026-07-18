//! Token-bucket rate limiter with 429 exponential backoff.
//!
//! Garmin Connect is aggressive with 429s. This limiter:
//! - Enforces max concurrent requests
//! - Enforces minimum interval between requests
//! - Exponential backoff on 429 responses

use std::sync::Arc;
use std::sync::atomic::{AtomicU32, Ordering};
use tokio::sync::Semaphore;
use tokio::time::{Duration, Instant, sleep};

/// Default max concurrent requests to Garmin API.
const DEFAULT_MAX_CONCURRENT: usize = 2;

/// Minimum delay between requests.
const DEFAULT_MIN_INTERVAL: Duration = Duration::from_millis(500);

/// Base backoff on 429.
const BASE_BACKOFF: Duration = Duration::from_secs(30);

/// Max backoff (5 minutes).
const MAX_BACKOFF: Duration = Duration::from_secs(300);

/// Rate limiter for Garmin API calls.
///
/// All state is behind `Arc`, so cloning shares the same semaphore
/// and backoff counters — identical to `GarminClient` clone semantics.
#[derive(Clone)]
pub struct GarminRateLimiter {
    semaphore: Arc<Semaphore>,
    min_interval: Duration,
    last_request: Arc<tokio::sync::Mutex<Option<Instant>>>,
    consecutive_429s: Arc<AtomicU32>,
}

impl GarminRateLimiter {
    pub fn new() -> Self {
        Self {
            semaphore: Arc::new(Semaphore::new(DEFAULT_MAX_CONCURRENT)),
            min_interval: DEFAULT_MIN_INTERVAL,
            last_request: Arc::new(tokio::sync::Mutex::new(None)),
            consecutive_429s: Arc::new(AtomicU32::new(0)),
        }
    }

    /// Run a request through the rate limiter.
    /// Acquires a semaphore permit, waits for min_interval, then executes.
    pub async fn run<F, Fut, T>(&self, request: F) -> anyhow::Result<T>
    where
        F: FnOnce() -> Fut,
        Fut: std::future::Future<Output = anyhow::Result<T>>,
    {
        // Wait for a concurrency slot.
        let _permit = self.semaphore.acquire().await?;

        // Enforce minimum interval.
        let mut last = self.last_request.lock().await;
        if let Some(prev) = *last {
            let elapsed = prev.elapsed();
            if elapsed < self.min_interval {
                sleep(self.min_interval - elapsed).await;
            }
        }
        *last = Some(Instant::now());
        drop(last);

        request().await
    }

    /// Call when a 429 is received. Returns the backoff duration.
    pub fn on_429(&self) -> Duration {
        let count = self.consecutive_429s.fetch_add(1, Ordering::Relaxed);
        let backoff = BASE_BACKOFF.mul_f64(2.0_f64.powi(count as i32));
        std::cmp::min(backoff, MAX_BACKOFF)
    }

    /// Call when a successful request is made. Resets 429 counter.
    pub fn on_success(&self) {
        self.consecutive_429s.store(0, Ordering::Relaxed);
    }

    /// Sleep for the 429 backoff duration.
    pub async fn backoff_sleep(&self) {
        let duration = self.on_429();
        sleep(duration).await;
    }
}

impl Default for GarminRateLimiter {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn first_429_returns_base_backoff() {
        let rl = GarminRateLimiter::new();
        let backoff = rl.on_429();
        assert_eq!(backoff, BASE_BACKOFF);
    }

    #[test]
    fn consecutive_429s_exponential_backoff() {
        let rl = GarminRateLimiter::new();
        let b1 = rl.on_429(); // 30s
        let b2 = rl.on_429(); // 60s
        let b3 = rl.on_429(); // 120s
        assert_eq!(b1, Duration::from_secs(30));
        assert_eq!(b2, Duration::from_secs(60));
        assert_eq!(b3, Duration::from_secs(120));
    }

    #[test]
    fn backoff_capped_at_max() {
        let rl = GarminRateLimiter::new();
        for _ in 0..10 {
            rl.on_429();
        }
        let backoff = rl.on_429();
        assert!(backoff <= MAX_BACKOFF);
    }

    #[test]
    fn success_resets_429_counter() {
        let rl = GarminRateLimiter::new();
        rl.on_429();
        rl.on_429();
        rl.on_success();
        let backoff = rl.on_429();
        assert_eq!(backoff, BASE_BACKOFF); // back to base
    }

    #[tokio::test]
    async fn run_executes_request() {
        let rl = GarminRateLimiter::new();
        let result = rl.run(|| async { Ok(42i32) }).await.unwrap();
        assert_eq!(result, 42);
    }

    #[tokio::test]
    async fn run_propagates_error() {
        let rl = GarminRateLimiter::new();
        let result: anyhow::Result<i32> = rl.run(|| async { Err(anyhow::anyhow!("fail")) }).await;
        assert!(result.is_err());
    }
}
