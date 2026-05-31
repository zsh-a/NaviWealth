# Sync Protocol Spec — NaviWealth (v1)

> Frozen contract between client (Flutter, all platforms) and server
> (Cloudflare Workers + Rust + D1).
>
> MVP target: **eventual consistency via polling**. WebSocket / SSE / E2EE /
> field-level LWW are explicitly out of scope for v1.

Status: **Frozen v1.0** (2026-04-28). Any change after this point requires a
new minor version (`Sync-Protocol-Version` header) and migration notes.

Companion documents:

- [`sync-protocol-tests.md`](./sync-protocol-tests.md) — protocol-level test
  case catalogue used by both client and server suites.

---

## 1. Goals & non-goals

### Goals

- **Local-first.** Client is the source of truth; the app is fully usable
  offline. The server is durable storage + fan-out to other devices.
- **Eventual consistency.** All devices that have pulled past a given HLC
  observe the same materialised state.
- **Deterministic conflict resolution.** Row-level Last-Writer-Wins ordered by
  HLC. Same input + same op order ⇒ same final state on every device.
- **Tombstones, not hard deletes.** Deletes are sync events, not data loss.
- **Cheap on Workers.** Single push / pull must fit inside the 50 ms CPU
  budget on D1.

### Non-goals (v1)

- WebSocket / SSE realtime push. (Polling is enough until we measure latency
  pain.)
- Field-level LWW.
- E2EE / encrypted payload. Server stores plaintext.
- Multi-tenant / per-tenant quotas. Single user, scoped by JWT.
- Schema-level migrations of OpLog payloads — handled by data-model versioning
  separately.

---

## 2. Terminology

| Term | Definition |
|------|------------|
| **HLC** | Hybrid Logical Clock — `(phys_ms, logical, node_id)` tuple, monotonic per node, partially ordered globally. |
| **Op** | A single mutation: `insert` / `update` / `delete` on one row. |
| **OpLog** | Append-only ledger of Ops on both client and server. |
| **device_id** | Stable UUID per install per platform. Generated at first launch, persisted in secure storage. Acts as HLC `node_id`. |
| **op_id** | UUIDv4 assigned at op creation. Globally unique; used for idempotency. |
| **server_hlc** | The HLC the server stamps on an op when accepting it via `/sync/push`. |
| **client_hlc** | The HLC the client stamped when generating the op locally. |
| **tombstone** | Op of type `delete`. The materialised row is kept with `deleted_at` set; no row is physically removed in v1. |
| **cursor** | The HLC of the last op the client successfully applied from the server. The next pull is `since = cursor`. |

---

## 3. Hybrid Logical Clock (HLC)

### 3.1 Format

```text
HLC := <phys_ms : u64> "." <logical : u16> "-" <node_id : uuid>
```

- `phys_ms` — physical Unix time in milliseconds. `u64`, but in practice
  always a Unix-millis value (so first ~50 bits are zero), serialised as
  unsigned decimal.
- `logical` — 16-bit unsigned counter, reset to `0` whenever `phys_ms`
  advances.
- `node_id` — the writer's `device_id` (UUID v4). For server-stamped HLCs,
  `node_id` is the special UUID
  `00000000-0000-0000-0000-000000000000` (the "server node"); this lets
  clients distinguish ops they themselves authored from ops the server
  rewrote (`fx_rates` snapshots, etc.).

Canonical string form (used in JSON, URLs, headers, D1 columns):

```text
1714291200000.0001-1f5b0c3a-4e2d-4d31-9b77-3f7c1f0d2c01
```

The dot separator is **mandatory**, even when `logical == 0`. Always pad
`logical` to 4 hex digits (`%04x`) so the string sorts lexicographically the
same as the numeric tuple — this lets D1 use a TEXT column with an index for
range scans.

### 3.2 Ordering

For two HLCs `a` and `b`:

```text
a < b  iff  (a.phys_ms, a.logical, a.node_id)
                 lex<  (b.phys_ms, b.logical, b.node_id)
```

`node_id` is a deterministic tie-breaker; it does not encode causality, only
prevents equal HLCs.

### 3.3 Local update rule

On every local event the client computes a new HLC:

