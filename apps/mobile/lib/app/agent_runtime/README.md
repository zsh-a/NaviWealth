# App Agent Runtime Adapters

This directory is the Flutter app composition layer for the native/upstream
agent runtime. Keep it as adapters only:

- Build the active `DomainPack` catalog for the runtime.
- Bridge FRB JSON calls and streams into Dart/Riverpod APIs.
- Dispatch device tools back into Flutter-owned repositories.
- Record traces and proposal application results through app providers.

Directory map:

- `bindings/`: profile turn bindings between app seams and runtime calls.
- `bridges/`: FRB/native/profile completion bridges.
- `catalog/`: runtime catalog assembly from active domain packs.
- `chat/`: FRB chat stream types, runner, and trace mapping.
- `overrides/`: production provider overrides installed by bootstrap.
- `proposals/`: proposal application bridge back into app routes.
- `runner/`: app-owned runtime and step runners.
- `tools/`: tool host, dispatcher, plan binding, and headless process host.
- `trace/`: local trace capture for runtime-backed execution.

Do not put protocol-only DTOs here. Those live in
`core/ai/runtime/agent_runtime/`.

Do not put Rust implementation details here. Those live in
`apps/mobile/native/lifeos_native/src/agent_runtime/`.

Do not fork upstream runtime behavior here. That belongs in the
`third_party/agent-runtime` submodule and is consumed through
`lifeos_native`.
