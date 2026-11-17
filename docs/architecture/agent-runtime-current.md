# Agent Runtime Current Architecture

Status: active native-runtime implementation reference.

## Document Contract

Owns the layout, layering and consumption rules of the
`third_party/agent-runtime` submodule. The submodule's own crates, schemas,
fixtures and contract tests are authoritative for exact APIs.

NaviWealth consumes the standalone runtime from
`https://github.com/zsh-a/agent-runtime.git` through the Git submodule at
`third_party/agent-runtime`. Paths below are relative to that submodule root
unless prefixed with the submodule directory.

## Scope

The runtime provides:

- reusable Rust contracts and runner crates;
- schema / fixture / OpenAPI wire contracts;
- local CLI, HTTP, stdio, eval, replay, debug bundle, and TUI surfaces;
- a dependency-light TypeScript client under `bindings/ts`.

The runtime must remain independent of NSH, nsh-base, and NaviWealth domain
models. Business policy, permissions, repositories, and business side effects
stay in the host application. Rust agents consume domain-neutral contracts and
request effects through host gateways; adding one does not transfer domain
ownership into the standalone runtime.

## Code Map

```text
crates/
  agent-core/       Stable DTOs, traits, IDs, errors, trace/session/proposal contracts
  agent-runtime/    AgentRunner, scheduler, retry/timeout, lease locking, trace capture
  agent-store/      In-memory and file-backed run/state/proposal/session stores
  llm-protocol/     Typed LLM content, provider codecs, SSE and schema validation (no I/O)
  llm-client/       Runtime-neutral transport, retry, deadline and capability policy
  llm-reqwest/      Reqwest transport and native/browser provider adapters
  agent-chat/       Shared ChatTurn request/event contract and provider/tool loop
  agent-tools/      Reusable tool registry, policy, and tool-host helpers
  agent-cli/        Local developer surfaces and host adapters

schemas/            JSON Schema contracts for runtime wire types
fixtures/contracts/ Valid and invalid schema fixtures used by contract tests
openapi/            agent-runtime-api.yaml — HTTP API contract for server-first clients
```

## Runtime Layers

1. `agent-core` defines protocol shapes and host-facing traits.
2. `llm-protocol` owns typed LLM contracts, codecs and SSE parsing. `llm-client`
   owns shared request policy over a Host Transport; `llm-reqwest` implements
   that transport for native and browser hosts.
3. `agent-chat` owns provider-neutral interactive ChatTurn request/event
   contracts and the LLM/tool continuation loop over `AgentServices`.
4. `agent-runtime` executes scheduled or explicit `Agent` instances through
   `AgentRunner`.
5. `agent-store` persists run/state/proposal/session records.
6. Host adapters implement `AgentServices` and tool/proposal/state behavior.
7. CLI/server/TUI are surfaces over these contracts.

## How NaviWealth Uses It

- `crates/navi-health` performs meal recognition through `llm-protocol` wire
  types and `llm-client` request policy; the NSH client supplies its platform
  fetch as the Host Transport. Recognition is a single-shot draft operation;
  there is no chat loop or proposal seam in the NSH client. Unified capture
  uses the same protocol/client directly for `ask_user` tool calls, persisting
  the suspended call and owner answers in its local draft. Continuation occurs
  only when the owner submits or retries; `agent-chat` is not adopted.
- Domain truth in `crates/navi-finance` and `crates/navi-health` never imports
  runtime crates; only recognition paths do.
- CI runs `cargo fmt --check` and `cargo test --workspace --locked` inside the
  submodule (`.github/workflows/crates.yml`).

## Invariants

- All top-level runtime wire messages carry `protocol_version: "agent.v1"`.
- Cross-language contracts are JSON-first. Keep envelopes stable and put
  business-specific data in `input`, `output`, `payload`, or `metadata`.
- Runtime crates must not import NSH, nsh-base, or NaviWealth domain code.
- Business side effects are never executed by the runtime; hosts own
  confirmation and writes.

## Interaction Entrypoints

Use these entrypoints when debugging:

```bash
cd third_party/agent-runtime
rtk cargo run -p agent-cli -- list
rtk cargo run -p agent-cli -- tui
rtk cargo run -p agent-cli -- validate schemas/run-request.schema.json fixtures/contracts/run-request.valid.json
```

## Change Routing

| Change | Start Here | Required Checks |
|---|---|---|
| Add or change a wire field | `schemas/`, submodule `third_party/agent-runtime/crates/agent-core/`, fixtures | schema validation tests |
| Change LLM provider behavior | submodule `third_party/agent-runtime/crates/llm-protocol/`, `third_party/agent-runtime/crates/llm-client/` | `rtk cargo test` in the submodule |
| Change recognition prompts or parsing | `crates/navi-health/` | health fixtures and adapter tests |

## Current Limitations

- There is no standalone `bindings/dart` package; the pinned runtime ships
  `bindings/ts` only.
- Trace is event-first (`events`) and does not expose a separate `spans` array.
- `ScheduleSpec` supports `manual` and `interval` only.

Use this document and current tests as authority.
