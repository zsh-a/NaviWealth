//! Work that must outlive the page that asked for it (a backup, a restore,
//! connecting Garmin): spawned under the app's root, so closing a page does
//! not cancel it half way. Such tasks end only with the app.

use std::{cell::Cell, future::Future};

use nsh_core::prelude::*;

thread_local! {
    static ROOT: Cell<Option<Owner>> = const { Cell::new(None) };
}

/// Marks the current owner as the app's root; the root calls it once.
pub fn mark_root() {
    ROOT.set(Some(Owner::current()));
}

/// Runs `future` under the app's root (the current owner before
/// [`mark_root`]).
pub fn spawn_app(future: impl Future<Output = ()> + 'static) {
    match ROOT.get().filter(Owner::is_live) {
        Some(root) => root.run(|| {
            spawn(future);
        }),
        None => {
            spawn(future);
        }
    }
}
