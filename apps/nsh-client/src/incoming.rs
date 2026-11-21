//! The TSX entry's bridge for content shared from other apps
//! ([`crate::data::incoming`]): the Android host copies a share into
//! app-private storage and the entry hands the copies over once.

use nsh_core::prelude::*;
use serde_json::Value;

/// Content shared to NaviWealth from other apps.
#[module]
pub struct Incoming;

#[module]
impl Incoming {
    /// Opens what the Android host copied from one share: images and text as
    /// an unsent capture draft, a statement file in the statement review.
    pub fn receive(shared: Value, _cx: &mut ModuleCx) -> Result<(), String> {
        let shared = serde_json::from_value(shared).map_err(|_| "invalid_share".to_owned())?;
        crate::data::incoming::receive(shared);
        Ok(())
    }
}
