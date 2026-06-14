//! HealthSyncEngine — cursor-based incremental sync across providers.
//!
//! Manages sync cursors so repeated calls don't re-fetch already-synced
//! date ranges. Returns `SyncOutcome` for the Dart shell to display.

use anyhow::Result;
use chrono::NaiveDate;
use serde::Serialize;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::Mutex;

use super::provider::{HealthProvider, HealthSnapshot};

/// Sync cursor: tracks the last synced date per provider.
pub type SyncCursors = HashMap<String, NaiveDate>;

/// Outcome of a sync operation.
#[derive(Debug, Clone, Serialize)]
pub struct SyncOutcome {
    /// Provider name.
    pub provider: String,
    /// Start date of this sync.
    pub from: NaiveDate,
    /// End date of this sync.
    pub to: NaiveDate,
    /// Number of daily metrics synced.
    pub metrics_count: usize,
    /// Number of activities synced.
    pub activities_count: usize,
    /// Error messages (if any partial failures occurred).
    pub errors: Vec<String>,
    /// Duration in milliseconds.
    pub duration_ms: u64,
}

/// Health sync engine.
pub struct HealthSyncEngine {
    providers: HashMap<String, Arc<dyn HealthProvider>>,
    cursors: Arc<Mutex<SyncCursors>>,
}

impl HealthSyncEngine {
    pub fn new() -> Self {
        Self {
            providers: HashMap::new(),
            cursors: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    /// Register a provider.
    pub fn add_provider(&mut self, provider: Arc<dyn HealthProvider>) {
        self.providers.insert(provider.name().to_string(), provider);
    }

    /// Sync all providers for the given range.
    pub async fn sync_range(&self, from: NaiveDate, to: NaiveDate) -> Result<Vec<SyncOutcome>> {
        let mut outcomes = Vec::new();
        for (name, _provider) in &self.providers {
            match self.sync_provider(name, from, to).await {
                Ok(outcome) => outcomes.push(outcome),
                Err(e) => outcomes.push(SyncOutcome {
                    provider: name.clone(),
                    from,
                    to,
                    metrics_count: 0,
                    activities_count: 0,
                    errors: vec![e.to_string()],
                    duration_ms: 0,
                }),
            }
        }
        Ok(outcomes)
    }

    /// Sync a single provider, using the cursor to avoid re-fetching.
    pub async fn sync_provider(
        &self,
        provider_name: &str,
        from: NaiveDate,
        to: NaiveDate,
    ) -> Result<SyncOutcome> {
        let provider = self
            .providers
            .get(provider_name)
            .ok_or_else(|| anyhow::anyhow!("Provider not found: {provider_name}"))?;

        let start = std::time::Instant::now();
        let mut errors = Vec::new();

        // Use cursor to avoid re-fetching.
        let effective_from = {
            let cursors = self.cursors.lock().await;
            cursors
                .get(provider_name)
                .copied()
                .map(|cursor| std::cmp::max(from, cursor + chrono::Duration::days(1)))
                .unwrap_or(from)
        };

        if effective_from > to {
            return Ok(SyncOutcome {
                provider: provider_name.to_string(),
                from,
                to,
                metrics_count: 0,
                activities_count: 0,
                errors: vec![],
                duration_ms: start.elapsed().as_millis() as u64,
            });
        }

        // Sync daily metrics.
        let snapshot = match provider.sync_daily_range(effective_from, to).await {
            Ok(s) => s,
            Err(e) => {
                errors.push(format!("daily sync failed: {e}"));
                HealthSnapshot::default()
            }
        };

        let metrics_count = snapshot.steps.len()
            + snapshot.sleep_sessions.len()
            + snapshot.resting_hr.len()
            + snapshot.hrv.len()
            + snapshot.heart_rate.len()
            + snapshot.active_energy.len()
            + snapshot.distance_walking_running.len()
            + snapshot.total_energy.len()
            + snapshot.vo2_max.len()
            + snapshot.weight.len()
            + snapshot.body_fat.len()
            + snapshot.floors_climbed.len()
            + snapshot.respiratory_rate.len()
            + snapshot.body_battery.len()
            + snapshot.stress.len()
            + snapshot.training_load.len()
            + snapshot.training_effect.len()
            + snapshot.spo2.len();

        // Sync activities.
        let activities = match provider.sync_activities(effective_from, to).await {
            Ok(a) => a,
            Err(e) => {
                if !is_optional_activity_error(&e) {
                    errors.push(format!("activity sync failed: {e}"));
                }
                vec![]
            }
        };
        let activities_count = activities.len();

        // Update cursor.
        {
            let mut cursors = self.cursors.lock().await;
            cursors.insert(provider_name.to_string(), to);
        }

        Ok(SyncOutcome {
            provider: provider_name.to_string(),
            from: effective_from,
            to,
            metrics_count,
            activities_count,
            errors,
            duration_ms: start.elapsed().as_millis() as u64,
        })
    }

    /// Get current cursors.
    pub async fn cursors(&self) -> SyncCursors {
        self.cursors.lock().await.clone()
    }

    /// Set a cursor (for restoring from persistence).
    pub async fn set_cursor(&self, provider: String, date: NaiveDate) {
        self.cursors.lock().await.insert(provider, date);
    }
}

fn is_optional_activity_error(error: &anyhow::Error) -> bool {
    let msg = error.to_string().to_lowercase();
    msg.contains("404 not found") || msg.contains("garmin api error: 404")
}

impl Default for HealthSyncEngine {
    fn default() -> Self {
        Self::new()
    }
}
