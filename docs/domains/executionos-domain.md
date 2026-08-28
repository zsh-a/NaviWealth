# ExecutionOS Domain SSOT

ExecutionOS is the LifeOS execution layer. It is user opt-in, local-first, and
focused on plans, next actions, and progress review.

## Document Contract

Owns ExecutionOS objects, Today/Plans/Review behavior, source references,
tools, and Agents. It does not own sibling-domain evidence semantics or shared
proposal infrastructure. `execution_pack.dart`, Execution repositories, and
focused Execution tests are authoritative for the current implementation.

## Scope

Included:

- Personal todos as lightweight Actions.
- Plans for bounded delivery work or a longer-running promise. The current
  storage keeps these as Project and Commitment records for compatibility.
- Progress entries for check-ins, blockers, scope changes, and completion.
- Today and Plans shell tabs. Review is a contextual destination reached from
  signals and the command palette.
- Cross-domain source references by neutral row-family metadata.

Excluded:

- Team collaboration, comments, assignment, permissions, or publishing.
- Jira / Linear style project management.
- Kanban-first workflows, gantt charts, dependency graphs, or timesheets.
- Automatic AI writes to user commitments or actions without confirmation.

Core rule: Action is the reusable next-step primitive. A Plan is a lightweight
roll-up, not a separate task system. The Project/Commitment distinction is
secondary context; Milestones can be added later only when a current workflow
needs them.

## Shell Registration

ExecutionOS is registered through `kExecutionPack` in
`apps/mobile/lib/app/domain_packs.dart`.

Contributions:

- Scope: `DomainScope.execution`.
- Shell: `features/execution/composition/execution_domain_shell.dart`.
- Routes: `features/execution/composition/execution_routes.dart`.
- Primary tabs: Today, Plans.
- Tools: `features/execution/execution_ai_tools.dart`.
- Command palette: `features/execution/composition/execution_command_palette.dart`.
- Proposal kinds: `features/execution/composition/execution_proposal_kinds.dart`.
- Proposal applier: `features/execution/composition/execution_proposal_applier.dart`.

ExecutionOS is active only when the user enables it in Settings.

## Domain Objects

| Object | Purpose | Storage |
|---|---|---|
| Plan | Bounded or ongoing container for actions | `execution_projects` / `execution_commitments` |
| Action | Personal todo / next concrete step | `execution_actions` |
| Update | Check-in, blocker, scope change, completion note | `execution_progress_entries` |

Domain models:

- `features/execution/domain/execution_models.dart`

Repository:

- `features/execution/data/execution_repository.dart`

## Persistence And Sync

Tables:

- `core/persistence/execution_tables.dart`

Synced tables use `SyncableTable` and the `exec:` row-family prefix:

- `exec:execution_projects`
- `exec:execution_actions`
- `exec:execution_commitments`
- `exec:execution_progress_entries`

Local table names stay unprefixed. Prefixing and stripping happen at the sync
boundary.

## UI

| Tab | Purpose |
|---|---|
| Today | Persistent daily Top 3 plus explicitly scheduled actions, due work, and blocked follow-through |
| Plans | Later actions, active plans, existing long-term commitments, and a closed-work archive |
| Review | Focus, stalled/blocked work, missing next actions, overdue targets, repeated blockers, throughput, source outcomes, recently closed actions, and confirmed batch next-action creation |

Key files:

- `features/execution/ui/execution_today_page.dart`
- `features/execution/ui/execution_commitments_page.dart`
- `features/execution/ui/execution_review_page.dart`
- `features/execution/ui/execution_search_sheet.dart`

The daily Top 3 is device-local, persists for the current local calendar day,
and resets the next day. Users pin or remove Actions from the Action menu. An
empty Top 3 can show the latest Review artifact's `recommended_focus_ids`, but
the recommendation is never adopted until the user explicitly confirms it.

Today exposes only the daily focus and blocked-work lenses. Unscheduled backlog
and the complete open inventory belong to Plans, not the daily workspace.
An Action enters Today because it is scheduled for today or earlier, is already
in progress, or is blocked; priority alone does not promote an unscheduled
Action into Today. Focus is a separate local Top 3 selection, not another
Action status.
Plans uses one Add entry point that offers Action or multi-step Plan creation;
search is also owned there instead of repeated on every tab.

The shared Add entry asks only whether the user is creating an Action or a
multi-step Plan. New Action capture starts with title plus Inbox / Today /
Tomorrow and keeps priority, dates, one unified `Belongs to` relation, and
notes behind an optional detail disclosure. Plans use a target date as the
primary time expression; the stored horizon remains compatibility metadata and
is not a second user-facing planning choice. Choosing a Commitment inherits its
Project atomically instead of asking the user to configure both fields.
Manual status changes show a short Undo action. Blocking requires a concrete
reason, which is stored as blocker progress instead of a generic placeholder.
Progress recorded from an Action, Project, or Commitment is context-bound in
the UI. Status changes create their own progress entry; a manual update does
not require a second choice about whether it should also mutate Action status.

