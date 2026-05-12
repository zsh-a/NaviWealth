//! Agent event sinks.

use crate::ai::runtime::AgentEvent;
use crate::error::AppError;

pub trait EventSink {
    fn emit(&mut self, event: AgentEvent) -> Result<(), AppError>;
}

impl EventSink for Vec<AgentEvent> {
    fn emit(&mut self, event: AgentEvent) -> Result<(), AppError> {
        self.push(event);
        Ok(())
    }
}
