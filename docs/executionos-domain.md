# ExecutionOS Domain SSOT

ExecutionOS is the LifeOS execution layer. It is user opt-in, local-first, and
focused on personal commitments, next actions, and progress review.

## Scope

Included:

- Personal todos as lightweight Actions.
- Commitments for work that needs a longer-running promise.
- Progress entries for check-ins, blockers, scope changes, and completion.
- Today, Commitments, and Review shell tabs.
- Cross-domain source references by neutral row-family metadata.

Excluded:

- Team collaboration, comments, assignment, permissions, or publishing.
- Jira / Linear style project management.
- Kanban-first workflows, gantt charts, dependency graphs, or timesheets.
- Automatic AI writes to user commitments or actions without confirmation.

Core rule: Action is the reusable todo primitive. Project and milestone
concepts can be added later only when a current workflow needs them.

## Shell Registration

ExecutionOS is registered through `kExecutionPack` in
`apps/mobile/lib/app/domain_packs.dart`.

Contributions:

- Scope: `DomainScope.execution`.
- Shell: `features/execution/composition/execution_domain_shell.dart`.
- Routes: `features/execution/composition/execution_routes.dart`.
- Tabs: Today, Commitments, Review.
- Command palette: `features/execution/composition/execution_command_palette.dart`.

ExecutionOS is active only when the user enables it in Settings.

## Domain Objects

| Object | Purpose | Storage |
|---|---|---|
| Action | Personal todo / next concrete step | `execution_actions` |
| Commitment | Longer-running promise or focus area | `execution_commitments` |
| ProgressEntry | Check-in, blocker, scope change, completion note | `execution_progress_entries` |

Domain models:

- `features/execution/domain/execution_models.dart`

Repository:

- `features/execution/data/execution_repository.dart`

## Persistence And Sync

Tables:

- `core/persistence/execution_tables.dart`

Synced tables use `SyncableTable` and the `exec:` row-family prefix:

- `exec:execution_actions`
- `exec:execution_commitments`
- `exec:execution_progress_entries`

Local table names stay unprefixed. Prefixing and stripping happen at the sync
boundary.

## UI

| Tab | Purpose |
|---|---|
| Today | Today's open actions, blockers, and high-priority follow-through |
| Commitments | Active commitments plus open actions |
| Review | Recent progress, blockers, and completion notes |

Key files:

- `features/execution/ui/execution_today_page.dart`
- `features/execution/ui/execution_commitments_page.dart`
- `features/execution/ui/execution_review_page.dart`

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
