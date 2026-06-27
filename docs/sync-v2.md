# Sync Protocol — NaviWealth (v2, row-state)

> Contract between client (Flutter, all platforms) and server (Cloudflare
> Workers + Rust + D1).
>
> **Supersedes [`sync-protocol.md`](./sync-protocol.md) (v1, OpLog).** v2 is a
> clean break — there is no on-wire compatibility with v1. The v1 doc is kept
> as deleted-history reference only.

Status: **Active v2.0** (2026-05-22).

## 0. Why v2

v1 modelled sync as an append-only **OpLog**: every mutation was an `Op`
(`insert`/`update`/`delete`), the server replayed ops into per-table
materialised rows, and new devices replayed the entire history. For a
**single-user, few-device, local-first** app that is over-built. The OpLog
gave no stronger guarantee than "row-level last-writer-wins" — which is
exactly what a per-row LWW register gives — but cost:

- an unbounded `op_log` table (no GC), so first-sync got slower forever;
- a schema-aware server that re-materialised every business table;
- a Hybrid Logical Clock with server re-stamping, merge rules and skew
  rejection (a skewed clock could block sync for hours);
- a client-side outbox that could be head-of-line-blocked by one poison op;
- per-table op appliers, op validation, backfill and applier-versioning.

v2 collapses all of that. **Sync the current state of each row, not the
events.** Each row is a last-writer-wins register. The server becomes a dumb
versioned blob store.

## 1. Goals & non-goals

### Goals

- **Local-first.** The client is the source of truth; the server is durable
  storage + fan-out. The implementation now *matches* that description.
- **Eventual consistency.** Two devices that have drained each other's
  changes converge to identical row state.
- **Deterministic conflict resolution.** Per-row LWW, total order on
  `(version, device_id)`. Same inputs ⇒ same final state on every device.
- **Tombstones, not hard deletes.** A delete is a row with `deleted = 1`.
- **Cheap & bounded.** One table server-side, one row per business row,
  no history. First-sync ships final state, never replays.
- **Never block on a clock.** Clock skew degrades LWW tie-break *quality*,
  never sync *availability*.

### Non-goals (v2)

- Field-level merge. LWW is whole-row (same as v1).
- E2EE. Server stores plaintext.
- Multi-tenant. Single user, scoped by JWT.
- Realtime is **Phase 2** (§10), not a non-goal — the wire model already
  supports it without a protocol bump.

## 2. Model

| Term | Definition |
|------|------------|
| **row** | One business-table row, identified by `(table, id)`. The unit of sync. |
| **payload** | The row's full column set as a JSON object. Opaque to the server. Client pushes may send `null` for deletes; stored tombstones use an empty JSON object. |
| **version** | Opaque, lexicographically ordered LWW token the authoring device assigns. The current client uses canonical HLC strings. |
| **device_id** | Stable UUID per install. LWW tie-breaker and echo filter. |
| **seq** | `i64` the server assigns to a row each time it is stored. Strictly monotonic per user. The pull cursor. |
| **cursor** | Highest `seq` a device has drained. Next sync sends `since = cursor`. |
| **dirty** | Client-only per-row flag: a local change not yet confirmed by the server. |

Two independent orderings, each the simplest tool for its job:

- **Conflict** (which write wins a row): `(version, device_id)` — works
  offline, no coordination. Skew only mis-picks a winner in the rare
  same-row-same-window race; it never stalls.
- **Pull cursor** (what is new since I last looked): server `seq` — a plain
  integer, assigned by the single authoritative server.

## 3. Server data model

The **entire** server-side sync schema is one table:

```sql
CREATE TABLE sync_rows (
  seq         INTEGER PRIMARY KEY AUTOINCREMENT,  -- pull cursor, monotonic
  user_id     TEXT    NOT NULL,
  table_name  TEXT    NOT NULL,
  row_id      TEXT    NOT NULL,
  payload     TEXT    NOT NULL,                   -- opaque JSON row; "{}" for tombstones
  version     TEXT    NOT NULL,                   -- client LWW token (opaque, ordered)
  device_id   TEXT    NOT NULL,                   -- author
  deleted     INTEGER NOT NULL DEFAULT 0,         -- 0 | 1
  updated_at  TEXT    NOT NULL,                   -- server receive time (diagnostics)
  UNIQUE (user_id, table_name, row_id)
);
CREATE INDEX sync_rows_pull ON sync_rows (user_id, seq);
```

`seq` is the SQLite rowid with `AUTOINCREMENT`, so it is strictly increasing
and never reused. A row is stored with `INSERT OR REPLACE`: an update deletes
the old row and re-inserts, which mints a **fresh, higher `seq`** — that is
how a changed row becomes visible to a `since`-cursor pull. `AUTOINCREMENT`
makes `seq` assignment atomic, so no counter and no `sync_state` table is
needed.

