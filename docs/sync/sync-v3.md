# Sync Protocol — NaviWealth v3

Status: **Active**.

## Document Contract

Owns the Sync v3 wire protocol, row-state conflict semantics, acknowledgements,
cursors, and domain reset generations. It does not own domain table membership;
that inventory comes from `sync_table_registry.dart`. Fixtures and Dart/Rust
serializer tests are authoritative for exact payloads.

The protocol uses row-state/LWW sync, explicit accepted acknowledgements, and
per-domain reset generations so an OS can be permanently erased across every
device without an offline device resurrecting stale rows.

## Row model

Every `RowChange` carries:

- `table`: domain-prefixed row family (`fin:`, `health:`, `know:`, `exec:`),
- `id`, `payload`, `version`, `deleted`,
- `generation`: the client's current generation for the owning domain.

The protocol header is `Sync-Protocol-Version: 3`.

## POST /sync

The request remains `{device_id, since, changes}`. The server accepts a row
only when its JWT domain claim allows the row family and its `generation`
equals the authoritative generation in `sync_domain_generations`.

The response adds:

```json
{
  "seq": 42,
  "changes": [],
  "more": false,
  "accepted": [],
  "domain_generations": {
    "finance": 0,
    "health": 2,
    "knowledge": 1,
    "execution": 0
  }
}
```

Before applying pulled rows, a client compares this map with its local
`sync.domain_generation.<owner>.<domain>` values. Any mismatch causes a local hard
reset of that domain's source rows, caches, memories, audit projections,
agent state, and outbox pointers. Only response rows matching the new
generation may then be applied.

### Atomic conflict resolution and pull horizon

For one `(user_id, table, id)`, the winning state is the greatest ordered pair
`(version, device_id)`. Both that comparison and the authoritative generation
check execute inside the write SQL. A stale concurrent writer, a duplicate key
later in one batch, or an equal version/device retry cannot overwrite the winner.
Only a winning replacement receives a new monotonically allocated `seq`.
`accepted` acknowledges domain/protocol acceptance; it does not mean the submitted
state won LWW. A newer server state remains authoritative.

Each pull first captures that user's current `MAX(seq)` as a horizon, then reads
only `since < seq <= horizon`, excluding the caller's rows. If row-count or
payload-size limits truncate the page, `more` is true and the cursor is the last
included row's `seq`; otherwise it is the captured horizon. A concurrent insert
or replacement receives a later sequence and remains eligible on the next pull.
The server never performs a later MAX read to advance past unseen rows. If an
invalid/ahead cursor or erasure leaves `since` above the current horizon, the
empty final page returns the current horizon so future writes remain reachable.

### Client visibility and progress

A cursor belongs to `SyncScope(ownerUserId, enabledDomains)`, with the domain set
sorted before persistence. Another owner or domain combination starts with its
own cursor, preventing earlier filtered pulls from hiding newly visible rows.
Local HLC ordering is device-local and independent of the pull scope.

The engine checks that response `domain_generations` keys exactly match its
enabled domains before applying data, acknowledging pointers or advancing the
cursor. A token still carrying old domain claims fails with
`sync_domain_claim_mismatch` until auth refresh completes. Superseded sync
sessions cannot apply their response after owner/token/domain composition changes.

Pending collection and queue depth include only the current owner's enabled
domains. Other owners' and disabled domains' pointers remain queued. Rows absent
from `accepted` remain dirty, but their keys are deferred for the rest of the
current cycle so they cannot starve later batches. Remaining rejection is reported
as `sync_rows_rejected`; generation-reset rejection is handled by the domain reset.
A page claiming `more` without advancing its cursor fails instead of looping.

## POST /sync/reset-domain

Request:

```json
{ "domain": "knowledge" }
```

The server atomically:

1. increments `(user_id, domain).generation`,
2. physically deletes all `sync_rows` under that domain prefix,
3. records reset time and authoring device.

Response:

```json
{ "domain": "knowledge", "generation": 2 }
```

The generation guard is also present in the row insert SQL, so a sync request
that races with the reset cannot reinsert a stale row after the generation
increment.

## Storage

Migration `0019_sync_domain_generations.sql` adds `sync_rows.generation` and:

```sql
CREATE TABLE sync_domain_generations (
  user_id TEXT NOT NULL,
  domain TEXT NOT NULL,
  generation INTEGER NOT NULL,
  reset_at TEXT NOT NULL,
  reset_device_id TEXT NOT NULL,
  PRIMARY KEY (user_id, domain)
);
```

Generation zero is implicit until the first reset. Clients and servers must
both use protocol version 3.

## Client registry

`apps/mobile/lib/core/sync/sync_table_registry.dart` is the client SSOT for
syncable tables. Each `SyncTableRegistration` declares its row-family prefix,
primary key, owner scope, backfill eligibility, and backup eligibility. Row
serialization and application use the shared storage/applier implementation;
the registry does not contain per-table payload codecs or applier callbacks.
Local table names remain unprefixed; `fin:`、`health:`、`know:` and `exec:` are
added and stripped only at the sync boundary. Local-only and derived tables
must not enter this registry.

