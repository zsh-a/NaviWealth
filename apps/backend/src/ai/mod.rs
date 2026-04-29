//! AI assistant backend (FIR-59).
//!
//! Hosts the Anthropic Claude proxy and the function-calling tool surface
//! the model uses to read the user's financial data. Splitting this into
//! its own module keeps the LLM concerns — system prompt, tool schemas,
//! rate limiting, SSE relay — isolated from the sync/auth machinery.
//!
//! Wire shape:
//!
//! 1. Client POSTs `/ai/chat` with a chat history.
//! 2. The handler validates the JWT, applies the rate-limit guardrail and
//!    forwards the conversation to Anthropic with the tool schemas attached.
//! 3. Anthropic's SSE response is relayed verbatim to the client until the
//!    model emits `tool_use` and stops.
//! 4. The handler dispatches each tool call against D1, appends the model's
//!    `tool_use` block + the synthesized `tool_result` block to the
//!    conversation, and re-issues the request to Anthropic.
//! 5. Steps 3–4 loop until the model returns plain text, at which point the
//!    SSE stream ends with `event: done`.
//!
//! The model is **not allowed** to compute monetary values on its own — every
//! number the user reads in the assistant's reply must trace back to a
//! `tool_result` block. The system prompt enforces that contract; see
//! `guardrails::SYSTEM_PROMPT`.

pub mod anthropic;
pub mod guardrails;
pub mod sse;
pub mod tools;
