# Rust Agent Runtime Handoff

Date: 2026-06-28

This file records the current implementation state before switching development
to another machine.

## Repository State

Current branch:

```text
refactor_agent
```

Current worktree state before writing this handoff:

```text
clean
```

Latest relevant commits:

```text
5ac61f8f refactor(agent-cli): split config module
10522f47 feat(mobile): wire agent runtime bridge
73e0e44f feat(agent-runtime): add rust runtime workspace
373a8f1d docs: add agent runtime design references
f46d951d docs: add rust agent runtime design
```

After moving to another machine, fetch/pull these commits and run:

```bash
rtk cargo test --workspace
cd apps/mobile
rtk flutter analyze
```

Use the mobile checks selectively if the new machine does not yet have Flutter,
Xcode, or the native embedding toolchain configured.

## Implemented Runtime Scope

The independent Rust runtime workspace exists at the repository root:

```text
Cargo.toml
Cargo.lock
crates/
  agent-core/
  agent-runtime/
  agent-store/
  agent-llm/
  agent-cli/
schemas/agent-runtime/
fixtures/agent-runtime/
evals/agent-runtime/
examples/agent-runtime/
openapi/agent-runtime-api.yaml
```

Major implemented capabilities:

- Core contracts: `Agent`, `AgentSpec`, `RunRequest`, `AgentRunResult`,
  `AgentTrace`, tool specs, proposal envelopes, sessions, threads, steps,
  hook events, prompt manifests, and LLM request/response DTOs.
- Runner lifecycle: `run_once`, `tick`, run store writes, trace emission,
  execution timeout, concurrency limiting, lease-based duplicate prevention,
  stale run recovery, idempotency keys, retry/backoff for `retryable` errors.
- Stores: in-memory and file-backed run/proposal/session/state storage.
- CLI: `run`, `tick`, `replay`, `inspect`, `validate`, `catalog`, `tool`,
  `proposal`, `session`, `eval`, `cmd`, `debug-bundle`, `metrics`, `serve`,
  and basic `tui`.
- Tool sources: inline mock tools, process JSON-RPC host, MCP stdio,
  HTTP JSON manifest.
- LLM providers: OpenAI-compatible, Anthropic, Ollama, and mock.
- Proposal lifecycle: create/list/inspect/decide/apply/undo, persisted state,
  trace lifecycle events, HTTP endpoints.
- Debug bundle: redacted run record/request/result/trace, event JSONL,
  tool call JSONL, state snapshot, replay config, prompt manifest.
- Eval: expected status, agent id, output mode, trace events, tool call
  sequence, proposal expectations, prompt manifest expectations, golden trace,
  scoring hook, and `eval create --from-run`.
- Metrics summary: run status counts, run latency, tool counts/failures,
  proposal lifecycle counts, replay count, LLM token totals.
- HTTP and stdio JSONL runtime server surfaces.

The runtime is documented in:

```text
docs/architecture/rust-agent-runtime-design.md
docs/architecture/rust-agent-runtime-mvp.md
```

## Mobile Bridge State

The mobile bridge commit added Flutter/Dart and native Rust integration pieces:

```text
apps/mobile/lib/app/agent_runtime_catalog.dart
apps/mobile/lib/app/agent_runtime_tool_host.dart
apps/mobile/lib/app/agent_runtime_headless_tool_host.dart
apps/mobile/lib/app/agent_runtime_native_bridge.dart
apps/mobile/lib/src/rust/api/agent_runtime.dart
apps/mobile/native/lifeos_native/src/api/agent_runtime.rs
apps/mobile/bin/agent_runtime_tool_host.dart
apps/mobile/bin/agent_runtime_tool_host_headless.dart
```

Current bridge capabilities:

- Export active `DomainPack` composition as `agent_catalog.v1`.
- Export active agents, device tools, proposal kind inventory, prompt blocks,
  and metadata for prompt manifests.
- Provide a Dart JSONL tool-host adapter compatible with Rust CLI process
  tool calls.
- Provide a headless Dart tool host entrypoint for local development.
- Provide FRB/native validation, summary, and first-step run functions for
  agent runtime wire contracts.
- Provide FRB/native continuation for the first Dart-dispatched tool step via
  `agentRuntimeContinueRunStep`.
- Provide a Dart-side `AgentRuntimeNativeStepRunner` that executes a bounded
  embedded tool loop without a process host: native start step, Dart device
  tool dispatch, native continuation step, repeated until a terminal native
  step or the tool-call budget is exhausted.
- Provide a Dart-side `AgentRuntimeProposalBridge` that parses ready proposal
  envelopes from terminal FRB steps and dispatches confirmed proposals through
  the active cross-domain `ProposalApplier`.
- Provide a Dart-side `AgentRuntimeConfirmedProposalRunner` that composes the
  bounded FRB step runner with the proposal bridge for explicit
  confirmed-proposal execution.