## Client business invariants and compatibility

Sync selects a winning state per row. `RowApplier` applies one received page in
a Drift transaction with deferred foreign-key checks; this does not guarantee
that every row of a business aggregate arrives in the same page or belongs to
the same authored version.

Domains own aggregate completeness and calculation eligibility. Watchlist paper
allocations already use a deterministic head, immutable versions, and a pending
state while the selected version is incomplete. See
[FinanceOS](../domains/financeos-domain.md#watchlist-paper-simulations) for that
business contract. Other multi-row changes must state their own constraint and
partial-arrival behavior; they must not infer business atomicity from per-row
LWW or move financial validation into the backend.

The applier validates a table's registered prefix and owner before applying it.
Known columns are updated in place using an UPSERT; columns omitted by an older
client keep their current values. The wire version supplies the stored HLC.
Unknown fields on a supported row are retained as opaque JSON in the local-only
`sync_row_extras`, keyed by owner, table and row id. Dirty-row serialization merges
them back into the payload, with current known columns taking precedence. A newer
winning row updates retained fields; absence preserves them, and explicit null
clears their value. Stale rows cannot modify either source data or opaque state.
The page transaction rolls both back together on failure. Domain reset and backup
restore clear compatibility state in their owner/table scope.
Push collection excludes another owner's rows while preserving their dirty
pointers; it still clears genuine orphan pointers through the normal ack path.

Before exposing the database to callers, the client compares a signature of its
codec, namespace, registered primary keys, owner scope and actual supported column
types with the persisted signature. A change atomically hydrates newly supported
opaque fields, invalidates stored scope cursors and marks a schema replay. Pending
local mutations remain queued and a strictly newer local HLC always wins. During
this replay equal-version rows may hydrate fields lost by clients predating opaque
preservation. The replay marker survives interrupted pagination and clears only
after the final successful page and durable cursor write. An unchanged signature
keeps the scoped cursors intact.

Unknown prefixes and unsupported tables are skipped with diagnostics. Adding
support changes the signature and re-pulls current server state, including rows
previously skipped after cursor advancement. This is additive client compatibility
within Sync v3. It is not schema negotiation, a historical event log, or a migration
of retired entities. Replay cannot reconstruct values already overwritten on the
server, rows erased by a domain reset, or new enum semantics unsupported by older
business code. Additive columns need nullable values or backward-compatible
defaults; new required columns without defaults need a separate migration and
old-client contract. Synced source changes must document those limits and provide
mixed-version tests.

## Encryption boundary

Current Sync payloads are JSON that the backend can parse; Sync v3 does not
provide end-to-end encryption. Native database-at-rest encryption and encrypted
local archives protect separate storage boundaries. A future Sync E2EE change
requires its own threat model, key custody/recovery, and client compatibility
decision. The production stability gate below supplies operational evidence;
it does not establish confidentiality or key recovery guarantees.

## Data-management behavior

Settings → Data & Storage exposes the protocol through explicit operations:

- cache cleanup deletes only registered, rebuildable local tables;
- current-device reset removes one OS locally and leaves cloud state intact;
- delete everywhere advances the server generation and then mirrors the reset
  locally;
- reset all applies the same operation to every registered OS while preserving
  account, device, app settings, and FX configuration;
- per-OS encrypted backup/restore operates independently of reset generation;
- AI/chat/memory/agent history is a separate local-only cleanup resource.

Automatic maintenance applies retention to expired or old derived history and
records each run locally. It never deletes synced source tables.

## Production stability gate

The mobile client aggregates every terminal cycle into UTC-day buckets in
owner-scoped local-only `sync_meta` storage (`sync.stability.daily.<owner-key>`).
Retention covers the newest observed UTC day and its preceding 29 days. Each
bucket preserves exact cycle/outcome counters plus first and last timestamps;
higher polling frequency does not evict earlier days or approximate success rate.
Only timestamps, failure classes, conflict and generation-reset counters are
retained; row ids, payloads, error text and account data are excluded.

A release window is eligible after at least 10 cycles spanning 14 actual days,
measured from first to last cycle timestamp rather than the number of buckets.
It passes only with at least 95 percent successful cycles, zero fatal protocol
errors and zero generation-reset failures. Reports expose `insufficientData`,
`failing` or `passing`, exact issues, window timestamps, remaining cycles and
observation duration. The UI presents insufficient coverage as collecting.
Retryable failures, failure-to-success recoveries, local LWW wins and ignored rows
remain available as aggregate diagnostics.

Settings may copy the privacy-safe aggregate report as JSON. This gate supplies
prerequisite operational evidence for a future Sync E2EE decision; serializers or
synthetic tests cannot establish a real 14-day release window.