Actions created from a Knowledge decision preserve the source family and row
id. App-level composition de-duplicates that source link, so a decision has one
current follow-up action while a dropped action can be replaced explicitly.

Plans presents Projects and Commitments in one plan inventory, with object type
as secondary context. Closed work is a subordinate archive entry rather than a
peer mode competing with active work.

Review is a current-week digest. Attention findings and the one batch
next-action CTA come first. Weekly activity is collapsed by default, while
Agent run status and freshness live behind Review details. Progress is normally recorded from the Action,
Project, or Commitment that owns it; Review does not expose a global create
Progress action or historical time-window switcher.

Today, Commitments, and Review share an all-status search across Action title
and note, Project title and description, and Commitment title and description.
Default open-list reads are complete rather than silently capped; explicit
limits are reserved for callers that intentionally paginate.

## Cross-Domain References

ExecutionOS may reference source work from FinanceOS, HealthOS, or KnowledgeOS
through neutral metadata only:

```text
sourceDomain
sourceRowFamily
sourceRowId
sourceLabelSnapshot
```

It must not import sibling domain business entities.

Completed-action outcome badges are observational before/after comparisons,
not causal attribution. A result is emitted only when the Action has a concrete
source row id, that source family completed a successful current evaluation,
and the evaluation occurred after completion. Loading, failed, disabled, or
otherwise unevaluated source families produce no outcome instead of being
misreported as cleared. User copy says whether the signal is currently
detected; it never says the Action caused the change.

Aggregate read-model sources use a stable, bounded identity rather than a
guessed business row id. The current Finance budget-pressure loop uses
`fin:budgets` plus `month:YYYY-MM`; a settled monthly read can therefore match
the same posture signal or establish that it is no longer detected.

## AI Tools

Tool barrel: `features/execution/execution_ai_tools.dart`.

Read tools:

- `list_open_actions`
- `list_blocked_actions`
- `summarize_execution_progress`

Proposal tools:

- `propose_action`
- `propose_action_status_update`
- `propose_project`
- `propose_commitment`
- `propose_progress`

Rules:

- `propose_*` tools return `ProposalEnvelope`s; they do not directly write
  ExecutionOS tables.
- Confirmed `execution_*` proposals route through
  `ExecutionProposalApplier`.
- AI should keep suggested actions concrete, next-step sized, and tied to
  source references when they came from another domain.
- `list_open_actions` and `summarize_execution_progress` should include
  relation titles where available so AI can attach proposals to the right
  Project or Commitment without guessing from ids.
- Existing Action status changes must use `propose_action_status_update`
  after identifying the target Action. Do not create a duplicate Action just
  to represent completion, blocking, resuming, or dropping an existing one.
- Cross-domain source identity is atomic: `source_domain`,
  `source_row_family`, and `source_row_id` must be supplied together.
  Applying a proposal rejects a near-identical open Action tied to the same
  concrete source.
- Proposal application validates every referenced Action, Project, and
  Commitment. A Commitment's Project is inherited when omitted, while
  conflicting Project / Commitment relations are rejected.

## Agents, Review, And Memory

The weekly Review agent reads complete bounded snapshots of open Actions,
active Projects/Commitments, the last seven days of progress and closed
Actions, and observational source-outcome summaries. It emits stable local
findings for blocked/due/stalled Actions, Projects or Commitments without a
next Action, overdue targets, repeated blocker entries, and Today overload.
Findings resolve when the signal disappears; dismiss/snooze applies only while
the evidence fingerprint remains unchanged.

Review artifacts preserve human-readable titles, recommend a Top 3 focus set,
show weekly completed/dropped throughput, and expose a proposal action for
turning diagnostics into concrete next Actions. Progress entries are also
indexed into typed local Event storage and `source_fact` Memory; blockers and
completion/scope changes receive higher event importance. Derived findings and
memory indexes do not sync.

The Review page can turn selected missing Project/Commitment next steps from
the artifact proposal payload into high-priority Actions after explicit user
confirmation. It re-checks current open Actions before presenting the batch
and writes only the selected rows through the repository.

`ExecutionDueActionAgent` runs daily, finds open Actions due within the next
24 hours (including overdue Actions), and writes a reminder artifact with
action-detail evidence routes. It never posts a notification directly; any
proactive interruption must pass through the global attention policy.