Production Flutter integration is FRB-first: Flutter calls the native Rust
bridge and keeps Drift/Riverpod device tools on the Dart side. JSONL process
tool hosts remain for CLI smoke tests, external tool adapters, and debugging;
they are not the primary mobile runtime path.

Known limitation:

- Data-backed Flutter tools may still be blocked in standalone Dart VM
  contexts by sqlite3/Drift environment setup. Treat that as a dev/process-host
  limitation, not the production mobile path. The production path should
  advance through FRB embedded runtime steps and Dart-side device tool dispatch.
- The embedded FRB path currently covers deterministic native step contracts
  bounded Dart-side tool loops, and an explicit confirmed-proposal runner. The
  remaining production work is the full LLM-backed native runner and wiring this
  runner into a concrete agent/UI confirmation entrypoint.

## Current Refactor State

The original handoff noted that `agent-cli` was still mostly in one large file.
The first safe split had been committed:

```text
crates/agent-cli/src/main.rs   5898 lines
crates/agent-cli/src/config.rs  209 lines
```

Commit:

```text
5ac61f8f refactor(agent-cli): split config module
```

Moved into `config.rs`:

- `RuntimeProfile`
- `EffectiveAgentConfig`
- `load_agent_config`
- `configured_path`
- `configured_paths`
- `configured_string`
- `configured_u16`
- `configured_u32`
- `configured_u64`
- `execution_policy`

No behavior changes were intended in that refactor.

Continuation update on 2026-06-28:

```text
crates/agent-cli/src/main.rs          2857 lines
crates/agent-cli/src/catalog.rs        293 lines
crates/agent-cli/src/tools.rs          659 lines
crates/agent-cli/src/proposal.rs       260 lines
crates/agent-cli/src/eval.rs           853 lines
crates/agent-cli/src/debug_bundle.rs   567 lines
crates/agent-cli/src/server.rs         386 lines
crates/agent-cli/src/tui.rs            292 lines
```

Moved in this continuation:

- `catalog.rs`: catalog summary, catalog reading, prompt manifest helpers,
  catalog dry-run registry, and traced dry-run tool calls.
- `tools.rs`: `ToolOverrides`, CLI `AgentServices`, process JSONL tool host,
  MCP stdio tool source, HTTP JSON tool source, external tool manifests, mock
  tool parsing, and builtin tool specs.
- `proposal.rs`: proposal decision/action response types, approval parsing,
  apply/undo state transitions, proposal action tool routing, and proposal
  trace append helpers.
- `eval.rs`: eval case/report structs, eval run/create flow, golden trace
  normalization, prompt/proposal expectations, scoring hook execution, and the
  dev score hook.
- `debug_bundle.rs`: debug bundle export, manifest/replay config/state snapshot
  structs, redaction helpers, trace/tool-call asset extraction, and local bundle
  JSON helpers.
- `server.rs`: HTTP route handlers and runtime stdio JSONL server surface.
- `tui.rs`: ratatui state loading, render helpers, terminal event loop, and
  one-shot render support.
- `registry.rs`: YAML registry loading, registry-to-runner conversion, and the
  local echo agent runner.
- `session.rs`: CLI/HTTP session reports, session/thread creation, thread fork,
  run metadata, and session step recording.
- `metrics.rs`: runtime metrics summary aggregation and trace event extraction.
- `command_template.rs`: command markdown creation/parsing and command template
  execution.
- `replay.rs`: replay mode/report types plus deterministic and live trace
  replay execution.
- `trace_store.rs`: shared JSON/text file helpers and store trace read/write
  paths used by CLI runtime modules.
- `runtime_server.rs`: runtime server orchestration, HTTP/stdout-facing request
  params, run/tool/proposal/session methods, metrics, and replay entrypoints.
- `stdio_protocol.rs`: shared JSON-RPC-style stdio request/response helpers used
  by the runtime stdio server and dev helper servers.
- `dev_stdio.rs`: hidden development tool-host and MCP stdio helper servers.
- `llm.rs`: `llm complete` provider selection and request execution.
- `run_cli.rs`: `run` and `tick` command runner/store/service setup.
- `catalog_cli.rs`: catalog subcommand dispatch and catalog report printing.
- `tool_cli.rs`: tool list/call command dispatch and tool source validation.
- `cli_input.rs`: shared `--input`/`--input-json` JSON input helper.
- `session_cli.rs`: session create/list/show/fork command dispatch.
- `proposal_cli.rs`: proposal create/list/inspect/decide/apply/undo command
  dispatch.

The first split was committed as `dc428208`. The split is still intended to be
behavior-preserving; the current continuation adds the registry/session/metrics,
command-template, replay, trace-store, runtime-server, and stdio-protocol
modules plus dev-stdio, LLM, run/tick, catalog, tool, shared CLI input,
session, and proposal command dispatch in the worktree and has passed focused
CLI verification.

## Last Verified Commands

Before the config split commit, the runtime had passed:

