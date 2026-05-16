//! Layer 4 record-entry — cloud Vision parse (§5.10.10 / S5b-vision).
//!
//! This is **not** the ContextPack analytical-upload ingest in
//! `routes::ai::ingest` (unrelated, same word). Here a receipt image
//! or statement PDF is turned into structured draft transactions by a
//! multimodal model, via a single forced `tool_use` call.
//!
//! Deliberately **outside** the chat `ToolRegistry`: these schemas are
//! used only by the `/ingest/parse` route's one-shot call, never
//! exposed to the chat tool-loop (§5.10.9). Nothing here persists —
//! the route is in-request and the image is discarded when it returns.

pub mod parse;

pub use parse::{
    build_messages, extract_drafts, parse_tool_schema, system_prompt, ParsedDraftWire, EMIT_TOOL,
    MAX_PARSED_DRAFTS,
};
