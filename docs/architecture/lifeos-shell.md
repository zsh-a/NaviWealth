# LifeOS Shell SSOT

This document describes the current cross-domain shell. It is written for implementation agents: where to plug in, which files own each seam, and which boundaries must not move.

## Document Contract

Owns `DomainPack` composition, opt-in behavior, shell routing, and the
cross-domain integration seams. It does not own domain business rules or exact
AI/Sync wire contracts. `domain_pack.dart`, `domain_packs.dart`, and their
composition tests are authoritative for the current inventory.

## Scope

The shell owns cross-domain infrastructure:

- Multi-domain IA and routing.
- Domain opt-in.
- AI tool, prompt, proposal, and agent composition.
- Memory Runtime and indexer bootstrap.
- Sync v3 row-family namespace and per-domain reset generations.
- Shared persistence adapter.
- Encrypted local backup and restore.
- Trigger coordination, global attention policy, background-safe evaluation,
  and notifications.

Domain business behavior belongs in the domain SSOT:

- FinanceOS: `../domains/financeos-domain.md`.
- HealthOS: `../domains/healthos-domain.md`.
- KnowledgeOS: `../domains/knowledgeos-domain.md`.
- ExecutionOS: `../domains/executionos-domain.md`.

## Current Shape

```text
app/
  bootstrap.dart                 Provider overrides and shell composition
  domain_packs.dart              Production domain inventory
  routing/router_builder.dart    Outer dock shell plus domain routes
  shell/app_dock_shell.dart      Multi-domain chrome
  domain_bootstrap.dart          Domain indexer/background startup
  life_context_composition.dart  Personal profile + active Life context
  agents/                        App-owned cross-domain synthesis
  interaction/                   InteractionSession Coordinator and host adapters

core/
  lifeos/domain_pack.dart        Domain registration contract
  shell/domain_shell.dart        Domain shell spec and tab ownership
  auth/domain_scope.dart         Domain opt-in enum and wire values
  backup/backup_table_registry.dart  Encrypted backup table metadata
  sync/sync_table_registry.dart  Row-family prefixes and sync table metadata
  ai/composition/                Cross-domain AI seams
  ai/session/                    InteractionSession ids, events, reducer, and policies
  ai/agents/                     Agent framework
  ai/attention/                  Global silent/surface/interrupt policy
  ai/local/memory/               Memory Runtime
  speech/                        Domain-neutral SpeechInput/SpeechOutput capabilities
  developer/                     Local dogfood issue contract/store
  persistence/                   Drift adapter and shared tables

features/<domain>/
  composition/                   Domain shell, routes, command palette, overrides
  ai_tools/                      Domain-owned device tools
  agents/                        Domain-owned agents
  data/                          Repositories, platform adapters, indexers
  domain/                        Domain entities
  ui/                            Domain screens
```

## Domain Inventory

`apps/mobile/lib/app/domain_packs.dart` is the source of truth for domains in this build.

| Domain | Scope | Shell tabs | Tools | Agents |
|---|---|---|---|---|
| FinanceOS | `finance` | Today, Activity, Wealth, Plan | `kFinanceDeviceTools` | Weekly Wealth Review, Cashflow Anomaly Review, FIRE Plan Drift Monitor, Options Income Risk Review |
| HealthOS | `health` | Today, Trends | `kHealthDeviceTools` | Recovery Alert, Weekly Summary |
| KnowledgeOS | `knowledge` | Inbox, Library | `kKnowledgeDeviceTools` | — |
| ExecutionOS | `execution` | Today, Plans (+ hidden Review) | `kExecutionDeviceTools` | Review, Due Action |

Finance is always active. Health, Knowledge, and Execution are enabled through
`domainOptInsProvider`.

The registry and settings retain the stable `*OS` product-pack names. Primary
shell chrome uses the shorter localized labels Finance, Health, Knowledge, and
Execution so users navigate by task area rather than architecture terminology.

