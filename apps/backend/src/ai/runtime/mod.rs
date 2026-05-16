//! Provider-agnostic runtime contracts shared by AI adapters and loops.

pub mod adapter;
pub mod agent_loop;
pub mod event;
pub mod session;
pub mod sink;

pub use adapter::*;
pub use agent_loop::*;
pub use event::*;
pub use session::*;
pub use sink::*;
