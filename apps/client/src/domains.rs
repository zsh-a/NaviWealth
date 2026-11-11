//! The lightweight domain registry: each opt-in domain declares its
//! settings key, tab and screen wiring in one place (the spirit of the
//! Flutter `domain_packs.dart`). Finance is always on; knowledge,
//! execution and health default to off and are enabled from settings.
//! The enabled set lives in the settings KV and is mirrored in-memory on
//! `Services`, so sync and AI composition follow the switches immediately.

use std::sync::Arc;

use lifeos::sync::SyncRegistry;
use nsh_core::prelude::*;

use crate::state::Services;

/// One opt-in domain's registration.
pub struct DomainSpec {
    /// Stable key (also the sync-domain prefix name).
    pub key: &'static str,
    /// Registry label.
    pub label: &'static str,
    /// Tab label shown when enabled.
    pub tab_label: &'static str,
    /// Tab bar test id.
    pub tab_test_id: &'static str,
    /// Settings toggle test id.
    pub toggle_test_id: &'static str,
    /// Tab index in the shell (after the four base tabs).
    pub tab_index: u8,
    /// Settings KV key holding `1`/`0`.
    pub enabled_key: &'static str,
}

pub const KNOWLEDGE: DomainSpec = DomainSpec {
    key: "knowledge",
    label: "知识",
    tab_label: "笔记",
    tab_test_id: "tab-knowledge",
    toggle_test_id: "domain-toggle-knowledge",
    tab_index: 4,
    enabled_key: "domain.knowledge.enabled",
};

pub const EXECUTION: DomainSpec = DomainSpec {
    key: "execution",
    label: "执行",
    tab_label: "执行",
    tab_test_id: "tab-execution",
    toggle_test_id: "domain-toggle-execution",
    tab_index: 5,
    enabled_key: "domain.execution.enabled",
};

pub const HEALTH: DomainSpec = DomainSpec {
    key: "health",
    label: "健康",
    tab_label: "健康",
    tab_test_id: "tab-health",
    toggle_test_id: "domain-toggle-health",
    tab_index: 6,
    enabled_key: "domain.health.enabled",
};

/// The opt-in domains, in tab order.
pub const OPTIONAL_DOMAINS: [&DomainSpec; 3] = [&KNOWLEDGE, &EXECUTION, &HEALTH];

/// Shared UI state: the enabled domain keys (reactive so tabs and screens
/// appear the moment the switch flips).
#[derive(Clone, Copy)]
pub struct DomainsState(pub Signal<Vec<&'static str>>);

impl DomainsState {
    pub fn is_enabled(&self, key: &'static str) -> bool {
        self.0.get().contains(&key)
    }
}

/// The sync registry for the current switch state: finance always, each
/// enabled domain's row families added on top.
pub fn sync_registry_for(enabled: &[&str]) -> SyncRegistry {
    let mut registry = naviwealth_finance::tables::sync_registry();
    for spec in OPTIONAL_DOMAINS {
        if enabled.contains(&spec.key) {
            let domain_registry = match spec.key {
                "knowledge" => naviwealth_knowledge::tables::sync_registry(),
                "execution" => naviwealth_execution::tables::sync_registry(),
                "health" => naviwealth_health::tables::sync_registry(),
                _ => continue,
            };
            for adapter in domain_registry.adapters() {
                registry.add(adapter.clone());
            }
        }
    }
    registry
}

/// Every registered row family regardless of switches (backup and restore
/// must round-trip all data even while a domain is disabled).
pub fn full_sync_registry() -> SyncRegistry {
    let mut registry = naviwealth_finance::tables::sync_registry();
    for registry_of in [
        naviwealth_knowledge::tables::sync_registry(),
        naviwealth_execution::tables::sync_registry(),
        naviwealth_health::tables::sync_registry(),
    ] {
        for adapter in registry_of.adapters() {
            registry.add(adapter.clone());
        }
    }
    registry
}

/// The domain migrations in shared-counter order (1 core, 2 finance,
/// 3 knowledge, 4 execution, 5 health, 6 finance assets).
pub fn domain_migrations() -> lifeos::db::Migrations {
    lifeos::db::migrations::core_migrations()
        .push(naviwealth_finance::tables::migration())
        .push(naviwealth_knowledge::tables::migration())
        .push(naviwealth_execution::tables::migration())
        .push(naviwealth_health::tables::migration())
        .push(naviwealth_finance::tables::assets_migration())
}

/// Persist a switch and mirror it on `Services` so sync/AI follow at once.
pub async fn set_enabled(services: &Arc<Services>, spec: &DomainSpec, on: bool) {
    services.set_domain_enabled(spec.key, on);
    services
        .settings_set(spec.enabled_key, if on { "1" } else { "0" })
        .await;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn registry_merges_only_enabled_domains() {
        // Finance alone carries its six row families.
        let finance_only = sync_registry_for(&[]);
        assert_eq!(finance_only.adapters().len(), 6);
        assert!(finance_only.adapter("fin:assets").is_some());
        assert!(finance_only.adapter("know:notes").is_none());

        let all = sync_registry_for(&["knowledge", "execution", "health"]);
        assert_eq!(all.adapters().len(), 6 + 2 + 2 + 1);
        assert!(all.adapter("know:decisions").is_some());
        assert!(all.adapter("exec:actions").is_some());
        assert!(all.adapter("health:metrics").is_some());

        // A partial switch set adds exactly those families.
        let partial = sync_registry_for(&["execution"]);
        assert!(partial.adapter("exec:plans").is_some());
        assert!(partial.adapter("know:notes").is_none());
        assert!(partial.adapter("health:metrics").is_none());
    }

    #[test]
    fn full_registry_and_migrations_cover_every_family() {
        let all = full_sync_registry();
        for table in [
            "fin:accounts",
            "fin:assets",
            "fin:prices",
            "know:notes",
            "know:decisions",
            "exec:plans",
            "exec:actions",
            "health:metrics",
        ] {
            assert!(all.adapter(table).is_some(), "missing {table}");
        }

        // The shared migration counter: every step claims a unique version
        // 1..=6 (1 core, 2 finance, 3 knowledge, 4 execution, 5 health,
        // 6 finance assets).
        let steps = domain_migrations();
        let mut versions: Vec<i64> = steps.steps().iter().map(|s| s.version).collect();
        versions.sort();
        let unique_len = {
            let mut deduped = versions.clone();
            deduped.dedup();
            deduped.len()
        };
        assert_eq!(unique_len, steps.steps().len(), "versions must be unique");
        assert_eq!(versions, vec![1, 2, 3, 4, 5, 6]);
    }
}