Hidden tabs are declared through `DomainShellSpec.hiddenTabs`: routable branches
that own a real shell index but are not rendered in the tab bar, switcher, or
sidebar. Review is reached from one domain header action, the Life review
entry, or a relevant signal/artifact; it is not duplicated in the command
palette.

## Adding Or Changing A Domain

Use this path for any domain-level change:

1. Add or update domain code under `features/<domain>/`.
2. Export tools through `features/<domain>/<domain>_ai_tools.dart`.
3. Add or update shell spec and route builder under `features/<domain>/composition/`.
4. Add agents under `features/<domain>/agents/` and expose a builder provider if needed.
5. Add command palette entries under `features/<domain>/composition/`.
6. Register the domain once in `app/domain_packs.dart`.
7. Add domain memory/background bootstraps through the owning `DomainPack` only when they have a real source stream or startup task.
8. Register any data-management, settings, notifications, share handlers, Life
   signals, or source-route resolution on the same pack rather than in shell
   conditionals.
9. Add tests for opt-in behavior, route ownership, tool registration, and domain-specific repositories.

Do not add custom opt-in checks to every consumer. Consumers should derive from `activeDomainPacksProvider` or from a domain-owned provider that already observes the opt-in.

## Multi-Domain IA

The router uses a two-layer shell:

- Outer shell: `AppDockShell`, global lifecycle, route context, system-back behavior, and adaptive workspace navigation.
- Inner shell: one `StatefulShellRoute` per active domain route builder.

Important files:

- `app/routing/router_builder.dart`
- `app/shell/app_dock_shell.dart`
- `core/shell/domain_shell.dart`
- `features/finance/composition/finance_routes.dart`
- `features/health/composition/health_routes.dart`
- `features/knowledge/composition/knowledge_routes.dart`

Rules:

- Settings, login, onboarding, the `/assistant` conversation workspace, and
  global configuration routes stay outside the domain dock shell.
- A domain owns its tab paths through `DomainPack.tabPaths`.
- A domain may declare a chrome identity hue through `DomainPack.accent`
  (a light/dark `DomainAccent` pair from `design_system/theme/domain_accent.dart`).
  It tints only shell chrome — the switcher chip/sheet, the dock/rail/sidebar
  selected-tab treatment, and the desktop workspace tile. Null falls back to
  the global primary; status and market colors always stay semantic.
- Additional route prefixes that belong to a domain but are not tabs use `DomainPack.additionalPathPrefixes`.
- Desktop uses one visual sidebar at the large window class (1200dp+). Its
  workspace row switches between Life and active domains; its destinations
  are the tabs of the current domain. Do not stack a domain dock beside a
  second tab sidebar.
- Compact and medium layouts keep domain-local bottom/rail navigation and use
  the header workspace switcher. Finance-only installations resolve `/life`
  to Finance Today; the Life workspace becomes useful only when at least one
  optional domain is active.
- The Life hub does not repeat domain destinations inside its content.

Settings uses the same progressive-disclosure rule. Data & storage contains
backup/export and destructive user-data actions. Cache counts, retention,
automatic cleanup, and database compaction live under Advanced → Storage
maintenance. Runtime diagnostics, app logs, performance evidence, and
developer-issue tooling are debug-build surfaces; normal release builds keep
only user-actionable AI model, Agent, transparency, and storage controls.

## Identity And Opt-In

Location:

- `core/auth/domain_scope.dart`
- `core/auth/providers.dart`
- `features/settings/ui/domains_settings_page.dart`

Rules:

- `DomainScope.finance` is always present.
- Optional domains default to off.
- Settings → Domains separates enablement from operational configuration.
  A domain contributes a detail route only when it owns meaningful integration
  controls; domains with no such controls expose only their opt-in switch.
- Tool lists, prompt blocks, shell specs, agents, and command entries are derived from active domain packs.
- Backend auth may use the domain claim to filter sync pulls; client code must still enforce local opt-in for UI and domain jobs.

## AI Composition

Core contracts:

- `core/ai/contracts/`
- `core/ai/runtime/`
- `core/ai/composition/`

