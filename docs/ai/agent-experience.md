# Agent Experience SSOT

Status: current implementation and extension contract.

Last reviewed: 2026-08-23.

## Document Contract

Owns Agent lifecycle, artifact presentation, scheduling, evidence, and outcome
evaluation rules. It does not own the native chat runtime or domain-specific
finding logic. `DomainPack` registrations and the executable Agent outcome
corpus are authoritative for the production inventory.

This document describes the production agent experience. Cross-domain outcome
and evaluation sequencing belongs in `../roadmap/roadmap-lifeos.md`; this file
does not maintain a second roadmap.

## Product Model

Agents are a proactive insight layer inside existing domain pages, not a new AI
destination. Users should be able to understand what happened, inspect local
evidence, act through an existing confirmed proposal path, ask a contextual
follow-up, or dismiss the result.

Rules:

- Domain Agent results appear in the owning domain surface. The app-owned Daily
  Navigator appears on the Life surface.
- Follow-up uses `askAi()` and a registered `AiIntentInvocation`; do not add an
  agent chat tab or private follow-up route.
- Writes and high-risk actions use `ProposalEnvelope`, interaction-mode policy,
  confirmation, durable undo where supported, and trace recording.
- Domain agents are registered through `DomainPack`. Inactive optional domains
  do not expose, schedule, or render their agents.
- Deterministic calculations remain in services/tools. The LLM may summarize
  or explain them but must not silently replace them.

## Current Composition

The production `DomainPack` registry is authoritative. At this review:

| Domain | Agents | Default placement |
|---|---|---|
| LifeOS app composition | Daily Navigator | Life home |
| FinanceOS | Weekly Wealth Review, Cashflow Anomaly Review, FIRE Plan Drift Monitor, Options Income Risk Review | Finance home |
| HealthOS | Recovery Alert, Weekly Summary | Health home/review |
| KnowledgeOS | — | — |
| ExecutionOS | Review, Due Action | Execution review |

Do not copy this list into another roadmap. Composition contract tests must
continue to enforce one presentation spec and one executable outcome fixture
for every production agent.

The Execution Review agent is an implementation collaborator for the single
domain Review surface. It is hidden from Settings and does not render a second
named result card. Specialized detector agents may also be hidden when their
output is already owned by a primary product surface.

## User-Visible States

### Scheduled LLM assistants

Weekly Wealth Review and Weekly Health Summary are production LLM tasks.
`app/agents/scheduled_agent_composition.dart` adapts the existing domain
registrations without changing their stable IDs. Legacy deterministic analysis
helpers remain available to domain code/tests, but are not a report fallback.
The shared executor uses the existing `FrbChatRunner` native tool loop, not an
additional LLM loop. Model absence or execution failure never publishes a
rule-based replacement report.

Users can create weekly tasks in Settings or through `propose_scheduled_task`.
Chat proposals require the existing confirmation path before activation.
Tasks are owner-scoped, device-local `scheduled_agent_tasks` definitions;
they are not synced or included in encrypted backups in this version. Task
deletion archives the definition and retains reports/history. Domain reset
removes that domain's definitions and associated run/preference rows.

Each task grants read-only access to one enabled domain, using the currently
configured model service. Both the advertised catalog and actual dispatch
registry exclude writes, proposals, interactions, shell memory and other
domains. Definitions contain instructions, not executable scripts. User
instructions and retrieved evidence cannot expand these privileges. Task
creation is never exposed inside a scheduled run.

Weekly schedules use a local-calendar weekday/hour/minute; device timezone
changes follow device local time. Missed periods coalesce into one latest run.
Manual previews do not move automatic scheduling. A failed automatic attempt
backs off for one hour. Foreground launch/resume performs catch-up; no exact
background or server execution guarantee is made. Runs are limited to four
tool rounds, twelve tool calls, 4096 output tokens per model round and two
minutes. Current owner, active domain, task revision and enablement are checked
again before tool dispatch and report persistence.