```text
rtk cargo test --workspace
rtk git diff --check
```

After the config split, these were run and passed:

```text
rtk cargo test -p agent-cli --test contracts
rtk cargo test -p agent-cli config_profile_drives_run_defaults --test catalog_cli
rtk cargo test -p agent-cli config_profile_drives_http_serve_defaults --test catalog_cli
rtk cargo test -p agent-cli http_server_handles_catalog_summary_and_agent_run --test catalog_cli
rtk cargo test --workspace
rtk git diff --check
```

One full `catalog_cli` run briefly failed because
`http_server_handles_catalog_summary_and_agent_run` did not observe the server
start before its timeout. The same test passed immediately when rerun alone,
so treat that as an HTTP server startup timing flake unless it reproduces.

After the continuation module splits, these were run and passed:

```text
rtk cargo fmt --all -- --check
rtk cargo check -p agent-cli
rtk cargo test -p agent-cli
rtk git diff --check
```

`rtk cargo clippy -p agent-cli --all-targets -- -D warnings` was also run, but
is currently blocked by existing `clippy::result_large_err` findings in
`crates/agent-runtime/src/lib.rs`.

## Recommended Next Steps

The original suggested extraction order has now been implemented in the
continuation worktree:

1. `catalog.rs`
   - `CatalogSummary`
   - catalog load/read helpers
   - prompt block and prompt manifest helpers
   - catalog-backed dry-run registry helpers if the dependency direction stays
     simple
2. `tools.rs`
   - `ToolOverrides`
   - process tool host
   - MCP tool source
   - HTTP JSON tool source
   - inline mock tools
3. `proposal.rs`
   - proposal CLI/HTTP lifecycle helpers
   - apply/undo tool routing
   - proposal trace append helpers
4. `eval.rs`
   - eval case/report structs
   - eval run/create/scoring hook
   - golden trace helpers
5. `debug_bundle.rs`
   - bundle manifest/config/snapshot/redaction helpers
6. `server.rs`
   - HTTP routes
   - stdio JSONL server
7. `tui.rs`
   - ratatui state and rendering helpers
8. `registry.rs`
   - YAML registry loading
   - echo runner adapter
9. `session.rs`
   - session/thread reports and step recording
10. `metrics.rs`
   - metrics summary aggregation
11. `command_template.rs`
   - command markdown create/run flow
12. `replay.rs`
   - replay mode/report types
   - deterministic/live replay execution
13. `trace_store.rs`
   - shared JSON/text file helpers
   - store trace read/write paths
14. `runtime_server.rs`
   - runtime server orchestration
   - run/tool/proposal/session method surface
15. `stdio_protocol.rs`
   - shared stdio request/response helpers
16. `dev_stdio.rs`
   - hidden development tool-host and MCP stdio helpers
17. `llm.rs`
   - LLM provider command handling
18. `run_cli.rs`
   - run/tick command runner setup
19. `catalog_cli.rs`
   - catalog command dispatch
20. `tool_cli.rs`
   - tool list/call command dispatch
21. `cli_input.rs`
   - shared JSON input argument handling
22. `session_cli.rs`
   - session command dispatch
23. `proposal_cli.rs`
   - proposal command dispatch

Remaining useful cleanup:

- Review whether `main.rs` should also split recover/metrics/cmd/eval command
  dispatch groups.
- Commit the continuation split intentionally, excluding unrelated untracked
  files.

## Useful Commands

Runtime:

```bash
rtk cargo fmt --all
rtk cargo test --workspace
rtk cargo test -p agent-cli --test contracts
rtk cargo test -p agent-cli --test catalog_cli
rtk cargo run -p agent-cli -- catalog summary fixtures/agent-runtime/catalog.valid.json
rtk cargo run -p agent-cli -- eval evals/agent-runtime --store /private/tmp/agent-runtime-eval-store
```

Mobile targeted checks:

```bash
cd apps/mobile
rtk dart format .
rtk flutter analyze
rtk flutter test test/app/agent_runtime_catalog_test.dart
rtk flutter test test/app/agent_runtime_tool_host_test.dart
rtk flutter test test/app/agent_runtime_native_bridge_test.dart
rtk cargo test --manifest-path native/lifeos_native/Cargo.toml
```

Project lint gates worth running before a PR:

```bash
./tool/check-tool-descriptors.sh
./tool/check-enum-mirror.sh
rtk cargo test --workspace
```

## Dependency Policy

The runtime workspace targets Rust 1.96 and edition 2024. New Rust dependencies
should continue to use current stable mainstream crates first, then document
any ecosystem or platform constraint that prevents using the newest compatible
release.

Current notable crates:

- `tokio`
- `clap`
- `serde`, `serde_json`, `serde_yaml`
- `schemars`, `jsonschema`
- `miette`, `thiserror`
- `reqwest` with rustls
- `time`
- `uuid` v7
- `ratatui`, `crossterm`
- `futures`
- `blake3`
- `toml`
