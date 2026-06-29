use agent_core::RunId;
use camino::{Utf8Path, Utf8PathBuf};
use miette::{IntoDiagnostic, Result, miette};
use serde::Serialize;
use serde_json::Value;

pub(crate) async fn write_store_trace(
    store: &Utf8Path,
    trace: &agent_core::AgentTrace,
) -> Result<()> {
    write_json(store_trace_path(store, &trace.run_id), trace).await
}

pub(crate) async fn read_store_trace(store: &Utf8Path, run_id: &RunId) -> Result<Option<Value>> {
    let path = store_trace_path(store, run_id);
    if !path.exists() {
        return Ok(None);
    }
    read_json(path).await.map(Some)
}

fn store_trace_path(store: &Utf8Path, run_id: &RunId) -> Utf8PathBuf {
    store
        .join("traces")
        .join(format!("{}.trace.json", run_id.0))
}

pub(crate) async fn read_json(path: Utf8PathBuf) -> Result<Value> {
    let bytes = fs_err::tokio::read(&path)
        .await
        .map_err(|e| miette!("failed to read JSON at {path}: {e}"))?;
    serde_json::from_slice(&bytes).map_err(|e| miette!("failed to parse JSON at {path}: {e}"))
}

pub(crate) async fn read_trace(path: Utf8PathBuf) -> Result<agent_core::AgentTrace> {
    let value = read_json(path.clone()).await?;
    serde_json::from_value(value).map_err(|e| miette!("failed to parse trace at {path}: {e}"))
}

pub(crate) async fn write_json(path: Utf8PathBuf, value: &impl Serialize) -> Result<()> {
    if let Some(parent) = path.parent() {
        fs_err::tokio::create_dir_all(parent)
            .await
            .into_diagnostic()?;
    }
    let bytes = serde_json::to_vec_pretty(value).into_diagnostic()?;
    fs_err::tokio::write(path, bytes).await.into_diagnostic()
}

pub(crate) async fn write_text(path: Utf8PathBuf, text: &str) -> Result<()> {
    if let Some(parent) = path.parent() {
        fs_err::tokio::create_dir_all(parent)
            .await
            .into_diagnostic()?;
    }
    fs_err::tokio::write(path, text).await.into_diagnostic()
}
