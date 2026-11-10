//! Bridge from app-level tokio tasks to the nsh engine thread. Signals
//! are engine-thread-only and tasks spawned during an event handler die
//! with that handler's owner, so the pipe is created in a component body
//! (the screen's owner) and background jobs report through it.

use std::sync::Arc;

use nsh_core::prelude::*;

use crate::state::Services;

/// An engine-thread pump for background events. Create it in a component
/// body; its drain task lives with that owner. `send_job` runs work on
/// the app-level tokio runtime and streams results back through the
/// registered callback.
pub struct EventPipe<E> {
    tx: tokio::sync::mpsc::UnboundedSender<E>,
}

impl<E: Send + 'static> Clone for EventPipe<E> {
    fn clone(&self) -> Self {
        Self {
            tx: self.tx.clone(),
        }
    }
}

impl<E: Send + 'static> EventPipe<E> {
    pub fn new(mut on_event: impl FnMut(E) + 'static) -> Self {
        let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<E>();
        spawn(async move {
            while let Some(event) = rx.recv().await {
                on_event(event);
            }
        });
        Self { tx }
    }

    pub fn sender(&self) -> tokio::sync::mpsc::UnboundedSender<E> {
        self.tx.clone()
    }
}

/// Run `job` on the app-level tokio runtime; it reports `E` events (and
/// finally drops the sender) through `tx`.
pub fn spawn_job<E, F, Fut>(
    services: &Arc<Services>,
    tx: tokio::sync::mpsc::UnboundedSender<E>,
    job: F,
) where
    E: Send + 'static,
    F: FnOnce(tokio::sync::mpsc::UnboundedSender<E>) -> Fut + Send + 'static,
    Fut: std::future::Future<Output = ()> + Send + 'static,
{
    services.runtime.spawn(async move {
        job(tx).await;
    });
}