LLM reports require structured JSON and references to actual successful tool
results. Host-owned references contain the source tool, capture time and
result, never model-invented routes. Statistics remain authoritative tool
outputs; interpretation and report text come from the LLM. Evidence existence
checks do not constitute semantic verification of every model claim.

| State | Meaning | UI behavior |
|---|---|---|
| `idle` | Enabled and waiting | Show next/last run and allow manual run |
| `running` | Reading, computing, or invoking the runtime | Show bounded progress and prevent duplicate run |
| `noFinding` | Completed with nothing worth surfacing | Show lightweight history/status |
| `ready` | A user-visible artifact exists | Render the owning domain result surface |
| `failed` | The run failed | Show a safe reason, repair action, and retry |
| `disabled` | Agent or owning domain is disabled | Allow re-enable from Settings where applicable |

Run state is persisted in `AgentRunStore`; scheduling uses the last non-failed
completion time rather than in-memory timestamps or run start time.

## Result Contract

`AgentArtifact` is the shared user-visible result shape. It carries:

- owning agent and domain;
- status, severity, title, summary, and structured insights;
- evidence references and optional affected-object references;
- registered actions and follow-up intents;
- trace id and lifecycle timestamps;
- dismissed, snoozed, and expiry visibility state.

Artifact ids should be deterministic where reruns represent the same logical
result. Upsert must preserve local visibility state for the same owner and must
never leak dismissed/snoozed state across users.

Agent run, artifact, and preference tables are local-only. They are not Sync v3
source rows and are not part of encrypted user-data backup unless a future
design explicitly changes that policy.

Artifacts are temporary explanations, not durable personal Memory. Repeated
runs reconcile stable finding identities; they do not append episodic model
summaries to `memories`.

## Presentation Contract

Reusable UI:

- `AgentResultCard` for compact domain placement;
- `AgentRunStatusCard` for Settings and status surfaces;
- the shared artifact detail sheet/body for summary, evidence, actions, trace,
  history, dismiss, and snooze behavior.

Presentation rules:

- Keep domain pages dense: emphasize at most one primary result and a small
  number of secondary summaries.
- Use one primary action. Put snooze, dismiss, and transparency/history entry
  points in secondary affordances.
- Use object-specific copy such as “Review recovery signal”, not marketing copy
  explaining AI.
- Follow-up chips carry registered intent, object reference, artifact id,
  domain, and evidence context through `askAi()`.
- Use Forui and the local design system; do not nest cards or create a full
  screen agent dashboard.
- Compact viewports must keep title, close action, body, and primary action
  reachable without overflow.

## Preferences, Triggers, And Attention

Settings exposes active, user-configurable presentation specs only and supports:

- enable/disable;
- manual run;
- latest status and artifact;
- run history.

Disabling an agent prevents manual, scheduled, retry, and background-due runs
at the runner boundary. Disabling an optional domain also removes its agent
composition and cancels/ignores its background work.

`AgentTriggerSpec` supports schedule, event, threshold, state transition,
freshness, and manual policy. The coordinator debounces and de-duplicates
signals before the runner records concrete run provenance. A schedule is a
fallback, not the default reason to call an LLM when no state changed.

Every proactive result is evaluated by `AttentionArbiter` as `silent`,
`surface`, or `interrupt`, using novelty, severity, confidence, actionability,
freshness, evidence completeness, suppression state, notification eligibility,
and a global 24-hour interrupt budget. Domain Agents do not call notification
services directly.

The Life background callback reads only a precomputed primitive snapshot and
runs deterministic attention logic. It can persist a pending attention
decision and post an `interrupt` notification, but cannot invoke an LLM, read
Memory, dispatch tools, apply proposals, or mutate business data. Foreground
startup imports that decision and performs any full synthesis.

## Evidence, Proposals, And Transparency

- Ready results cite navigable `EvidenceAnchor`s where they refer to local
  source state.