`version` is stored as `TEXT`: the server treats it as a fully opaque,
lexicographically-ordered token and never interprets it (so the client is
free to use an integer, an HLC string, or anything else that sorts the same
as its intended order). LWW compares it as a string, never with SQL
arithmetic.

The server does not know the business schema. `payload` is an opaque JSON
blob it never inspects. Live rows carry their full row JSON. Deleted inbound
rows may send `payload: null`; the server stores `{}` plus `deleted = 1`,
and clients materialise the tombstone from the row identity, version, and
deleted flag. There are **no per-table materialised tables**, no `op_log`,
no `sync_state`.

## 4. The version stamp & LWW

### 4.1 Client stamp

`version` is an **opaque, lexicographically-ordered token** the authoring
device assigns to a row. The only requirements: it sorts the same as the
write order, and it is monotonic per device.

The client uses its existing **HLC canonical string** —
`<wallMillis>.<counter:%04x>-<deviceId>` — for this token. It is monotonic
per device (`Hlc.tick` never regresses), and for 13-digit millisecond
timestamps it sorts lexicographically the same as the `(wallMillis, counter,
deviceId)` tuple. Crucially, **no skew rejection exists in v2**: a forward
clock jump just produces a large token; the server accepts it regardless, so
sync never stalls. The token is also written into the row's `payload`, so it
round-trips with the row.

(The server is agnostic here — a future client could swap the HLC string for
a plain monotonic integer with no protocol change.)

### 4.2 LWW rule

For a given `(table, id)`, the stored row is the one with the greatest
`(version, device_id)` pair, compared lexicographically:

```text
incoming wins  iff  incoming.version >  stored.version
               or  (incoming.version == stored.version
                     and incoming.device_id > stored.device_id)
```

`device_id` only breaks the (astronomically rare) exact-millisecond tie so
the order is total and convergence deterministic. Equal `(version,
device_id)` ⇒ same write ⇒ idempotent no-op.

Applied identically on **server** (push) and **client** (apply). Same rule,
both ends ⇒ convergence.

## 5. HTTP API

All endpoints:

- `Content-Type: application/json; charset=utf-8`
- `Authorization: Bearer <jwt>` required (401 otherwise)
- `Sync-Protocol-Version: 2` request header — server returns 426 on mismatch
- Errors use the `{ "code": "...", "message": "..." }` envelope from
  `apps/backend/src/error.rs`

### 5.1 `POST /sync`

One round trip does push **and** pull.

**Request**

```json
{
  "device_id": "1f5b0c3a-…",
  "since": 1287,
  "changes": [
    {
      "table": "fin:accounts",
      "id": "e2c4-…",
      "payload": { "name": "Brokerage", "currency": "USD", "...": "..." },
      "version": "1716381000123.0000-1f5b0c3a",
      "deleted": false
    }
  ]
}
```

- `changes` — locally `dirty` rows. **No ordering requirement** between
  rows; the server may process them in any order. `payload` is the full row
  (JSON object); for a delete send `"payload": null, "deleted": true`.
- `since` — the device's cursor. `0` for first sync.
- Constraints: `len(changes) ≤ 500`; body ≤ 1 MB; per-row `payload`
  ≤ 64 KB. Violations → `413 payload_too_large` (client splits).
- `device_id` must equal the JWT-bound device, and every change is attributed
  to it. Mismatch → `400 device_mismatch`.

**Response 200**

```json
{
  "seq": 1342,
  "changes": [
    {
      "table": "fin:assets",
      "id": "a1b2-…",
      "payload": { "...": "..." },
      "version": "1716381005000.0000-9f0e",
      "device_id": "9f0e-…",
      "deleted": false,
      "seq": 1340
    }
  ],
  "more": false
}
```

- `changes` — rows with `seq > since` **and** `device_id ≠ caller`
  (echo filter), ordered by `seq` ascending, capped at 500 rows / ~900 KB.
- `more` — `true` ⇔ the page was capped; the client immediately re-syncs
  with `since` = the last change's `seq` to drain.
- `seq` — the cursor the client adopts after applying this page:
  - `more == true`  → the last returned change's `seq`;
  - `more == false` → the server's global `MAX(seq)` for the user (so the
    client also fast-forwards past its own just-pushed rows, which were
    echo-filtered out).

**Processing order (server):** apply `changes` (LWW) first, then run the
pull query — so a row the caller just pushed and a peer's newer version of
it resolve before the same response is built.

