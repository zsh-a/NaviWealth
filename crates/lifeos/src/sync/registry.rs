//! Registry of the active domain tables.

use std::collections::HashMap;
use std::sync::Arc;

use crate::error::Domain;

use super::adapter::TableAdapter;

#[derive(Clone, Default)]
pub struct SyncRegistry {
    adapters: Vec<Arc<dyn TableAdapter>>,
    by_table: HashMap<String, usize>,
}

impl SyncRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn add(&mut self, adapter: Arc<dyn TableAdapter>) {
        let table = adapter.table().to_owned();
        self.by_table.insert(table, self.adapters.len());
        self.adapters.push(adapter);
    }

    pub fn adapter(&self, table: &str) -> Option<&Arc<dyn TableAdapter>> {
        self.by_table.get(table).map(|&i| &self.adapters[i])
    }

    pub fn adapters(&self) -> &[Arc<dyn TableAdapter>] {
        &self.adapters
    }

    pub fn adapters_for_domain(
        &self,
        domain: Domain,
    ) -> impl Iterator<Item = &Arc<dyn TableAdapter>> {
        self.adapters.iter().filter(move |a| a.domain() == domain)
    }
}
