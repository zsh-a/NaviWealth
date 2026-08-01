# Sync Protocol — NaviWealth v3

Status: **Active** (2026-07-12).

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
`sync.domain_generation.<domain>` values. Any mismatch causes a local hard
reset of that domain's source rows, caches, memories, audit projections,
agent state, and outbox pointers. Only response rows matching the new
generation may then be applied.

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
primary key, owner scope, backfill behavior, payload codec, and row applier.
Local table names remain unprefixed; `fin:`、`health:`、`know:` and `exec:` are
added and stripped only at the sync boundary. Local-only and derived tables
must not enter this registry.

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

The mobile client normalizes terminal cycle samples by timestamp and keeps the
latest 50 in the local-only `sync_meta` key
`sync.stability.samples.v1`. Samples contain only timestamps, success/failure
classes, conflict counters, and generation-reset counters; row ids, payloads,
error text, and account data are excluded.

A release window is eligible to pass after at least 10 cycles spanning 14 days.
It passes only when successful cycles are at least 95 percent, fatal protocol
errors are zero, and generation-reset failures are zero. The report exposes a
structured `collecting`, `failing`, or `passing` state, exact gate issues,
window timestamps, and the remaining cycles and observation time. It also
retains retryable failure counts, failure-to-success recoveries, local LWW wins,
and ignored rows for diagnosis. Settings may copy this aggregate report as
privacy-safe JSON, which must not contain row ids or payloads. This gate is
prerequisite evidence for any future Sync E2EE decision; serializer fixtures
alone do not satisfy it, and a real 14-day release window is still required.