**Errors:** `401 unauthorized`, `400 bad_request` / `device_mismatch`,
`413 payload_too_large`, `426 protocol_version`, `429 rate_limited`,
`500 internal`.

There is **no** `clock_skew_too_large`, `ops_unordered`, `empty_update`,
`op_id_mutated`, `stale_op`, `invalid_hlc` — those concepts no longer exist.

### 5.2 `GET /me`

JWT check + a cheap "is there anything new" probe.

```json
{ "user_id": "u_…", "server_now": "2026-05-22T12:00:00.000Z", "seq": 1342 }
```

`seq` is the server's current `MAX(seq)`; a client whose cursor already
equals it can skip the round trip. `server_now` is informational only —
v2 does not depend on synchronized clocks.

### 5.3 Idempotency

Re-sending an unchanged row is a no-op: LWW sees equal `(version,
device_id)` and does not store (so no new `seq`, no echo). Push is therefore
safe to retry wholesale after any network failure.

### 5.4 Rate limit (guard rail)

`POST /sync`: 60 / minute / user. Single-user defence against a runaway
client bug, not adversarial.

## 6. Conflict resolution & tombstones

- **LWW** per §4.2, whole-row, applied on both ends.
- **Delete** = a normal row write whose `deleted` flag is set (the client's
  `deleted_at` column is non-null). The row identity and version persist; a
  peer can materialise the tombstone from `(table, id, version, deleted)`.
  A later write with a higher `(version, device_id)` resurrects it.
- **Tombstone GC** (v2 makes this trivial, unlike v1): a row that is
  `deleted = 1` and whose `seq` is below every device's cursor can be hard
  deleted. Deferred until `sync_rows` row count is a concern; one tombstone
  row is tiny.
- Clients filter `deleted = 1` out of user-facing queries.

## 7. Client responsibilities

### 7.1 Syncable-table columns

Every syncable Drift table already carries the metadata v2 needs, via the
`SyncableTable` mixin:

| Column | Meaning |
|--------|---------|
| `hlc` | The row's `version` token (§4.1). |
| `deleted_at` | Tombstone — non-null ⇒ `deleted`. |
| `owner_user_id`, `updated_by_device`, `updated_at` | Author / audit metadata, carried in the payload. |

Current syncable table inventory is pinned by
`apps/mobile/lib/core/sync/row_applier.dart` and mirrored by
`apps/mobile/test/core/sync/op_test.dart`:

| Row family | Tables |
|------------|--------|
| `fin:` | `accounts`, `assets`, `liabilities`, `fx_rates`, `tags`, `budgets`, `goals`, `devices`, `amortization_entries`, `tag_links`, `categories`, `settings`, `users`, `journal_entries`, `postings`, `prices`, `corporate_actions`, `watchlist_items`, `options_strategy_profile`, `approved_underlyings`, `options_trade_journal` |
| `health:` | `health_metrics` |
| `know:` | `knowledge_notes`, `knowledge_principles`, `knowledge_assumptions`, `knowledge_decisions`, `knowledge_concepts`, `knowledge_experiments`, `knowledge_routines` |
| `exec:` | `execution_projects`, `execution_actions`, `execution_commitments`, `execution_progress_entries` |

Locally-dirty rows are tracked in a lightweight **dirty-pointer log**, the
`op_outbox` table — exactly four columns: `(op_id, table_name, row_id,
created_at)`. The sync engine reads the *set* of dirty `(table_name,
row_id)` pairs out of it and pushes each row's **current state**. Entries
are deleted once the server acknowledges the row.

### 7.2 Local write path

A local mutation, in one Drift transaction:

1. stamp a fresh `hlc`;
2. write the business row (`deleted_at` set if this is a delete);
3. append one pending-change entry for `(table, row_id)`.

The user-facing call returns as soon as the local row is written; the sync
engine drains the pending log in the background (§7.3).

### 7.3 Sync cycle

One cycle drains both directions, looping until neither side has a backlog:

```text
loop:
  1. pointers = pending log → dedupe to the set of dirty (table, row_id)
  2. changes  = for each dirty row (cap 500): read its CURRENT state
  3. resp     = POST /sync { device_id, since = cursor, changes }
  4. apply resp.changes — one transaction, defer_foreign_keys = ON:
        for each remote row: LWW vs local hlc; if remote wins, upsert
  5. clear the pending-log entries for the rows just pushed
  6. cursor = resp.seq
  7. stop when no dirty rows remain AND resp.more == false
```

- **Step 2** reads the row's *current* state, so several local edits to one
  row between syncs collapse into a single push.
- **Step 4** applies the whole page in one transaction. `PRAGMA
  defer_foreign_keys` means cross-row references (posting → journal_entry)
  need not arrive in any order — by commit the page is internally consistent.
