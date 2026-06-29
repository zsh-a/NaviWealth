use agent_core::{AgentError, TraceEvent, TraceSink};
use async_trait::async_trait;
use tokio::sync::Mutex;

#[derive(Default)]
pub struct MemoryTraceSink {
    events: Mutex<Vec<TraceEvent>>,
}

impl MemoryTraceSink {
    pub async fn events(&self) -> Vec<TraceEvent> {
        self.events.lock().await.clone()
    }
}

#[async_trait]
impl TraceSink for MemoryTraceSink {
    async fn emit(&self, event: TraceEvent) -> Result<(), AgentError> {
        self.events.lock().await.push(event);
        Ok(())
    }
}
