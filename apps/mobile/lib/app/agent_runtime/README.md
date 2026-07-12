# App Agent Runtime Adapters

This directory is the Flutter app composition layer for the native/upstream
agent runtime. Keep it as adapters only:

- Build the active `DomainPack` catalog for the runtime.
- Bridge FRB JSON calls and streams into Dart/Riverpod APIs.
- Dispatch device tools back into Flutter-owned repositories.
- Record traces and proposal application results through app providers.

Directory map:

- `bindings/`: profile turn bindings between app seams and runtime calls.
- `bridges/`: raw FRB API adapters and app-level native/profile bridges.
- `catalog/`: runtime catalog assembly from active domain packs.
- `chat/`: FRB chat stream types, runner, and trace mapping.
- `overrides/`: production provider overrides installed by bootstrap.
- `proposals/`: proposal application bridge back into app routes.
- `persistence/`: checkpoint contract/in-memory store plus the Drift adapter.
- `runner/`: snapshot execution and profile-turn orchestration.
- `tools/`: tool host, dispatcher, effect-plan binding, and headless process host.
- `trace/`: local trace capture for runtime-backed execution.

Do not put protocol-only DTOs here. Those live in
`core/ai/runtime/agent_runtime/`.

Do not put Rust implementation details here. Those live in
`apps/mobile/native/lifeos_native/src/agent_runtime/`.

Do not fork upstream runtime behavior here. That belongs in the
`third_party/agent-runtime` submodule and is consumed through
`lifeos_native`.

## Storage Policy

Production FRB execution is app-owned for persistence. Rust emits
runtime-shaped JSON events, steps, proposals, and LLM responses; the Flutter
adapter records user-visible state through the existing Drift-backed stores:

- `AiTraceStore` / `ai_traces` for transparency and debugging.
- `AgentRunStore` / `agent_runs` for lifecycle and schedule gates.
- `AgentArtifactStore` / `agent_artifacts` for briefing, review, and alert
  surfaces.
- Domain repositories, proposal appliers, undo, and touched-entity stores for
  product side effects.

Do not make Flutter UI or repositories read or write the upstream runtime's
`runtime.sqlite` tables. That schema is runtime-owned and not a NaviWealth
product contract. If runtime-owned SQLite is needed later, add explicit debug
or replay bridge APIs that return stable JSON and keep the product persistence
path in Drift.