Aggregation:

- Tools: `deviceToolsProvider`.
- Prompt blocks: `systemPromptBlocksProvider`.
- Agents: `agentRegistryProvider`.
- Domain inventory: `activeDomainPacksProvider`.

Domain exports:

- Finance: `features/finance/finance_ai_tools.dart`.
- Health: `features/health/health_ai_tools.dart`.
- Knowledge: `features/knowledge/knowledge_ai_tools.dart`.
- Execution: `features/execution/execution_ai_tools.dart`.

Rules:

- Domain tools live in `features/<domain>/ai_tools/`.
- Shell tools that are genuinely domain-neutral may remain in `core/ai/runtime/device/tools/`.
- Read tools can return direct data.
- Write tools either return `ProposalEnvelope` or require explicit confirmation. Narrow local writes must be documented in the domain SSOT.
- System prompts are active-domain scoped. The model must not receive instructions for inactive domain tools.

## Interaction Session Runtime

The shell's long-term interaction seam is one modality-agnostic
`InteractionSession`, not a separate Voice Agent Runtime. Its boundary is:

```text
Interaction owns timing and delivery
Agent Runtime owns semantics and execution
Domain owns truth and side effects
Capability owns modality
```

The initial implementation is deliberately split:

```text
core/ai/session/       ids, semantic events, pure reducer, policies
app/interaction/       thin side-effectful Coordinator and host adapters
core/speech/           SpeechInput and SpeechOutput capabilities
app/agent_runtime/     existing ChatTurn / tool / proposal / resume adapter
```

The standalone Rust Agent Runtime already exists in the
`third_party/agent-runtime` submodule. It remains the source of truth for
`agent-core`, `agent-chat`, `agent-llm`, runner, store, schema, and fixture
contracts. `apps/mobile/lib/app/agent_runtime/` is NaviWealth's Host/FRB
adapter. Full-duplex voice reuses those contracts and does not add a parallel
Agent loop or an `agent-interaction` crate at this stage.

The Coordinator must remain thin. Its state policy is a pure
`InteractionState reduce(InteractionState, InteractionEvent)` reducer; it
invokes ChatRepository, SpeechInput, SpeechOutput, and InteractionEnvelope
side effects outside the reducer. This keeps deterministic replay and a future
runtime migration possible without moving Flutter orchestration wholesale.

### Session lanes and identifiers

One `VoiceState` is insufficient because input, execution, and output overlap:

```text
InputLane       idle → listening → endpointing → committed
ExecutionLane   idle → running → tool_running → waiting_interaction → done
OutputLane      idle → synthesizing → playing → interrupted → idle
```

Every event entering the reducer receives one Coordinator-assigned sequence
number and carries:

```text
SessionId + TurnId + ResponseEpoch + sequence
```

Tool, Proposal, and external-side-effect events additionally carry an
`OperationId`. `OperationId` is not required on every session event. A stale
`ResponseEpoch` invalidates UI/audio output; it never rolls back a committed
business operation.

An `AiIntentInvocation` starts or scopes a session. Later turns carry their
own `inputOrigin` (`voice`, `touch`, `keyboard`, etc.) and reuse the same
session. `source` on `AiIntentInvocation` remains the entry location such as
`finance_home` or `command_palette`; it is not overloaded with the input
modality.

### Two-phase barge-in

VAD is allowed to react quickly without immediately invalidating the Agent
response:

```text
speech_started
  → BargeInCandidate
  → duck/pause playback immediately
  → sustained speech or valid ASR text
  → BargeInCommitted
  → increment epoch and cancel/discard stale output
```

Noise, coughs, and speaker residue can resolve as `false_interruption`, in
which case the same epoch/output may resume. A pending
`InteractionEnvelope` takes priority over a normal new turn. Voice input must
first be interpreted as an interaction response when its schema allows it; it
must not bypass approval or typed confirmation.

### Delivery and context projection

Generated assistant text, delivered output, and next-turn context are separate:

