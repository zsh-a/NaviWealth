//! Provider-agnostic runtime contracts shared by AI adapters and loops.

pub mod adapter;
pub mod event;

pub use adapter::*;
pub use event::*;
