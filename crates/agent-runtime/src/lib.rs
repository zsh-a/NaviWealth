mod lock;
mod policy;
mod recovery;
mod registry;
mod runner;
mod scheduler;
mod services;
mod trace;

pub use lock::InMemoryLockStore;
pub use policy::ExecutionPolicy;
pub use recovery::{RecoveredRun, RecoveryReport, recover_stale_runs};
pub use registry::InMemoryAgentRegistry;
pub use runner::{AgentRunner, RunOutcome, run_idempotency_key};
pub use scheduler::AgentScheduler;
pub use services::BasicAgentServices;
pub use trace::MemoryTraceSink;

pub const RUNTIME_VERSION: &str = env!("CARGO_PKG_VERSION");

#[cfg(test)]
mod tests;
