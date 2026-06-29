use std::time::Duration;

#[derive(Clone)]
pub struct ExecutionPolicy {
    pub timeout: Duration,
    pub max_retries: u32,
    pub retry_backoff: Duration,
    pub max_concurrent_runs: usize,
}

impl Default for ExecutionPolicy {
    fn default() -> Self {
        Self {
            timeout: Duration::from_secs(60),
            max_retries: 0,
            retry_backoff: Duration::ZERO,
            max_concurrent_runs: 1,
        }
    }
}

impl ExecutionPolicy {
    pub(crate) fn lease_ttl(&self) -> Duration {
        let attempts = self.max_retries.saturating_add(1);
        self.timeout
            .saturating_mul(attempts)
            .saturating_add(self.retry_backoff.saturating_mul(self.max_retries))
    }
}
