# ExecutionOS Domain SSOT

ExecutionOS is the local-first LifeOS execution layer. It turns intent into a
small set of plans, concrete next actions, and reviewable progress.

## Document Contract

This document owns ExecutionOS objects, Today/Plans/Review behavior, neutral
source references, tools, and agents. Shared proposal infrastructure and the
meaning of sibling-domain evidence remain outside this domain.

Production code is authoritative:

- `apps/mobile/lib/app/domain_packs/execution_pack.dart`
- `apps/mobile/lib/features/execution/`
- focused tests under `apps/mobile/test/features/execution/`

## Product Boundary

Included:

- Plans for outcomes that need more than one action.
- Actions as concrete next steps.
- Progress entries for check-ins, blockers, scope changes, completion, and
  dropped work.
- Today, Plans, and contextual Review workflows.
- Neutral references to source rows in FinanceOS, HealthOS, or KnowledgeOS.

Excluded:

- Team assignment, comments, permissions, or publishing.
- Kanban-first project management, gantt charts, dependencies, or timesheets.
- Milestones, recurring-task engines, or another hierarchy above Plan.
- AI writes without explicit proposal confirmation.

The core rule is deliberately small: Plan is the only grouping primitive and
Action is the only next-step primitive.

## Shell Registration

`kExecutionPack` registers the domain through
`apps/mobile/lib/app/domain_packs.dart` and contributes:

- scope `DomainScope.execution`;
- Today and Plans shell tabs;
- contextual Review and detail routes;
- device tools and prompt blocks;
- command-palette entries;
- proposal kinds and their applier;
- ExecutionOS agents.

ExecutionOS is active only when enabled in Settings.

## Domain Objects

| Object | Purpose | Storage |
|---|---|---|
| Plan | Multi-step outcome or ongoing area of focus | `execution_plans` |
| Action | Concrete personal next step | `execution_actions` |
| Progress | Check-in, blocker, scope change, completion, or drop record | `execution_progress_entries` |

Models live in `features/execution/domain/execution_models.dart`. Repository
operations are composed by `features/execution/data/execution_repository.dart`.

Every Action and Progress row has at most one optional `plan_id`. Closing or
deleting a Plan moves its open Actions to Inbox so follow-through is not lost.

## Persistence And Sync

Tables are defined in `core/persistence/execution_tables.dart`. All three
families sync with the `exec:` prefix:

- `exec:execution_plans`
- `exec:execution_actions`
- `exec:execution_progress_entries`

Local table names stay unprefixed; prefixing happens only at the Sync v3
boundary. Derived review findings, daily focus selection, events, and memory
indexes are local-only.

Schema v80 intentionally resets ExecutionOS data to this canonical model. It
does not preserve the removed hierarchy.

## UI

| Surface | Responsibility |
|---|---|
| Today | Daily Top 3, scheduled/due work, and blocked follow-through |
| Plans | Inbox actions, active Plans, search, and a subordinate closed archive |
| Review | Current-week attention, throughput, findings, and confirmed batch next actions |

Key files:

- `features/execution/ui/execution_today_page.dart`
- `features/execution/ui/execution_plans_page.dart`
- `features/execution/ui/execution_review_page.dart`
- `features/execution/ui/execution_search_sheet.dart`

The daily Top 3 is device-local and resets with the local calendar day. Review
may recommend focus IDs, but Today adopts them only after confirmation.
Focus ordering and removal are shown only in the explicit Edit focus mode.
Focus rows complete actions directly through the shared status/undo controller.
Foreground time refreshes on resume and minute ticks; local-day changes refresh
Today and reset the device-local focus selection without restarting the app.
Unscheduled backlog stays in Plans; priority alone never promotes an Action to
Today.

The shared Add entry offers only Action or Plan. Action capture starts with a
title and quick scheduling, while priority, dates, one `Belongs to` Plan
relation, and notes are progressively disclosed. Plan capture uses a target
date as its primary time expression.

Blocking requires a concrete reason and records blocker progress. Manual
status changes expose Undo. Progress opened from an Action or Plan keeps that
context fixed instead of asking the user to choose it again.

Today, Plans, and Review share search across Action title/note and Plan
title/description. Default open-list reads are complete; explicit limits are
reserved for intentional pagination or agent snapshot bounds.

## Cross-Domain References

ExecutionOS stores neutral source identity only:

```text
sourceDomain
sourceRowFamily
sourceRowId
sourceLabelSnapshot
```

The domain must not import sibling business entities. App composition
de-duplicates source-linked Actions so a source decision has one current
follow-up; a dropped Action may be explicitly replaced.

KnowledgeOS Decision detail uses this seam as an explicit user action. The
selected Decision option becomes the default Action title and the Action keeps
the exact `know:knowledge_decisions` source identity plus a Decision-question
label snapshot, so repeated taps open or reuse the existing follow-up instead
of creating duplicates.

Completed-action outcome badges are observational comparisons, not causal
claims. They appear only after a successful, current evaluation of the exact
source identity.

## AI Tools And Proposals

Tool barrel: `features/execution/execution_ai_tools.dart`.

Read tools:

- `list_open_actions`
- `list_blocked_actions`
- `summarize_execution_progress`

Proposal tools:

- `propose_action`
- `propose_action_status_update`
- `propose_plan`
- `propose_progress`

Rules:

- Proposal tools return envelopes and never write domain tables directly.
- Confirmed `execution_*` proposals pass through `ExecutionProposalApplier`.
- Referenced Action and Plan IDs must exist for the current owner.
- Cross-domain identity is atomic: domain, row family, and row ID are supplied
  together.
- Status changes update the existing Action; they do not create duplicate
  Actions.
- Read tools include Plan titles where available so the runtime does not infer
  relations from opaque IDs.

## Agents, Review, And Memory

The weekly Review agent reads bounded snapshots of open Actions, active Plans,
recent Progress, and closed Actions. It emits stable local findings for blocked
or due work, stalled Actions, Plans without a next Action, overdue targets,
repeated blockers, and Today overload.

Review artifacts preserve human-readable titles, recommend a Top 3 focus set,
show weekly throughput, and can propose high-priority next Actions for selected
Plans after confirmation. The UI re-checks current open Actions before applying
the batch.

Actions, Plans, and Progress are indexed into typed local events. Blockers,
completion, and scope changes receive higher importance. These indexes and
derived findings do not sync.

`ExecutionDueActionAgent` runs daily, finds open Actions due within 24 hours,
and writes a reminder artifact with Action detail evidence. Any proactive
interruption still passes through the global attention policy.
