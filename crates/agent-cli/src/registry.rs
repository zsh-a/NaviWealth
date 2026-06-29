use std::sync::Arc;

use agent_core::{Agent, AgentContext, AgentError, AgentRunResult, AgentSpec, TraceEvent};
use agent_runtime::InMemoryAgentRegistry;
use async_trait::async_trait;
use camino::Utf8PathBuf;
use miette::{Result, miette};
use serde::Deserialize;

use crate::catalog::call_traced_tool;

#[derive(Debug, Deserialize)]
struct RegistryFile {
    agents: Vec<AgentManifest>,
}

#[derive(Debug, Deserialize)]
struct AgentManifest {
    #[serde(flatten)]
    spec: AgentSpec,
    #[serde(default = "default_runner")]
    runner: String,
}

pub(crate) struct CliRegistry {
    agents: Vec<Arc<dyn Agent>>,
}

impl CliRegistry {
    pub(crate) fn list_specs(&self) -> Vec<AgentSpec> {
        self.agents.iter().map(|agent| agent.spec()).collect()
    }

    pub(crate) fn into_agent_registry(self) -> Arc<InMemoryAgentRegistry> {
        InMemoryAgentRegistry::shared(self.agents)
    }
}

pub(crate) async fn load_registry(path: Utf8PathBuf) -> Result<CliRegistry> {
    let bytes = fs_err::tokio::read(&path)
        .await
        .map_err(|e| miette!("failed to read registry at {path}: {e}"))?;
    let file: RegistryFile = serde_yaml::from_slice(&bytes)
        .map_err(|e| miette!("failed to parse registry at {path}: {e}"))?;
    let agents = file
        .agents
        .into_iter()
        .map(|manifest| match manifest.runner.as_str() {
            "echo" => Ok(Arc::new(EchoAgent {
                spec: manifest.spec,
            }) as Arc<dyn Agent>),
            other => Err(miette!("unsupported agent runner '{other}'")),
        })
        .collect::<Result<Vec<_>>>()?;
    Ok(CliRegistry { agents })
}

struct EchoAgent {
    spec: AgentSpec,
}

#[async_trait]
impl Agent for EchoAgent {
    fn spec(&self) -> AgentSpec {
        self.spec.clone()
    }

    async fn run(&self, ctx: AgentContext) -> std::result::Result<AgentRunResult, AgentError> {
        ctx.trace
            .emit(TraceEvent::new(
                "echo_agent.input_received",
                ctx.input.clone(),
            ))
            .await?;
        let output = if let Some(tool_input) = ctx.input.get("tool_input") {
            call_traced_tool(&ctx, "echo", tool_input.clone()).await?
        } else {
            ctx.input.clone()
        };
        Ok(AgentRunResult::completed(
            ctx.run_id,
            self.spec.id.clone(),
            ctx.now,
            output,
            Some("echoed input".to_owned()),
        ))
    }
}

fn default_runner() -> String {
    "echo".to_owned()
}