```text
GeneratedText       complete local trace/debug output
DeliveryLedger      completed output segments per channel
ContextProjection   delivered prefix + interruption marker
```

The first implementation records completed segment ids rather than a bare
cross-language string offset. A later implementation may add an explicitly
defined UTF-8 or grapheme offset. Complete generated text may remain in the
local trace, but undelivered text must not be silently fed into the next voice
context.

### Engine policy

Engine choice is capability- and policy-driven, not model-name-driven:

| Engine | Role | Default policy |
|---|---|---|
| `LocalCascadedEngine` | Native audio processing → local/system ASR → existing Agent Runtime → system TTS | Production default |
| `CloudRealtimeEngine` | Provider realtime audio session with host tool/interaction gateways | Explicit opt-in; never a silent fallback |
| `LocalOmniEngine` | High-resource local speech/vision experiment | Experimental and device-gated |

The engine descriptor must advertise the capabilities required by the Host:
streaming input/output, full-duplex, interruption, transcript, tool calls,
proposal handling, interaction resume, durable resume, and delivery tracking.
An engine without the required safety capability is restricted to lower-risk,
read-only conversation.

Privacy is expressed per signal rather than as one ambiguous local flag:

```text
audio_transport
transcript_transport
context_transport
```

Local ASR plus a cloud LLM is audio-local but not a fully local turn. Cloud
Realtime is available only when the user policy permits audio and context to
leave the device.

The production model policy follows capability slots rather than a single
"all-in-one voice model":

| Capability slot | Production default | Optional path | Boundary |
|---|---|---|---|
| AEC / NS / AGC | iOS / Android system audio processing | Native engine-specific processing | High-rate audio stays native |
| Streaming ASR | Android system on-device ASR; iOS/macOS local Zipformer through `SpeechRecognizer` | Android local Zipformer; future native system adapters on Apple platforms | Partial text is semantic input only |
| Offline refinement | None in the first path | SenseVoice or Whisper when a real second-pass caller exists | Never required by the live turn loop |
| Agent reasoning | Existing user-selected `LlmProfile` and Agent Runtime | Realtime provider's generation inside its Host adapter | Voice does not choose a separate reasoning profile |
| TTS | System TTS | Downloadable local TTS | System TTS is not bundled model data |
| Full-duplex engine | Local cascaded engine | Explicit cloud realtime or experimental local omni engine | Capability and privacy gates are mandatory |

The current installed Zipformer bundle is Mandarin-only; a zh-en streaming
bundle is a versioned model-manifest change with its own language declaration,
checksums, fixtures, and native smoke coverage. `sherpa_onnx` is the current
local speech backend, not a product-level architecture dependency: all future
ASR/TTS implementations remain behind the existing speech seam.

## Proposal Application

Proposal application is a cross-domain seam under `core/ai/composition/`.

Current composition:

- Each domain contributes proposal card metadata through `DomainPack.proposalKinds`.
- Each domain contributes proposal apply/undo routing through `DomainPack.proposalApplierRouteBuilder`.
- `proposalKindRegistryProvider` and `proposalApplierProvider` are derived from active domain packs by `app/domain_composition.dart`.
- Finance exposes `financeProposalApplierProvider`.
- `CompositeProposalApplier` routes by explicit domain-owned proposal kinds and applied table prefixes. Unknown kinds or tables fail fast.

Rule: proposal metadata and proposal applier routes belong in the owning domain's `DomainPack`, not in bootstrap-time manual unions or domain-specific composite overrides.

## Cross-Domain Review

ExecutionOS contributes its contextual review destination through
`DomainPack.reviewRoutePath`. The Life hub renders one review entry and offers
only active domains with a real destination. Review data and pages stay
domain-owned; generic Life signals are not presented as a review backlog.

## Agent Runtime

Core framework:

- `core/ai/agents/agent.dart`
- `core/ai/agents/agent_trigger.dart`
- `core/ai/agents/agent_registry.dart`
- `core/ai/agents/agent_runner.dart`
- `core/ai/attention/`