- **Step 5** clears only the pending entries it pushed (by `op_id`); a new
  edit queued mid-flight carries a fresh entry and survives to the next
  cycle, so no write is lost.
- A row that repeatedly fails to push just stays in the pending log. It does
  **not** block other rows: changes are independent, the server applies each
  on its own, there is no ordered queue and no head-of-line. (v1 problem #1
  gone.)

### 7.4 Scheduling

| Trigger | Action |
|---------|--------|
| App resumed to foreground | sync immediately |
| Foreground timer | every 30 s |
| Manual "Sync now" | sync immediately |

Backoff on failure: exponential 1 s → 5 min, reset on success.

> A local-write-triggered sync (debounced wake on commit) would roughly
> halve cross-device latency. It is a small follow-up — the v2 cutover
> deliberately stayed off the write path — and is tracked separately.

### 7.5 Cursor

The pull cursor is one integer in `sync_meta` under key `sync.cursor`; the
HLC stamp state lives under `sync.local_hlc`. No per-table appliers.

First sync is `since = 0`; it pulls the **final state** of every row in one
paged drain — no op replay. Promoting a local-only install to synced enqueues
one pending entry per existing row once (the backfill pass).

## 8. Server responsibilities

`POST /sync` handler:

1. Auth; check protocol version; validate body size / count.
2. For each change: read the stored row's `(version, device_id)`; if the
   change wins LWW (§4.2), `INSERT OR REPLACE` it (mints a fresh `seq`).
   Reads happen up front; the winning `INSERT OR REPLACE`s ship as one
   `db.batch()` so the page is applied atomically.
3. Pull: `SELECT … WHERE user_id = ? AND seq > ? AND device_id <> ?
   ORDER BY seq LIMIT 501`; cap by body budget; compute `more`.
4. `seq` = last change's `seq` if `more`, else `SELECT MAX(seq)`.

The server is ~150 lines and schema-agnostic.

## 9. What v2 deletes

Relative to v1:

- **Server:** `op_log`, `sync_state`, all per-table materialised tables,
  `materialise.rs`, `state.rs`, `op.rs`, `sql_table_name` mapping, `hlc.rs`,
  the `/sync/push` + `/sync/pull` split. The whole server sync surface is now
  one table + one `store.rs` + one `routes/sync.rs`.
- **Client:** the whole `op.dart` (`Op`, `OpType`, `validateOpForQueue`),
  `op_applier.dart` and every per-table applier (`account_op_applier.dart`,
  `generic_op_applier.dart`) — replaced by one schema-driven `RowApplier`.
  The `SyncEngine`, API client and storage layer are rewritten. `op_outbox`
  is rebuilt as a four-column dirty-pointer log (DB migration v13 → v14,
  which also drops the dead `sync_errors` table).
- **Protocol:** `fields_diff` shallow-merge, `op_type` semantics, batch
  ordering, per-op idempotency keys, clock-skew rejection, server HLC
  re-stamping, the `/me` clock-calibration role.

Net: the sync layer drops to roughly one third of its size, and v1's three
severity-🔴 bugs (poison-op head-of-line block, clock-skew sync stall,
divergent orphan handling) cannot occur by construction.

> **Implementation note.** The client uses its existing per-row HLC string
> as the opaque `version` token (§4.1) rather than a separate integer
> column — the server is agnostic, so swapping in a plain `i64` later needs
> no protocol change. The conflict stamp lives in each row's `hlc` column;
> there is no separate `sync_dirty` flag — dirtiness is the dirty-pointer
> log (§7.1).

## 10. Phase 2 — realtime push wake-up (optional)

The wire model needs no change to go realtime. A **Durable Object per user**
holds a hibernatable WebSocket to each device. On `POST /sync` accepting any
change, the DO broadcasts `{ "seq": N }` to the other devices, which then
run a sync cycle. Idle devices hold one near-zero-cost WS instead of polling
every 30 s.

A DO can also own `sync_rows` in its built-in SQLite storage, in which case
D1 is not needed for sync at all and the DO is the *entire* sync backend:
storage + `seq` sequencer + fan-out, one class.

Phase 2 is deferred; Phase 1 (this doc, polling + D1) ships first.

## 11. References

- `apps/backend/src/routes/sync.rs` — the single `/sync` handler
- `apps/backend/src/sync/store.rs` — generic row store + LWW
- `apps/backend/migrations/0002_sync_schema.sql` — `sync_rows` schema
- `apps/mobile/lib/core/sync/` — client engine, version stamper, applier
- `docs/sync-protocol.md` — v1 (superseded, history only)