```text
fn next(local: HLC, now_ms: i64, device_id: Uuid) -> HLC:
    pmax = max(local.phys_ms, now_ms)
    logical = (local.phys_ms == pmax) ? local.logical + 1 : 0
    if logical >= 65_536:
        // Overflow guard: bump phys_ms artificially.
        pmax = pmax + 1
        logical = 0
    return HLC { phys_ms: pmax, logical, node_id: device_id }
```

On receiving an HLC `recv` (e.g. from a server pull), the client merges:

```text
fn merge(local: HLC, recv: HLC, now_ms: i64, device_id: Uuid) -> HLC:
    pmax = max(local.phys_ms, recv.phys_ms, now_ms)
    if pmax == local.phys_ms == recv.phys_ms:
        logical = max(local.logical, recv.logical) + 1
    elif pmax == local.phys_ms:
        logical = local.logical + 1
    elif pmax == recv.phys_ms:
        logical = recv.logical + 1
    else:
        logical = 0
    return HLC { phys_ms: pmax, logical, node_id: device_id }
```

The persisted **local HLC state** is `(phys_ms, logical)`; `node_id` is always
the device's own `device_id` for self-generated events.

### 3.4 Server stamping

The server treats incoming `client_hlc` as a **proposal**. On `/sync/push` it
computes:

```text
server_hlc = next(server_hlc_state, max(client_hlc.phys_ms, server_now_ms))
```

Server-stamped HLCs always have `node_id = SERVER_NODE_ID`. The server-side
HLC state is persisted in D1 (`sync_state` table, single row).

### 3.5 Drift handling

- **Acceptable drift:** ±60 s. Measured via `GET /me` (returns `server_now`).
- If `|client_now - server_now| > 60 s` on bootstrap, the client logs a warning
  and uses `server_now` as the basis for its first HLC after sync. (We do not
  block writes — the server will normalise via `next()` on push.)
- **Future-skewed clocks:** the server caps `phys_ms` at `server_now + 60 s`.
  Pushes whose `client_hlc.phys_ms` exceed that cap are rejected with
  `clock_skew_too_large` (HTTP 409).

---

## 4. OpLog entry

```json
{
  "op_id": "f4b5d2a0-7e21-4f60-bd3c-3a1b2c5e9f01",
  "table": "journal_entries",
  "row_id": "e2c4...",
  "op_type": "update",
  "fields_diff": {
    "narration": "rebate"
  },
  "hlc": "1714291200000.0001-1f5b0c3a-4e2d-4d31-9b77-3f7c1f0d2c01",
  "device_id": "1f5b0c3a-4e2d-4d31-9b77-3f7c1f0d2c01"
}
```

### 4.1 Fields

| Field | Type | Notes |
|-------|------|-------|
| `op_id` | UUIDv4 string | Globally unique. Idempotency key. |
| `table` | enum string | One of: `accounts`, `assets`, `liabilities`, `tags`, `tag_links`, `categories`, `amortization_entries`, `goals`, `devices`, `users`, `settings`, `journal_entries`, `postings`, `prices`, `watchlist_items`, `recurring_transactions`. Other tables (e.g. `fx_rates`, `app_meta`, the local market-data caches and `domain_event_log`) are **not** synced — `fx_rates` is global market data each device pulls independently. The `journal_entries` / `postings` / `prices` triple is the Beancount-style ledger foundation; they sync independently so a posting-level edit ships as a single op rather than a JE-wide rewrite. `watchlist_items` stores user-authored symbol tracking and local alert thresholds. `recurring_transactions` stores future planned-transaction templates only; expanded forecast occurrences are pure derived values and never enter OpLog until materialised as real journal entries. |
| `row_id` | string | Primary key of the row. For composite keys (e.g. `fx_rates`) the canonical form is `<base>:<quote>:<as_of_iso>`. |
| `op_type` | enum | `insert` \| `update` \| `delete`. |
| `fields_diff` | object \| null | See §4.2. |
| `hlc` | HLC string | The op's authoritative HLC. On client-generated ops, this is the `client_hlc` at the time of writing. The server overwrites it with `server_hlc` before persisting and before returning it to other devices. |
| `device_id` | UUID string | Always the **author's** device. Server-rewritten ops keep the original author's `device_id` here, so clients can still suppress echoes. |

