use std::{collections::BTreeMap, time::Duration};

use agent_runtime::ExecutionPolicy;
use camino::Utf8PathBuf;
use miette::{Result, miette};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
struct AgentConfigFile {
    #[serde(default)]
    runtime: RuntimeProfile,
    #[serde(default)]
    profiles: BTreeMap<String, RuntimeProfile>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct RuntimeProfile {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) profile: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) store: Option<Utf8PathBuf>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) eval_store: Option<Utf8PathBuf>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) registry: Option<Utf8PathBuf>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) catalog: Option<Utf8PathBuf>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) tool_sources: Option<Vec<Utf8PathBuf>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) host: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) port: Option<u16>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) stdio: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) timeout_seconds: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) max_retries: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) retry_backoff_ms: Option<u64>,
}

#[derive(Debug, Clone, Serialize)]
pub(crate) struct EffectiveAgentConfig {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(crate) source: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(crate) profile: Option<String>,
    pub(crate) runtime: RuntimeProfile,
}

impl RuntimeProfile {
    fn merge(&mut self, overlay: RuntimeProfile) {
        if overlay.profile.is_some() {
            self.profile = overlay.profile;
        }
        if overlay.store.is_some() {
            self.store = overlay.store;
        }
        if overlay.eval_store.is_some() {
            self.eval_store = overlay.eval_store;
        }
        if overlay.registry.is_some() {
            self.registry = overlay.registry;
        }
        if overlay.catalog.is_some() {
            self.catalog = overlay.catalog;
        }
        if overlay.tool_sources.is_some() {
            self.tool_sources = overlay.tool_sources;
        }
        if overlay.host.is_some() {
            self.host = overlay.host;
        }
        if overlay.port.is_some() {
            self.port = overlay.port;
        }
        if overlay.stdio.is_some() {
            self.stdio = overlay.stdio;
        }
        if overlay.timeout_seconds.is_some() {
            self.timeout_seconds = overlay.timeout_seconds;
        }
        if overlay.max_retries.is_some() {
            self.max_retries = overlay.max_retries;
        }
        if overlay.retry_backoff_ms.is_some() {
            self.retry_backoff_ms = overlay.retry_backoff_ms;
        }
    }
}

pub(crate) async fn load_agent_config(
    config_path: Option<Utf8PathBuf>,
    requested_profile: Option<&str>,
) -> Result<EffectiveAgentConfig> {
    let config_path = match config_path {
        Some(path) => Some(path),
        None => std::env::var("AGENT_RUNTIME_CONFIG")
            .ok()
            .map(Utf8PathBuf::from)
            .or_else(|| {
                let default = Utf8PathBuf::from("agent-runtime.toml");
                default.exists().then_some(default)
            }),
    };
    let Some(path) = config_path else {
        return Ok(EffectiveAgentConfig {
            source: None,
            profile: requested_profile.map(str::to_owned),
            runtime: RuntimeProfile::default(),
        });
    };

    let text = fs_err::tokio::read_to_string(&path)
        .await
        .map_err(|e| miette!("failed to read config at {path}: {e}"))?;
    let file: AgentConfigFile =
        toml::from_str(&text).map_err(|e| miette!("failed to parse TOML config at {path}: {e}"))?;
    let profile_name = requested_profile
        .map(str::to_owned)
        .or_else(|| file.runtime.profile.clone());
    let mut runtime = file.runtime;
    if let Some(profile_name) = &profile_name {
        let overlay =
            file.profiles.get(profile_name).cloned().ok_or_else(|| {
                miette!("profile '{profile_name}' was not found in config at {path}")
            })?;
        runtime.merge(overlay);
    }
    Ok(EffectiveAgentConfig {
        source: Some(path.to_string()),
        profile: profile_name,
        runtime,
    })
}

pub(crate) fn configured_path(
    value: Utf8PathBuf,
    default: &str,
    configured: Option<&Utf8PathBuf>,
) -> Utf8PathBuf {
    if value == Utf8PathBuf::from(default) {
        configured.cloned().unwrap_or(value)
    } else {
        value
    }
}

pub(crate) fn configured_u64(value: u64, default: u64, configured: Option<u64>) -> u64 {
    if value == default {
        configured.unwrap_or(value)
    } else {
        value
    }
}

pub(crate) fn configured_u32(value: u32, default: u32, configured: Option<u32>) -> u32 {
    if value == default {
        configured.unwrap_or(value)
    } else {
        value
    }
}

pub(crate) fn configured_u16(value: u16, default: u16, configured: Option<u16>) -> u16 {
    if value == default {
        configured.unwrap_or(value)
    } else {
        value
    }
}

pub(crate) fn configured_string(
    value: String,
    default: &str,
    configured: Option<&String>,
) -> String {
    if value == default {
        configured.cloned().unwrap_or(value)
    } else {
        value
    }
}

pub(crate) fn configured_paths(
    values: Vec<Utf8PathBuf>,
    configured: Option<&Vec<Utf8PathBuf>>,
) -> Vec<Utf8PathBuf> {
    if values.is_empty() {
        configured.cloned().unwrap_or_default()
    } else {
        values
    }
}

pub(crate) fn execution_policy(
    timeout_seconds: u64,
    max_retries: u32,
    retry_backoff_ms: u64,
) -> ExecutionPolicy {
    ExecutionPolicy {
        timeout: Duration::from_secs(timeout_seconds),
        max_retries,
        retry_backoff: Duration::from_millis(retry_backoff_ms),
        max_concurrent_runs: 1,
    }
}