Current domain agents:

- Health: Recovery Alert, Weekly Summary.
- Execution: Review, Due Action.

Current app-owned Agent:

- Daily Navigator: correlates active-domain `LifeSignal`s after deterministic
  material-change, freshness, evidence, and attention gates. It owns no domain
  calculations and never writes business rows directly.

Rules:

- Agents are named use cases, not a general automation platform.
- Domain Agents act as sensors/analysts: they read repositories, tools, or
  Memory Runtime and emit stable findings and temporary `AgentArtifact`s.
- Agent Artifacts do not write durable Memory and domain Agents do not send
  notifications. Explicit proposal confirmation owns business writes; the
  global attention layer is the only proactive-notification policy owner.
- Cross-run diagnostics are stored as local-only stable findings. Agents
  reconcile open findings by stable identity; disappeared signals resolve, and
  ignored/snoozed findings reopen only when evidence changes or snooze expires.
- Agents must not call other agents.
- `AgentTriggerSpec` separates schedule, event, threshold, state-transition,
  freshness, and manual trigger policy from persisted run provenance.
- Background callbacks may read only a precomputed primitive Life snapshot,
  run deterministic attention logic, and persist a pending decision. LLM,
  Memory retrieval, tools, proposal application, and business writes stay in
  the foreground provider graph.

## Memory Runtime

Location:

- `core/ai/local/memory/`
- `core/ai/local/embedding/`
- `app/domain_bootstrap.dart`

Core types:

- `EventRecord`
- `MemoryRecord`
- `MemoryAccessPolicy`
- `LifeContextSnapshot`
- `MemoryRuntime`
- `MemoryStore`
- `EventStore`
- `ContextBuilder`
- `Embedder`
- `PersonalProfileFact`
- `PersonalProfileSnapshot`

Indexers:

- Options trade journal to trade events and episodic memories.
- Health metrics to health events and selected sleep episodic memories.
- Knowledge notes and decisions to `know:*` memories.
- Execution plans, actions, and progress to `execution:*`
  memories/events.

Rules:

- `core/ai/local/memory/` does not import domains.
- Every event has typed domain/source identity and conclusion-level evidence;
  consumers never partition domains by string prefix or exclusion.
- Every durable Memory row declares retrieval role, evidence authority,
  provenance, and optional supersede lineage. Stable goals, preferences,
  constraints, and rules live in Personal Profile and require explicit user
  confirmation.
- Domain indexers live in domain `data/`.
- Domain indexers are contributed through `DomainPack.memoryBootstrapBuilder`;
  the app bootstrap only loops active packs.
- Every domain also declares `DomainPack.memorySourcePrefixes`. App composition
  turns active packs into one `MemoryAccessPolicy`; automatic Chat assembly,
  `build_context`, `query_memory`, proposal target lookup, and proposal apply
  all reuse it. Rows from disabled domains remain local but cannot be recalled
  or mutated by AI through a different path.
- Memory embeddings are derived local data and can be rebuilt.
- `build_context` is the preferred LLM retrieval tool for contextual answers; `query_memory` remains a flat fallback.
- Memory records carry an explicit retrieval role (`decision`, `episode`,
  `pattern`, `guidance`, or `legacy`) plus authority, provenance, temporal
  validity, and supersede lineage. `ContextBuilder` keeps these roles in
  separate bounded slots instead of treating every episodic row as a Decision.
- Host-owned `personal_profile_facts` stores structured goals, preferences,
  constraints, and rules without embeddings. The Settings UI may manage all
  local facts; `PersonalProfileSnapshot` injects only temporally current global
  facts and facts scoped to active domains. Profile is encrypted-backup-only
  and does not enter Sync v3.
- App-level retrieval emits profile facts as untrusted
  `ContextBlock(kind=profile)` records and other recalled data as untrusted
  memory blocks. Rust validates evidence intervals, filters expired and
  superseded blocks, hashes, budgets, snapshots, and renders them. Even
  `user_confirmed` evidence never receives instruction authority.