### 4.2 `fields_diff` semantics

- **`insert`** — full set of column values for the new row, **including**
  primary key. Server applies this verbatim if the row does not yet exist;
  if it already exists, the insert is treated as an update with the same
  diff (LWW comparison still applies — see §6).
- **`update`** — *partial* column → value map. Only listed columns change.
  An empty diff is invalid (HTTP 400 `empty_update`).
- **`delete`** — `null`. Sets `deleted_at` on the materialised row.

JSON encoding rules for column values:

| Column type | JSON form |
|-------------|-----------|
| `text` | string |
| `int` / `bool` | number (`0`/`1` for bool — matches Drift convention) |
| `real` | number |
| `datetime` | RFC3339 string (`2026-04-28T12:00:00.000Z`); always UTC, always with millisecond precision |
| nullable | JSON `null` for "unset", **omit the key** to mean "not in this diff" |

> **Important:** `null` and "absent" are distinct. `{"institution": null}`
> means "set institution to NULL". `{}` means "no field changes" — which is
> only legal on inserts of zero non-key columns and otherwise rejected.

### 4.3 Tombstones & resurrection

- `delete` does not remove the materialised row; it only sets `deleted_at`.
- A subsequent `update` or `insert` with a higher HLC clears `deleted_at`
  (resurrection). This means a row identity persists across deletes — clients
  must treat `row_id` as forever, not "free to recycle".
- Garbage collection of tombstones is **deferred** (tracked separately).
  Clients should filter `deleted_at IS NOT NULL` in user-facing queries.

### 4.4 OpLog size budget

- `op_id` (36) + `table` (≤16) + `row_id` (UUID, 36) + `op_type` (≤6) +
  `hlc` (≤80) + `device_id` (36) = ~210 B fixed overhead per op.
- `fields_diff` capped at **64 KB serialised** (server rejects with
  `payload_too_large`).
- A push batch of 500 ops × ~2 KB average ≈ 1 MB ceiling (see §5.2).

---

## 5. HTTP API

All endpoints:

- `Content-Type: application/json; charset=utf-8`
- `Authorization: Bearer <jwt>` required (returns 401 otherwise)
- `Sync-Protocol-Version: 1` request header — server returns 426 `Upgrade
  Required` on mismatch
- All timestamps ISO-8601 UTC, all HLCs in canonical string form (§3.1)
- All errors follow the `{ "code": "...", "message": "..." }` shape from
  `apps/backend/src/error.rs`

### 5.1 `GET /me`

Used at app start and at every reconnect to (a) check JWT validity, (b)
calibrate HLC physical time.

**Response 200**

```json
{
  "user_id": "u_2YxQ...",
  "server_now": "2026-04-28T12:34:56.789Z",
  "server_hlc": "1714303596789.0000-00000000-0000-0000-0000-000000000000"
}
```

**Errors**: `401 unauthorized`.

### 5.2 `POST /sync/push`

Upload a batch of client-generated ops.

**Request body**

```json
{
  "device_id": "1f5b0c3a-4e2d-4d31-9b77-3f7c1f0d2c01",
  "ops": [ /* OpLog entries, ordered by client_hlc ascending */ ]
}
```

**Constraints**

- `len(ops) ≤ 500`
- Serialised body ≤ 1 MB. The server returns `413 payload_too_large` on
  larger batches; the client must split.
- Ops must be ordered by `client_hlc` ascending. Out-of-order batches are
  rejected with `400 ops_unordered` (cheaper to detect than to sort on
  Workers).
- `device_id` in body must match the `device_id` field on every contained op.
  Mismatch → `400 device_mismatch`.

**Response 200**

```json
{
  "accepted": 487,
  "rejected": [
    {
      "op_id": "f4b5...",
      "code": "stale_op",
      "message": "newer hlc already applied"
    }
  ],
  "server_hlc_high": "1714303596800.0001-00000000-0000-0000-0000-000000000000",
  "server_now": "2026-04-28T12:34:56.789Z"
}
```

- `accepted` — number of ops accepted (durably persisted). The server has
  already applied LWW; some accepted ops may have been **shadowed** by
  pre-existing newer ops on the row, but this is not a rejection — they're
  still recorded in OpLog for fan-out and durability.
