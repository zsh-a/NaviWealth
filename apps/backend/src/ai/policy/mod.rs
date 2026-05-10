//! Code-level policy for AI tool dispatch.
//!
//! Two layers:
//!  * [`tool_policy`] — typed [`ToolDescriptor`] for every callable
//!    tool. Single source of truth for access class, risk level,
//!    confirmation requirement, and minimum context tier.
//!  * [`risk_policy`] — pure decision function consumed by the
//!    dispatcher. Phase 2-C is *advisory* (decisions are logged, not
//!    enforced) so we can validate the metadata against real traffic
//!    before flipping to enforcement in Phase 3.

pub mod risk_policy;
pub mod tool_policy;

pub use risk_policy::*;
pub use tool_policy::*;