- Long-chat transcript compaction is separate from Memory Runtime. The chat
  feature stores a source-fingerprinted structured checkpoint locally and
  emits it as untrusted `ContextBlock(kind=compaction_summary)`. It never
  syncs or becomes durable user memory; editing/deleting summarized source
  turns invalidates it.
- Models stage durable memory or Profile changes through `propose_memory`; they
  never write `memories` or `personal_profile_facts` directly. Local-only
  `memory_candidates` use a generic `memory | profile_fact` target and become
  formal records only after explicit user approval through the proposal seam.
- Candidate apply supports create, supersede, forget, reject, retry, and undo.
  Owner, active-domain access, target identity, and destination conflicts are
  revalidated at apply time. Confirmed AI records carry
  `authority=user_confirmed` and provenance `user_confirmed_ai`; terminal
  candidates are pruned per owner after 90 days.

## Human Interaction Contract

The shell uses the provider-neutral `InteractionEnvelope` /
`InteractionResponse` pair for `ask_user`, proposal approval, and typed
confirmation. Domain payloads remain opaque; the shell/runtime own interaction
identity, lifecycle, confirmation mode, expiry, subject, response schema, and
resume routing.

For ChatTurn, pending tools and a pending interaction are mutually exclusive.
`ask_user` is first dispatched as a device tool, then its standard interaction
is suspended into a local `requires_interaction` snapshot without another
model request. A user response resumes the original turn id and becomes an
`interaction_result` block. Missing or mismatched snapshots fail closed.
Proposal approval uses the same response contract but resumes through the
proposal-apply route. Legacy decision/apply fields remain during the
compatibility migration.

## Data Management

The Settings → Data & Storage surface is composed through the same domain
registry seam:

- Domain-neutral contracts and inspection/maintenance orchestration live in
  `core/data_management/`.
- Each domain owns a `features/<domain>/data_management/` spec and registers it
  through `DomainPack.dataManagementSpec`.
- The page reads the complete `domainPackRegistryProvider`, not only active
  packs. Data from a disabled optional domain must remain visible and
  maintainable.
- Synced source tables are derived from `sync_table_registry.dart`. Explicit
  reset actions can erase one OS on the current device or permanently across
  all devices through the Sync v3 generation protocol.
- Only tables explicitly registered as local, re-creatable caches may be
  hard-deleted. Cache cleanup never writes tombstones or the sync outbox.
- Per-user cache tables are filtered by `owner_user_id`; device-global derived
  caches may be cleared for the whole device.
- Per-OS encrypted archives filter the shared backup inventory by row-family
  prefix and can restore that OS without replacing unrelated domains.
- AI chat, audit traces, memories, event projections, and agent history are
  counted and cleaned as a separate cross-domain local resource. Source data,
  credentials, and preferences are not included in that action.
- Daily retention maintenance is opt-out, recorded in
  `data_maintenance_runs`, and can also be run manually. Database compaction is
  manual because SQLite `VACUUM` can be comparatively expensive.

Disabling a domain does not delete its data. Cache cleanup also does not imply
server erasure. Permanent erasure increments the domain generation before
physically deleting its server rows; stale offline writes are rejected and the
client hard-resets that domain when it observes a newer generation.

## Developer Issue Capture

Advanced Settings exposes a local dogfood report surface backed by the
local-only `developer_issues` table. The app shell retains the last domain route
while Settings is open; capture adds build identity, latest trace id, and at
most five structural tool error codes. It never includes raw tool payloads or
error messages. Export is explicit, omits owner identity and local screenshot
paths, and does not create a GitHub issue or invoke a coding Agent.

## Embedding Runtime

Current native runtime:

- Rust crate: `apps/mobile/native/lifeos_native/`.
- Dart adapter: `core/ai/local/embedding/rust_gemma_embedder.dart`.
- Generated bindings: `apps/mobile/lib/src/rust/`.
- Model installer: `core/ai/local/embedding/model_*`.
- Native build: the `rust_builder` Flutter plugin invokes cargokit from the
  normal `flutter run` and `flutter build` commands.