- `rejected` — only ops that were structurally invalid (see §5.4 error
  codes). `409` per-op rejections never bring down the whole batch unless
  every op is invalid (then HTTP 409).
- `server_hlc_high` — highest HLC the server stamped in this batch. The
  client uses this to advance its HLC state via `merge()`.
- `server_now` — current server clock; opportunistic drift correction.

**Errors**

- `401 unauthorized`
- `400 ops_unordered` / `400 empty_update` / `400 device_mismatch`
- `409 clock_skew_too_large`
- `413 payload_too_large`
- `429 rate_limited` (Retry-After in seconds)

**Idempotency**: re-pushing the same `op_id` with the same `client_hlc` is a
no-op (returns `accepted` count incremented as if first time). Re-pushing
the same `op_id` with a **different** `client_hlc` returns
`400 op_id_mutated`.

### 5.3 `GET /sync/pull?since=<hlc>&limit=500&device_id=<uuid>`

Fetch ops newer than `since`.

**Query**

| Param | Required | Notes |
|-------|----------|-------|
| `since` | yes | HLC string. Returns ops with `server_hlc > since`, strict greater-than. Use empty / zero (`0.0000-…0`) for first sync. |
| `limit` | no | 1–500, default 500. Server may return fewer (e.g. on body-size cap). |
| `device_id` | yes | The caller's `device_id`. The server **filters out** ops whose `device_id == this` to prevent echo loops. |

**Response 200**

```json
{
  "ops": [ /* OpLog entries, ordered by server_hlc ascending */ ],
  "server_hlc_high": "1714303596800.0017-00000000-...",
  "has_more": true,
  "server_now": "2026-04-28T12:34:56.789Z"
}
```

- `ops` — at most `limit` ops; HLC strictly increasing.
- `has_more` — `true` ⇔ a follow-up pull at `since = last op's hlc` would
  return more. Clients loop until `has_more == false` to drain.
- `server_hlc_high` — highest HLC observed on the server (not necessarily in
  this page). Used by the client to set its **horizon cursor** even when the
  current page is empty.
- The `hlc` of every returned op is the **server_hlc** stamped at push time.

**Errors**: `400 invalid_hlc`, `401 unauthorized`, `429 rate_limited`.

### 5.4 Error codes

| Code | HTTP | Meaning | Client action |
|------|------|---------|---------------|
| `unauthorized` | 401 | JWT missing/invalid/expired | Re-authenticate, retry |
| `bad_request` | 400 | Malformed JSON | Surface as bug |
| `ops_unordered` | 400 | Push batch not in HLC order | Sort, retry |
| `empty_update` | 400 | `update` with `{}` diff | Drop op (bug) |
| `device_mismatch` | 400 | Op `device_id` ≠ batch `device_id` | Drop batch (bug) |
| `op_id_mutated` | 400 | Same `op_id` re-pushed with different `client_hlc` | Drop op (bug) |
| `invalid_hlc` | 400 | Pull `since` not parseable | Reset cursor |
| `payload_too_large` | 413 | Push body > 1 MB | Split batch |
| `clock_skew_too_large` | 409 | `phys_ms` > `server_now + 60 s` | Trigger `/me` calibration, retry |
| `stale_op` | 409 (per-op) | Server already has newer HLC for the row | Mark op as shadowed; do not retry |
| `rate_limited` | 429 | Per-user cap exceeded | Honour `Retry-After` |
| `internal` | 500 | Worker bug | Exponential backoff |

### 5.5 Server-side rate limit (initial)

- Push: 30 batches / minute / user.
- Pull: 60 calls / minute / user.

These are guard rails against runaway client bugs ("防自己代码 bug 把额度跑光"),
not adversarial defence.

---

## 6. Conflict resolution

### 6.1 Rule

For each `(table, row_id)`, the materialised row reflects the op with the
**highest HLC** that the device has applied. Lower-HLC ops still exist in
OpLog (they shaped the historical ledger) but do not affect current state.

```text
fn apply(local_row: Option<Row>, op: Op) -> Option<Row>:
    if local_row.is_none():
        return Some(materialise(op))
    if op.hlc > local_row.last_hlc:
        return Some(merge(local_row, op))     // overwrite per op_type
    else:
        return local_row                      // shadowed; no change
```

