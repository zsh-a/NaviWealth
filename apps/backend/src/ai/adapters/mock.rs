//! Scripted adapter for runtime tests.

use std::cell::RefCell;
use std::rc::Rc;

use async_trait::async_trait;
use futures_util::future::pending;
use futures_util::stream::{self, BoxStream, StreamExt};

use crate::ai::runtime::{AgentEvent, AgentRequest, LlmAdapter};
use crate::error::AppError;

#[derive(Debug, Clone, Default)]
pub struct MockAdapter {
    rounds: Rc<RefCell<Vec<MockRound>>>,
}

impl MockAdapter {
    pub fn new(events: Vec<AgentEvent>) -> Self {
        Self::scripted(vec![MockRound::events(events)])
    }

    pub fn scripted(rounds: Vec<MockRound>) -> Self {
        Self {
            rounds: Rc::new(RefCell::new(rounds)),
        }
    }
}

#[async_trait(?Send)]
impl LlmAdapter for MockAdapter {
    async fn stream(&self, _req: AgentRequest<'_>) -> Result<BoxStream<'_, AgentEvent>, AppError> {
        let round = self.rounds.borrow_mut().remove(0);
        match round {
            MockRound::Events(events) => Ok(stream::iter(events).boxed()),
            MockRound::Error(message) => Err(AppError::Internal(message)),
            MockRound::Never => {
                pending::<()>().await;
                Ok(stream::empty().boxed())
            }
        }
    }
}

#[derive(Debug, Clone)]
pub enum MockRound {
    Events(Vec<AgentEvent>),
    Error(String),
    Never,
}

impl MockRound {
    pub fn events(events: Vec<AgentEvent>) -> Self {
        Self::Events(events)
    }

    pub fn error(message: impl Into<String>) -> Self {
        Self::Error(message.into())
    }

    pub fn never() -> Self {
        Self::Never
    }
}