- An agent must not infer an anchor from an arbitrary JSON id.
- Mutating actions route through active-domain proposal kinds and the composite
  proposal applier.
- Artifact actions must declare a registered intent and explicitly target the
  current `agent_artifact` object when they open an AI follow-up.
- Visible ready artifacts carry a trace id that resolves through the local AI
  transparency surface.
- Read tools for runs/artifacts enforce owner, active domain, active agent, and
  visibility checks; a deep link must not bypass those checks.

## Evaluation Contract

The executable agent outcome corpus is the regression source of truth. Cases
cover the behavior appropriate to each agent, including:

- ready results with expected insights, evidence, severity, and action intent;
- no-finding behavior;
- missing LLM profile and explicit failure for scheduled LLM tasks; existing
  non-task agents retain only their documented fallback policies;
- tool/runtime failure and budget exhaustion;
- prompt injection in retrieved content;
- domain opt-out and inactive-agent behavior;
- unexpected actions, proposal kinds, evidence ids, or forbidden claims.

The policy corpus separately evaluates whether a result deserved attention:

- `should_surface` and `should_stay_silent`;
- duplicate and unchanged finding suppression;
- stale or inactive-domain evidence;
- missing evidence, low confidence, and non-actionable suggestions;
- notification eligibility and interrupt-budget exhaustion;
- deterministic no-model-call gating.

Structured feedback records accepted, dismissed, snoozed, completed, and
undone outcomes with the originating Life-context, finding, and attention
fingerprints. Feedback is local policy evidence and never becomes Memory.

The fixed Memory answer-quality gate emits a privacy-safe JSON aggregate with
case/pass counts plus forbidden-claim, forbidden-evidence, missing-fact, and
missing-evidence failure counts. It includes only stable failing fixture ids;
questions, answers, facts, evidence ids, and retrieved content are excluded.
Separately, every action route declared by the Agent outcome corpus is opened
through the production `GoRouter` in `router_test.dart`. Evidence-bearing cases
also declare an evidence-type-to-route contract: exact workflow paths stay
exact, while entity details use a trailing `*` for the encoded id suffix. The
outcome evaluator rejects evidence sent to the wrong route family, and the
router test instantiates every dynamic family with a representative id. A
string-shaped route that resolves to the error page therefore fails the gate.

New production agents must land composition metadata, focused unit tests, and
executable ready and no-finding outcome cases in the same change. Rolling
quality/noise metrics and cross-domain outcome evaluation are completed LifeOS
baseline contracts; changes must extend those shared contracts rather than
creating Agent-specific reporting or attribution models.

## Adding Or Changing An Agent

1. Implement the named domain use case under `features/<domain>/agents/`.
2. Keep business calculation in deterministic domain services or tools.
3. Produce shared run states and `AgentArtifact`; do not invent a private
   result model.
4. Do not write Agent summaries to Memory or call notification services from
   the Agent. Emit stable findings/artifacts and let the attention layer decide.
5. Register the agent, presentation spec, intents, placement, and optional
   background bootstrap through the owning `DomainPack`.
6. Route follow-up through `askAi()` and writes through proposals.
7. Add owner/domain/visibility checks for any new read or deep-link path.
8. Add focused runner/store/UI tests and executable outcome and policy cases.
9. Verify the active/inactive domain composition contract.

## Non-Goals

- A global agent inbox or full-screen agent dashboard.
- A second chat destination.
- An open-ended automation/workflow builder, arbitrary scripts, automatic
  business writes, or task-to-task recursion. Confirmed read-only scheduled
  LLM analysis tasks are supported.
- Agent-to-agent calls.
- Silent modification of user-authored content or commitments.
- Syncing ephemeral run/artifact lifecycle tables.

## Verification

Run the focused tests for the changed domain plus:

```bash
cd apps/mobile
flutter analyze --fatal-infos
flutter test test/core/ai/agents
flutter test test/core/ai/regression
flutter test test/app/domain_composition_test.dart
```

Use the repository's `rtk` prefix when running these commands locally.
