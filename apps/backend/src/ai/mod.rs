//! AI assistant backend (FIR-59).
//!
//! Hosts the Anthropic-compatible LLM proxy and the function-calling tool surface
//! the model uses to read the user's financial data. Splitting this into
//! its own module keeps the LLM concerns — system prompt, tool schemas,
//! rate limiting, SSE relay — isolated from the sync/auth machinery.
//!
//! Wire shape:
//!
//! 1. Client POSTs `/ai/chat` with a chat history.
//! 2. The handler validates the JWT, applies the rate-limit guardrail and
//!    forwards the conversation to the LLM with the tool schemas attached.
//! 3. The LLM response is relayed to the client until the
//!    model emits `tool_use` and stops.
//! 4. The handler dispatches each tool call against D1, appends the model's
//!    `tool_use` block + the synthesized `tool_result` block to the
//!    conversation, and re-issues the request to the LLM.
//! 5. Steps 3–4 loop until the model returns plain text, at which point the
//!    SSE stream ends with `event: done`.
//!
//! The model is **not allowed** to compute monetary values on its own — every
//! number the user reads in the assistant's reply must trace back to a
//! `tool_result` block. The system prompt enforces that contract; see
//! `guardrails::SYSTEM_PROMPT`.

pub mod anthropic;
// Phase B adapter surface: defined ahead of route migration in Phase C.
#[allow(dead_code, unused_imports)]
pub mod adapters;
// Phase 1 contracts: types are defined ahead of consumers. The
// allow lifts when the routes/policy/tools modules start using them.
#[allow(dead_code, unused_imports)]
pub mod context;
pub mod guardrails;
// Phase 2-C: descriptor metadata is consulted by the dispatcher but
// fields like `risk` / `requires_confirmation` and the `Typed` /
// `ExternalWrite` variants exist for forward compatibility — they're
// referenced from review-only sites today. The allow lifts in Phase 3
// when the policy flips from advisory to enforced.
#[allow(dead_code)]
pub mod policy;
pub mod proposals;
// AI Read Models — 主通道（docs/ai-architecture.md §4.3）
pub mod read_models;
// Phase A runtime protocol: defined ahead of adapters / agent loop / SSE v2.
#[allow(dead_code, unused_imports)]
pub mod runtime;
pub mod sse;
pub mod tools;
