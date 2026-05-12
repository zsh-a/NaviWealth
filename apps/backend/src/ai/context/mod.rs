//! Wire-crossing AI contracts between mobile and the planner.
//!
//! Mirrors `apps/mobile/lib/core/ai/contracts/`. Mobile serializes a
//! [ContextPack] on every router invocation that needs the cloud; the
//! planner deserializes it here. When the planner needs ledger detail
//! it cannot infer from aggregates, it emits a [DisclosureRequest] as
//! a tool call which the device answers with a [DisclosureResponse]
//! (after consent). These types are the *only* shape the planner ever
//! reads from the device — there is no implicit fallback to raw rows.

pub mod context_pack;
pub mod disclosure;
pub mod system_prompt_extension;

pub use context_pack::*;
pub use disclosure::*;
pub use system_prompt_extension::format_context_pack;