### 6.2 Why row-level (not field-level) for v1

- Most edits in NaviWealth are coarse-grained (creating an account, recording
  a transaction). Two devices independently editing **different fields of
  the same row** is rare for a single-user app.
- Field-level LWW requires per-field HLC storage on every row → ~doubled
  schema. Deferred (explicitly out of scope).

### 6.3 Special cases

- **insert vs insert** on same `row_id`: higher HLC wins; lower HLC is
  shadowed. Functionally equivalent to update.
- **delete vs update**: higher HLC wins. A late update with higher HLC
  resurrects the row (`deleted_at = null`).
- **insert with diff missing required column**: server rejects with
  `400 bad_request` and `field_missing` detail; client drops the op (bug).

### 6.4 Materialisation atomicity

On both client and server, applying an op must be atomic w.r.t. (a) writing
the OpLog row and (b) updating the materialised business row. On D1 use a
single `BEGIN ... COMMIT`; on Drift/SQLCipher use `transaction()`.

---

## 7. Client flow

### 7.1 Local write path

```text
user action
    │
    ▼
domain layer creates Op {
    op_id  = uuid_v4(),
    hlc    = HLC.next(),
    device_id = self.device_id
}
    │
    ▼
single Drift transaction:
    INSERT into materialised table  (LWW vs current row)
    INSERT into op_log
    │
    ▼
notify SyncEngine: "wake up, push backlog"
```

The user-facing UI never blocks on the network — the local row is already
written by the time the function returns.

### 7.2 SyncEngine state machine

```text
                  ┌────────────────────┐
                  │       Idle         │
                  └────┬───────────┬───┘
        local write   │           │   timer 30s / fg-resume / bg-tick
                      ▼           ▼
              ┌──────────┐   ┌──────────┐
              │  Pushing │   │  Pulling │
              └─────┬────┘   └────┬─────┘
                    │             │
       network ok   │             │   network ok
                    ▼             ▼
              ┌──────────────────────┐
              │  ApplyingRemote      │
              │  (replay into Drift) │
              └─────────┬────────────┘
                        │
                        ▼
                  ┌──────────┐
                  │   Idle   │
                  └────┬─────┘
                       │ network err / 429 / 5xx
                       ▼
                  ┌──────────┐
                  │ Backoff  │  exp backoff: 1s, 2s, 4s, … cap 5min
                  └────┬─────┘
                       │ ready
                       ▼
                     Idle
```

Invariants:

- Only one active state at a time per device.
- Push and Pull are **never** concurrent on the same device — they share a
  mutex. (A serial loop is simpler than reasoning about interleaved HLC
  cursors.)
- Backoff cap is 5 minutes; reset on any successful push or pull.

### 7.3 Polling cadence

| Trigger | Action |
|---------|--------|
| App resumed to foreground | Push backlog → Pull (immediate) |
| App backgrounded | Stop foreground timer |
| Foreground timer | Every **30 s**: Push if dirty → Pull |
| Mobile background tick (`BackgroundTasks` / `WorkManager`) | At OS-allowed cadence (typically ≥ 15 min): Push if dirty → Pull |
| Web background (`Periodic Background Sync` if available) | Same as mobile. Falls back to foreground-only if API absent. |
| Manual "Sync now" in Settings | Push if dirty → Pull |

The server is single-user, so we can be aggressive: 30 s × 1 user × 60 min ×
24 h = ~3 K calls/day, well inside the 100 K/day Workers free tier even with
multiple devices.

### 7.4 Cursor management

