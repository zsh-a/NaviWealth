use std::{collections::HashMap, sync::Arc};

use agent_core::{Agent, AgentError, AgentRegistry, AgentSpec};
use async_trait::async_trait;

pub struct InMemoryAgentRegistry {
    agents: HashMap<String, Arc<dyn Agent>>,
}

impl InMemoryAgentRegistry {
    pub fn new(agents: Vec<Arc<dyn Agent>>) -> Self {
        Self {
            agents: agents
                .into_iter()
                .map(|agent| (agent.spec().id, agent))
                .collect(),
        }
    }

    pub fn shared(agents: Vec<Arc<dyn Agent>>) -> Arc<Self> {
        Arc::new(Self::new(agents))
    }
}

#[async_trait]
impl AgentRegistry for InMemoryAgentRegistry {
    async fn list_agents(&self) -> Result<Vec<AgentSpec>, AgentError> {
        Ok(self.agents.values().map(|agent| agent.spec()).collect())
    }

    async fn get_agent(&self, id: &str) -> Result<Option<Arc<dyn Agent>>, AgentError> {
        Ok(self.agents.get(id).cloned())
    }
}
