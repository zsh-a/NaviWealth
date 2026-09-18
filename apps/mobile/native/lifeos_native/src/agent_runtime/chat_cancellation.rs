//! Bridge-owned cancellation; dropping the aborted future also drops the HTTP stream.
use futures::future::{AbortHandle, AbortRegistration};
use std::collections::HashMap;
use std::sync::{LazyLock, Mutex};

type Entry = (AbortHandle, Option<AbortRegistration>);
static RUNS: LazyLock<Mutex<HashMap<String, Entry>>> = LazyLock::new(Default::default);

pub(super) fn prepare() -> String {
    let id = uuid::Uuid::new_v4().to_string();
    let (handle, registration) = AbortHandle::new_pair();
    RUNS.lock()
        .unwrap()
        .insert(id.clone(), (handle, Some(registration)));
    id
}

pub(super) fn cancel(id: &str) {
    if let Some((handle, _)) = RUNS.lock().unwrap().remove(id) {
        handle.abort();
    }
}

pub(super) fn claim(id: &str) -> Option<(AbortRegistration, Guard)> {
    let registration = RUNS.lock().unwrap().get_mut(id)?.1.take()?;
    Some((registration, Guard(id.to_owned())))
}

pub(super) struct Guard(String);
impl Drop for Guard {
    fn drop(&mut self) {
        RUNS.lock().unwrap().remove(&self.0);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use futures::future::{Abortable, pending};

    #[tokio::test]
    async fn cancellation_drops_pending_work_and_cleans_registry() {
        let id = prepare();
        let (registration, guard) = claim(&id).unwrap();
        cancel(&id);
        assert!(Abortable::new(pending::<()>(), registration).await.is_err());
        drop(guard);
        assert!(claim(&id).is_none());
    }

    #[test]
    fn cancellation_before_start_is_safe_and_scoped() {
        let first = prepare();
        let second = prepare();
        cancel(&first);
        assert!(claim(&first).is_none());
        let (_, guard) = claim(&second).unwrap();
        drop(guard);
        assert!(claim(&second).is_none());
    }
}