- The client persists `last_pulled_hlc` per user, **not per device**. (All of
  the user's devices share the same server view.)
- After each pull page, advance `last_pulled_hlc = max(server_hlc_high, last
  op.hlc)`.
- Persist in `app_meta` as key `sync.cursor`.

### 7.5 Push backlog

- Drift table `op_outbox` holds locally-generated ops not yet acknowledged
  by the server. Schema mirrors §4 plus a `created_at` for FIFO order.
- On push success: delete from `op_outbox` for every `op_id` in `accepted`.
  Ops listed in `rejected` with non-recoverable codes are also removed
  (they're recorded in `sync_errors` for diagnostics).
- Outbox is **append-only between syncs**; the SyncEngine does not edit ops
  to "amend" them. If the user re-edits a row before push, that's a new op
  with a new `op_id` and higher HLC — both go to the server, the latter wins.

---

## 8. Server flow

### 8.1 Push handling

```text
1. Authenticate (JWT → user_id).
2. Validate batch (size, ordering, device match).
3. Calibrate clock skew.
4. For each op (in order):
   a. SELECT current row + last_hlc for (user_id, table, row_id).
   b. server_hlc = next(server_state, max(client_hlc.phys_ms, server_now)).
   c. INSERT into op_log (with server_hlc).
   d. If server_hlc > current row's last_hlc:
        UPSERT materialised row.
        UPDATE row.last_hlc = server_hlc.
      else:
        // shadowed; OpLog still records, materialised row unchanged.
   e. Append op to response (accepted).
5. Persist server_state once at end of batch.
6. Return summary with server_hlc_high.
```

Step 4 uses prepared statements; the entire batch runs inside a single D1
transaction.

### 8.2 Pull handling

```text
1. Authenticate (JWT → user_id).
2. Parse since-HLC.
3. SELECT op_id, table, row_id, op_type, fields_diff, hlc, device_id
   FROM op_log
   WHERE user_id = ?
     AND device_id <> ?           -- caller's device_id
     AND hlc_text > ?             -- since
   ORDER BY hlc_text ASC
   LIMIT ?;
4. has_more = (rows returned == limit) AND (more rows exist past last hlc).
5. Return rows + server_hlc_high (independent SELECT MAX(hlc_text)).
```

The `hlc_text` column is TEXT with the canonical (lex-sortable) form from
§3.1, indexed `(user_id, hlc_text)`. The body-size cap (~900 KB) is enforced
by the handler — if accumulating ops would exceed it, stop early and set
`has_more = true`.

### 8.3 D1 sync tables (sketch)

```sql
CREATE TABLE op_log (
  op_id        TEXT PRIMARY KEY,
  user_id      TEXT NOT NULL,
  table_name   TEXT NOT NULL,
  row_id       TEXT NOT NULL,
  op_type      TEXT NOT NULL CHECK (op_type IN ('insert','update','delete')),
  fields_diff  TEXT,                -- JSON, NULL for delete
  hlc_text     TEXT NOT NULL,       -- server_hlc canonical form
  client_hlc   TEXT NOT NULL,       -- as supplied by author
  device_id    TEXT NOT NULL,
  created_at   TEXT NOT NULL        -- server insertion time
);
CREATE INDEX op_log_pull   ON op_log (user_id, hlc_text);
CREATE INDEX op_log_row    ON op_log (user_id, table_name, row_id, hlc_text);

CREATE TABLE sync_state (
  user_id        TEXT PRIMARY KEY,
  server_phys_ms INTEGER NOT NULL,
  server_logical INTEGER NOT NULL
);
```

Materialised business tables (`accounts`, `assets`, `journal_entries`,
`postings`, `prices`, …) carry `hlc_text TEXT NOT NULL`, `device_id TEXT`,
`deleted_at TEXT NULL` columns.

---

## 9. Sequence diagrams

### 9.1 Local write (offline) → push when online

```text
User             Drift (local)         SyncEngine          Server (D1)
 │   tap "save"      │                     │                     │
 │──────────────────►│                     │                     │
 │                   │ tx: write row       │                     │
 │                   │     write op_log    │                     │
 │   ack (UI updated)│                     │                     │
 │◄──────────────────│                     │                     │
 │                   │ notify              │                     │
 │                   │────────────────────►│                     │
 │                   │                     │ (offline; backoff)  │
 │                   │                     │ ...                 │
 │                   │                     │  network up         │
 │                   │                     │                     │
 │                   │                     │ POST /sync/push     │
 │                   │                     │────────────────────►│
 │                   │                     │                     │ server_hlc
 │                   │                     │                     │ assigned
 │                   │                     │                     │ row upsert
 │                   │                     │   200 {accepted,…}  │
 │                   │                     │◄────────────────────│
 │                   │ delete from outbox  │                     │
 │                   │◄────────────────────│                     │
```

### 9.2 Pull (other device's edits)

```text
SyncEngine                Server                 Drift
   │                        │                      │
   │ GET /sync/pull?since=X │                      │
   │───────────────────────►│                      │
   │                        │ SELECT op_log …      │
   │   200 {ops, has_more}  │                      │
   │◄───────────────────────│                      │
   │                        │                      │
   │ apply each op (LWW)    │                      │
   │ in single tx           │                      │
   │──────────────────────────────────────────────►│
   │                                              tx │
   │ advance cursor                                │
   │ (loop while has_more)                         │
```

### 9.3 Concurrent write on two devices, same row

```text
Device A (HLC=h_a)                         Device B (HLC=h_b)
 │   set name = "Foo"                       │   set name = "Bar"
 │   write row, write op_log                │   write row, write op_log
 │                                          │
 │   push                                   │   push (later)
 │──────────────────► server                │
 │                       upsert row         │
 │                       row.last_hlc=h_a   │
 │                                          │──────────────────► server
 │                                          │                       compare h_b vs h_a
 │                                          │                       h_b > h_a ⇒ overwrite name="Bar"
 │                                          │                       row.last_hlc=h_b
 │                                          │
 │   pull                                   │   (no-op pull)
 │◄────── server (op with h_b)              │
 │   apply: h_b > local h_a ⇒ name="Bar"    │
```

If `h_a > h_b` (B's local clock was behind), the order at the server is the
same — server compares HLCs, not arrival order. Result: `name="Foo"` on both
devices.

### 9.4 Delete then resurrect

```text
Device A: delete row (hlc=h_d)
Device B (offline): update row.note (hlc=h_u, with h_u > h_d)

A pushes h_d → server: row.deleted_at = ts(h_d), last_hlc = h_d
B comes online, pushes h_u → server:
    h_u > h_d ⇒ apply update; deleted_at = NULL (resurrection); last_hlc = h_u

Both devices, after pulling, see the row alive with B's new note.
```

---

## 10. Versioning & forward compatibility

- Wire version: `Sync-Protocol-Version: 1`. Server returns 426 on mismatch
  with body `{"code":"protocol_version","supported":[1]}`.
- Adding a new optional field to OpLog or response payloads is **additive**
  and does not bump the version. Removing or changing the meaning of a field
  does. Clients must ignore unknown fields.
- The `tables` enum (§4.1) is closed. Adding a new syncable table is a
  data-model change (separate ticket); add it to the enum and to the
  materialiser, no protocol bump needed.

### 10.1 Additive sync table SOP

For a new syncable table under v1:

1. Add the wire table name to §4.1.
2. Add the local Drift table with the standard sync metadata columns.
3. Register the table in the client OpApplier registry, using the generic LWW
   applier unless the table needs typed validation.
4. Add a D1 migration with the standard materialised-row shape:
   `(user_id, id, payload, hlc_text, updated_by_device, deleted_at)`.
5. Register the wire-to-D1 table mapping in the backend materialiser.
6. Add/extend backfill coverage so pre-existing local rows enqueue insert ops.
7. Document rollback: remove the feature writer first, then tombstone or ignore
   the materialised rows; keep OpLog rows durable for cursor consistency.

`recurring_transactions` originally followed this v1 SOP in mobile schema v9;
the dedicated backend migration was removed by the sync v2 clean rebuild.

---

## 11. Open / deferred items

These are explicitly **not** v1; tracked here so the spec stays complete.

| # | Item | Trigger to revisit |
|---|------|---------------------|
| D1 | Realtime push (WS / SSE / Durable Objects) | Multi-device latency complaints in user testing |
| D2 | Field-level LWW | Observed lost-update incidents on shared rows |
| D3 | E2EE payload | Sharing the app with anyone other than the author |
| D4 | Tombstone GC | OpLog growth > 100 MB / device |
| D5 | Compaction / snapshot pulls | First-sync time on new device > 30 s |
| D6 | Multi-tenant scoping | Ever shipping outside single-user mode |

---

## 12. References

- `apps/mobile/lib/data/db/tables.dart` — local schema baseline
- `apps/backend/src/error.rs` — error envelope shape
- Core entity definitions
- JWT auth (request preconditions for every endpoint here)
- Workers + Rust skeleton (host for these handlers)
- Client SyncEngine implementation (consumer of this spec)
- D1 schema migration & API implementation (server side)