Behavior:

- Bootstrap attempts to load EmbeddingGemma when model, ORT, and library paths are available.
- Failures fall back to `StubEmbedder`.
- Fingerprint changes drop stale vectors and allow reindexing.
- Web does not load the native embedder.

## Speech Input Runtime

Speech recognition is a domain-neutral input capability, not an AI tool and
not a source of automatic writes.

Location:

- Contract and platform selection: `core/speech/`.
- Existing ASR seam: `SpeechRecognizer` → `SpeechRecognitionSession` →
  `SpeechRecognitionEvent`; do not add a second public `AsrProvider` contract
  around it.
- Native engine: the `sherpa_onnx` Dart FFI plugin backed by C++ and ONNX Runtime.
- Reusable draft control: `design_system/widgets/speech_input_button.dart`.
- Model bundle: the shared AI model installer under `core/ai/local/embedding/model_*`.

Behavior:

- Android defaults to the system on-device recognizer; local INT8 Mandarin
  Zipformer is an opt-in alternative. iOS and macOS currently default to local
  Zipformer because their native system-recognizer adapters are not implemented
  yet. Web remains unsupported.
- The selected recognizer status advertises capabilities explicitly. Android's
  system path is low-resource push-to-talk; Android local Zipformer advertises
  native audio, VAD, barge-in, and full-duplex support. Apple/Dart Zipformer
  and Web retain false for those native full-duplex flags.
- The intended provider shape is `SpeechInput` above the existing recognizer
  seam, with `SystemSpeechRecognizer` and `SherpaSpeechRecognizer` as concrete
  implementations. Provider choice is policy-driven and must never silently
  fall back to a network recognizer.
- Managed recognition owns one application-wide microphone session. Concurrent
  starts fail deterministically with `session_busy`, and every completion,
  cancellation, startup failure, or stream error releases the session lease.
- A recognition session is bounded to five minutes. Reaching the limit emits
  the final transcript available from the native engine and closes the session.
- Moving the app out of the foreground finalizes active dictation. Editing the
  draft while recognition is starting or active cancels dictation, so a late
  partial result cannot overwrite user-authored text.
- Microphone PCM is consumed in memory and is neither persisted nor synced.
- Partial/final transcripts only update an editable text controller. Sending,
  saving, tool invocation, and proposal application remain explicit user actions.
- The current Dart path (`record` PCM stream → Dart decode → Sherpa FFI) remains
  a push-to-talk/local-ASR path. Android local Zipformer is the native
  full-duplex path: capture, AEC/NS/AGC, VAD, and high-rate ASR stay native;
  Dart/FRB receives only semantic events. Model initialization is off the
  Android UI thread and the initialized model handle is reused between turns;
  `capture_started` reports readiness and transcript-free startup duration. A
  host stop sends a cancelled terminal event before releasing the native
  microphone lease.
- Full-duplex barge-in follows `BargeInCandidate → BargeInCommitted`. A VAD
  signal may duck or pause playback immediately, but only sustained speech or
  valid ASR text increments the response epoch and invalidates the old output.
- Speech diagnostics retain only counters, durations, and stable error enums.
  Microphone bytes and transcript text are never passed to diagnostics or logs.
- AI Chat and Knowledge Inbox are the first callers; domains do not own or
  import the recognizer implementation.
- Web uses the unsupported stub and keeps microphone access disabled.
- Speech output is a separate `SpeechOutput` capability. System TTS is the
  initial production default; downloadable local TTS is an optional engine
  capability and is not bundled with the app.
- Android packages the ONNX Runtime supplied by `sherpa_onnx`; the Rust
  embedder dynamically reuses that single process-wide library.
- Model installation prefers individually checksummed files and falls back to
  the checksummed official sherpa-onnx GitHub Release archive when the primary
  host is unreachable. Archive extraction runs off the UI isolate and retains
  only the four manifest-declared runtime files.
- `apps/mobile/tool/run-asr-native-smoke.sh` downloads checksummed, pinned model
  and WAV fixtures and invokes `asr_native_smoke.dart` against the production
  recognizer configuration. `.github/workflows/asr-native-smoke.yml` runs the
  exact-transcript native regression for relevant changes, weekly, and on
  manual dispatch.

## Sync V3

Location:

- Client: `core/sync/`.
- Backend: `apps/backend/src/sync/`.
- Prefix/table registry: `core/sync/sync_table_registry.dart`.

Row-family prefixes:

| Domain | Prefix |
|---|---|
| FinanceOS | `fin:` |
| HealthOS | `health:` |
| KnowledgeOS | `know:` |
| ExecutionOS | `exec:` |

Rules:

- Local table names are unprefixed.
- Prefixing and stripping happen at the sync boundary.
- Sync table primary keys, owner-scope flags, and backfill eligibility are
  registered in one place: `SyncTableRegistration`.
- Backend store is generic and does not inspect domain payloads.
- Local-only tables and derived data do not sync.

## Persistence

Location:

- `core/persistence/app_database.dart`
- `core/persistence/tables.dart`
- `core/persistence/health_tables.dart`
- `core/persistence/knowledge_tables.dart`
- `core/persistence/execution_tables.dart`
- `core/persistence/local_only_tables.dart`

Rules:

- Drift stays centralized because the app uses one database.
- Ownership remains per domain even when table declarations live in `core/persistence/`.
- Repositories are the domain boundary for business reads and writes.
- Generated Drift files are never edited by hand.

## Backup And Restore

Location:

- `core/backup/`
- `core/backup/backup_table_registry.dart`

Rules:

- Backup/restore uses `kBackupTables`, not `kSyncableTables`.
- Backup table primary keys and restore outbox enqueue behavior are explicit
  in `BackupTableRegistration`.
- Syncable tables are not automatically backup tables unless their table
  metadata opts into backup coverage.

## Background And Notifications

Location:

- `core/background/`
- `core/notifications/`
- `core/ai/attention/`
- `app/agents/providers.dart`

Rules:

- Source-import callbacks may set lightweight due flags for foreground import.
- Life attention callbacks read only a precomputed primitive snapshot, evaluate
  deterministic candidates against the global interrupt budget, persist the
  decision, and notify only for `interrupt`.
- Full Agent runs and explanations happen after app startup with a complete
  provider graph.
- Domain Agents never bypass `AttentionArbiter` with direct notifications.

## Rust Boundary

Allowed:

- Embedding runtime and tokenizer through `flutter_rust_bridge`.
- Future security-sensitive sync encryption only after a separate trigger.

Not allowed:

- Business logic.
- Money math.
- Market data fetchers.
- SQL/Drift logic.
- Local LLM inference.
- Wide protobuf/event-dispatch SDKs.

## CI Gates

Run these when touching architecture boundaries:

```bash
./tool/lint-no-feature-in-shared.sh
./tool/lint-cross-feature-imports.sh
./tool/lint-finance-domain-data-imports.sh
./tool/lint-domain-neutral-contracts.sh
./tool/lint-frb-llm-entrypoints.sh
./tool/check-ai-contract-wire-enums.sh
```

Expected guarantees:

- Shared layers do not import domain features.
- `features/ai_chat/` does not import sibling features directly.
- Finance domain code does not import data-layer repositories or Drift rows.
- Domain-neutral contracts do not mention domain business types.
- AI contract wire enums match the checked-in serializer fixture.

Tool descriptor registration and sync row-family behavior are covered by the
regular Flutter test suite rather than duplicated shell wrappers.

## Change Checklist

For shell changes, verify:

- Domain inventory still comes from `DomainPack`.
- Optional domains work when disabled.
- Tool catalog and prompt blocks include only active domains.
- Router deep links still resolve for each domain.
- Proposal applier has one composite owner.
- Memory indexers do not create domain imports from `core/`.
- Sync prefixes are correct for new tables.
- Tests cover both active and inactive domain states.
