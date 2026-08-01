# Sync v3 Protocol — Test Case Catalogue

Status: executable-coverage companion, not a protocol SSOT.

## Document Contract

Owns stable scenario identifiers and expected test coverage. It does not own
wire semantics; [Sync v3](sync-v3.md) and serializer fixtures do. Checked-in
client/backend tests are authoritative for which cases are executable.

Companion to [`sync-v3.md`](./sync-v3.md). These are protocol-level
scenarios that the Flutter client and Cloudflare Worker backend should cover
for the active row-state sync protocol.

Each case lists **setup -> action -> expected outcome**. Test names follow
`SP-<group>-<n>` for cross-referencing in test comments.

---

## A. HLC mechanics

The client uses canonical HLC strings as the row-state `version` token. Existing
HLC unit-test IDs remain stable.

### SP-A-1 — `next` advances logical when phys equal

- **Setup**: `local = (1000, 5)`, `now_ms = 1000`.
- **Action**: `next(local, now_ms, dev)`.
- **Expect**: `(1000, 6, dev)`.

### SP-A-2 — `next` resets logical when phys advances

- **Setup**: `local = (1000, 99)`, `now_ms = 1500`.
- **Action**: `next(local, now_ms, dev)`.
- **Expect**: `(1500, 0, dev)`.

### SP-A-3 — `next` keeps `pmax` when local > now

- **Setup**: `local = (2000, 0)`, `now_ms = 1500`.
- **Action**: `next(local, now_ms, dev)`.
- **Expect**: `(2000, 1, dev)`.

### SP-A-4 — `merge` takes max of three sources

- **Setup**: `local = (1000, 3)`, `recv = (1500, 7)`, `now = 1200`.
- **Action**: `merge(local, recv, now, dev)`.
- **Expect**: `(1500, 8, dev)`.

### SP-A-5 — Logical overflow bumps phys

- **Setup**: `local = (1000, 65535)`, `now_ms = 1000`.
- **Action**: `next(local, now_ms, dev)`.
- **Expect**: `(1001, 0, dev)`.

### SP-A-6 — Canonical string round-trip

- **Setup**: `hlc = (1714291200000, 1, "1f5b...c01")`.
- **Action**: serialize, parse.
- **Expect**: input equals output bit-for-bit.

### SP-A-7 — Lex order matches tuple order

- **Action**: for random HLC pairs `(a, b)`, compare canonical strings and
  tuple order.
- **Expect**: `cmp(a.toString(), b.toString()) == cmp_tuple(a, b)`.

---

## B. Row-state wire model

### SP-B-1 — Local write enqueues a dirty pointer

- **Setup**: a repository creates a syncable row in one Drift transaction.
- **Action**: the mutation stamps `hlc`, writes the business row, and calls
  `OutboxStore.enqueue(table, rowId)`.
- **Expect**: the row is visible locally immediately and `op_outbox` contains
  one dirty pointer for `(table, rowId)`.

### SP-B-2 — Multiple edits to one row collapse to current state

- **Setup**: the same row is edited three times while offline, producing
  three dirty pointers.
- **Action**: `SyncEngine` collects a batch.
- **Expect**: it sends one `RowChange` for that `(table, id)` with the latest
  row payload and latest `hlc`, while retaining all pointer IDs for ack
  clearing.

### SP-B-3 — Outgoing table names carry LifeOS prefixes

- **Setup**: dirty rows exist in Finance, Health, Knowledge, and Execution tables.
- **Action**: the client builds `RowChange.table`.
- **Expect**: wire tables use `fin:`, `health:`, `know:`, or `exec:` prefixes at
  the sync boundary; unprefixed business table names are not sent.

### SP-B-4 — Outgoing row sends full current payload

- **Setup**: a dirty row has many non-null columns plus sync metadata.
- **Action**: the client serializes the row.
- **Expect**: `payload` is the full JSON-safe row map, `version` equals the
  row `hlc`, and `deleted` reflects whether `deleted_at` is non-null.

### SP-B-5 — Tombstone is sent as a deleted row

- **Setup**: a local delete marks `deleted_at` and stamps a higher `hlc`.
- **Action**: the client serializes the row.
- **Expect**: `deleted == true`, `version` is the tombstone `hlc`, and the
  row identity remains `(table, id)` so peers can materialize the tombstone.

### SP-B-6 — Missing dirty row clears stale pointer only

- **Setup**: `op_outbox` points at a row that no longer exists locally.
- **Action**: `SyncEngine` collects a batch.
- **Expect**: no `RowChange` is sent for that pointer and the stale pointer
  can be cleared after the cycle.

### SP-B-7 — Request batch caps at 500 changes

- **Setup**: more than 500 distinct dirty rows are queued.
- **Action**: `SyncEngine` collects a batch.
- **Expect**: at most 500 `changes` are sent and the cycle loops after the
  response because more dirty rows remain.

---

## C. `POST /sync` API

### SP-C-1 — Empty first sync succeeds

- **Setup**: a new device has cursor `0` and no dirty rows.
- **Action**: `POST /sync { device_id, since: 0, changes: [] }`.
- **Expect**: `200`, `changes` contains peer rows newer than `0`, `more`
  reflects pagination, and `seq` is the cursor the client should adopt.

### SP-C-2 — Push and pull happen in one request

- **Setup**: D1 has dirty rows and D2 has already stored newer peer rows.
- **Action**: D1 sends one `POST /sync` with `changes` and `since`.
- **Expect**: the server applies D1's winning changes first, then returns
  D2 rows with `seq > since` and `device_id != D1`.

### SP-C-3 — Response includes accepted push rows

- **Setup**: the request includes three domain-authorized changes.
- **Action**: the server handles the request.
- **Expect**: response `accepted` includes each accepted `(table, id)` even
  if LWW decides an already stored server row still wins.

### SP-C-4 — Client clears only accepted pointers

- **Setup**: request includes one accepted Finance row and one row rejected by
  domain authorization.
- **Action**: the client processes the response.
- **Expect**: only dirty pointers whose wire keys appear in `accepted` are
  cleared; unauthorized rows remain dirty.

### SP-C-5 — Device mismatch rejected

- **Setup**: JWT binds the caller to D1 but body has `device_id = D2`.
- **Action**: `POST /sync`.
- **Expect**: `400 device_mismatch`; no rows are stored.

### SP-C-6 — Wrong protocol version rejected

- **Setup**: request header `Sync-Protocol-Version: 999`.
- **Action**: `POST /sync`.
- **Expect**: `426 protocol_version`; client surfaces update-required UX.

### SP-C-7 — Body and row size limits enforced

- **Setup**: request body exceeds 1 MB, `changes.length > 500`, or a single
  row payload exceeds 64 KB.
- **Action**: `POST /sync`.
- **Expect**: `413 payload_too_large`; client keeps dirty pointers for retry
  after splitting or user intervention.

### SP-C-8 — Malformed JSON rejected

- **Setup**: body is not valid JSON or misses required wire fields.
- **Action**: `POST /sync`.
- **Expect**: `400 bad_request`; no rows are stored.

### SP-C-9 — Missing JWT rejected

- **Setup**: no `Authorization` header.
- **Action**: `POST /sync`.
- **Expect**: `401 unauthorized`.

---

## D. Server row store and pull cursor

### SP-D-1 — First write stores a row and mints seq

- **Setup**: no stored row for `(user, table, id)`.
- **Action**: apply an incoming change.
- **Expect**: the row is inserted with payload, version, device_id, deleted
  flag, and a positive `seq`.

### SP-D-2 — Winning update mints a higher seq

- **Setup**: server has row version `v1`.
- **Action**: incoming version `v2 > v1` is applied.
- **Expect**: stored payload/version are replaced and `seq` increases, making
  the row visible to peers whose cursor was the old `seq`.

### SP-D-3 — Losing update is idempotent

- **Setup**: server has row `(version = v2, device_id = D2)`.
- **Action**: incoming `(version = v1, device_id = D1)` where `(v1, D1)` loses
  under LWW.
- **Expect**: no stored fields change and no new `seq` is minted.

### SP-D-4 — Equal version and equal device is a no-op

- **Setup**: server has a row written by D1 at version `v1`.
- **Action**: D1 retries the same row at version `v1`.
- **Expect**: no new `seq` is minted; retry is safe.

### SP-D-5 — Pull filters caller echo

- **Setup**: server has rows from D1 and D2 with `seq > since`.
- **Action**: D1 syncs with that `since`.
- **Expect**: response `changes` includes only rows whose `device_id != D1`.

### SP-D-6 — Pull returns rows ordered by seq

- **Setup**: server has several peer rows newer than cursor.
- **Action**: pull phase runs.
- **Expect**: rows are ordered by ascending `seq`.

### SP-D-7 — Cursor fast-forwards past echo-filtered own rows

- **Setup**: all rows newer than `since` were authored by the caller.
- **Action**: caller syncs.
- **Expect**: `changes == []`, `more == false`, and `seq` equals the user's
  global `MAX(seq)` so the caller does not pull its own rows later.

### SP-D-8 — Pagination uses last returned seq when more is true

- **Setup**: peer backlog exceeds one page.
- **Action**: server returns a capped page.
- **Expect**: `more == true` and response `seq` equals the last returned
  row's `seq`; the next request with that `since` continues draining.

### SP-D-9 — Pull body budget can shorten a page

- **Setup**: peer rows are individually valid but the serialized response
  would exceed the pull body budget.
- **Action**: pull phase accumulates rows.
- **Expect**: it stops before exceeding the budget, sets `more == true`, and
  returns a cursor safe for the next page.

---

## E. Conflict resolution and tombstones

### SP-E-1 — Higher version wins

- **Setup**: D1 writes row at `v1`; D2 writes same row at `v2 > v1`.
- **Action**: both changes reach the server in any order.
- **Expect**: server and all clients converge to D2's row.

### SP-E-2 — Lower version loses even if it arrives later

- **Setup**: server stores row at `v2`; a late offline update at `v1 < v2`
  arrives.
- **Action**: apply incoming change.
- **Expect**: stored row remains at `v2`.

### SP-E-3 — Equal version tie breaks by device_id

- **Setup**: two devices produce the same version token for the same row.
- **Action**: both changes reach the server.
- **Expect**: lexicographically greater `device_id` wins; all clients apply
  the same rule locally.

### SP-E-4 — Delete wins over older live row

- **Setup**: server has live row at `v1`; D2 deletes at `v2 > v1`.
- **Action**: D2 syncs, peers pull.
- **Expect**: peers materialize `deleted_at != null` and user-facing queries
  hide the row.

### SP-E-5 — Later live write resurrects tombstone

- **Setup**: server has a tombstone at `v2`.
- **Action**: D1 writes a live row at `v3 > v2`.
- **Expect**: server and peers clear the tombstone and show the live row.

### SP-E-6 — Older live write cannot resurrect tombstone

- **Setup**: server has a tombstone at `v2`.
- **Action**: an offline live row at `v1 < v2` arrives.
- **Expect**: tombstone remains the winning row.

### SP-E-7 — Client apply skips remote rows when local wins

- **Setup**: local row has version `v2`; pulled row has version `v1 < v2`.
- **Action**: `RowApplier` applies the page.
- **Expect**: local row is unchanged and conflict diagnostics record a local
  win / skipped row.

---

## F. Client sync cycle

### SP-F-1 — Successful cycle drains push and pull

- **Setup**: dirty rows exist and server has peer rows.
- **Action**: `SyncEngine.run()`.
- **Expect**: accepted dirty pointers clear, peer rows apply in one
  transaction, cursor is persisted, status becomes online, and backoff resets.

### SP-F-2 — Loop continues while dirty backlog remains

- **Setup**: more than one push batch is needed.
- **Action**: `SyncEngine.run()`.
- **Expect**: engine keeps calling `/sync` until no dirty rows remain and the
  server response has `more == false`.

### SP-F-3 — Loop continues while pull backlog remains

- **Setup**: no local dirty rows, but server returns `more == true`.
- **Action**: `SyncEngine.run()`.
- **Expect**: engine immediately syncs again with the response cursor.

### SP-F-4 — Concurrent runs share one in-flight future

- **Setup**: two callers invoke `run()` while the first cycle is in progress.
- **Action**: both futures complete.
- **Expect**: only one cycle executes and both callers receive the same
  result.

### SP-F-5 — Failed request keeps dirty pointers

- **Setup**: dirty rows exist and `/sync` returns a retryable error.
- **Action**: `SyncEngine.run()`.
- **Expect**: no accepted keys are processed, dirty pointers remain queued,
  and engine enters backoff.

### SP-F-6 — Remote rows merge local HLC

- **Setup**: pulled rows include a high remote version.
- **Action**: apply succeeds.
- **Expect**: local HLC state merges the highest remote version so the next
  local write of that row can produce a newer token.

---

## G. Domain authorization and row-family namespace

### SP-G-1 — Finance claim accepts `fin:` rows

- **Setup**: JWT `domains = ["finance"]`.
- **Action**: caller pushes `fin:accounts`.
- **Expect**: row is accepted at the sync boundary.

### SP-G-2 — Missing domain claim drops optional-domain push rows

- **Setup**: JWT `domains = ["finance"]`.
- **Action**: caller pushes `health:health_metrics` or `know:knowledge_notes`.
- **Expect**: those rows are omitted from `accepted`, not stored, and the
  client keeps their dirty pointers.

### SP-G-3 — Optional-domain claim accepts matching rows

- **Setup**: JWT includes `health` or `knowledge`.
- **Action**: caller pushes matching `health:` or `know:` rows.
- **Expect**: rows are accepted and participate in LWW.

### SP-G-4 — Unprefixed rows are rejected

- **Setup**: caller pushes `accounts` instead of `fin:accounts`.
- **Action**: server filters by recognized prefixes.
- **Expect**: row is not accepted or stored.

### SP-G-5 — Pull filters revoked domains

- **Setup**: server has `health:` rows but caller's refreshed token no longer
  includes `health`.
- **Action**: caller syncs.
- **Expect**: pull response omits those rows.

---

## H. Bootstrap and resync

### SP-H-1 — Fresh device drains final row state

- **Setup**: new device has cursor `0`; server has rows across multiple
  pages.
- **Action**: sync runs until complete.
- **Expect**: local DB contains final row state, not historical edits, and
  cursor equals the server horizon.

### SP-H-2 — Cursor reset forces full pull without duplicates

- **Setup**: existing device clears `sync.cursor`.
- **Action**: sync starts with `since = 0`.
- **Expect**: rows are re-applied idempotently under LWW and local state
  converges without duplicate business rows.

### SP-H-3 — Local-only promotion enqueues existing rows once

- **Setup**: user signs in after using the app local-only.
- **Action**: promotion/backfill scans syncable tables.
- **Expect**: one dirty pointer per existing syncable row is queued, and the
  first sync uploads current state.

### SP-H-4 — Cursor ahead of server is harmless

- **Setup**: corrupted client cursor is greater than server `MAX(seq)`.
- **Action**: sync runs.
- **Expect**: server returns no changes, `more == false`, and the client can
  continue from the returned cursor.

---

## I. Errors, retry, and scheduling

### SP-I-1 — Expired JWT refreshes before retry

- **Setup**: `/sync` returns `401 unauthorized` and auth can refresh.
- **Action**: client retries through the auth layer.
- **Expect**: retry uses a fresh token; if refresh fails, sync surfaces auth
  failure and does not drop dirty pointers.

### SP-I-2 — Fatal protocol errors halt

- **Setup**: server returns `426 protocol_version` or a non-retryable 400.
- **Action**: `SyncEngine.run()` handles the error.
- **Expect**: engine state becomes halted/failed, not backoff.

### SP-I-3 — Payload-too-large does not lose local edits

- **Setup**: server returns `413 payload_too_large`.
- **Action**: `SyncEngine.run()` handles the error.
- **Expect**: dirty pointers remain queued and UI/diagnostics can surface the
  oversized row.

### SP-I-4 — `429` honors `Retry-After`

- **Setup**: server returns `429` with `Retry-After: 10`.
- **Action**: `SyncEngine.run()` computes retry delay.
- **Expect**: next backoff is at least 10 seconds.

### SP-I-5 — Backoff resets after success

- **Setup**: engine has consecutive retryable failures.
- **Action**: a later cycle succeeds.
- **Expect**: consecutive failure count and next backoff clear.

### SP-I-6 — `5xx` exponential backoff

- **Setup**: server returns `500` three times in a row.
- **Action**: `SyncEngine.run()` handles each failure.
- **Expect**: client backs off according to the configured exponential policy,
  capped by the policy maximum, and resets on success.

---

## J. Diagnostics and observability

### SP-J-1 — Apply report records local wins

- **Setup**: pull page contains rows that lose to local versions.
- **Action**: `RowApplier.applyWithReport`.
- **Expect**: report increments attempted rows and skipped-local-win rows.

### SP-J-2 — Apply report records ignored rows

- **Setup**: pull page contains an unknown or locally unsupported table.
- **Action**: `RowApplier.applyWithReport`.
- **Expect**: row is skipped, diagnostics record an ignored row, and the
  transaction remains usable for supported rows.

### SP-J-3 — Sync status surfaces conflict diagnostics

- **Setup**: a sync cycle applies some remote rows and skips others.
- **Action**: cycle completes.
- **Expect**: status bus emits online status with remote/applied/local-win
  counters.

### SP-J-4 — Server sync log includes dropped-domain counts

- **Setup**: request includes rows outside the caller's domain claims.
- **Action**: server handles `/sync`.
- **Expect**: structured sync log includes `dropped_push` or `dropped_pull`
  counts for diagnostics.

---

## K. Domain reset generations

### SP-K-1 — Permanent reset advances generation

- **Setup**: a domain has server rows in generation 0.
- **Action**: the owner calls `POST /sync/reset-domain`.
- **Expect**: rows under the domain prefix are physically removed and the
  response returns generation 1.

### SP-K-2 — Offline stale generation cannot resurrect rows

- **Setup**: a device still holds generation-0 rows after the server reset.
- **Action**: it reconnects and pushes those rows.
- **Expect**: the server rejects them, returns generation 1, and the client
  hard-resets the local domain before applying any pull rows.

### SP-K-3 — Reset racing with sync remains authoritative

- **Setup**: a generation-0 sync write races a reset transaction.
- **Action**: both reach D1 concurrently.
- **Expect**: the conditional row write cannot insert after the generation
  advances; the reset wins regardless of request ordering.

---

## Coverage matrix

| Spec area | Case IDs |
|---|---|
| HLC version token | SP-A-* |
| Dirty pointers and row serialization | SP-B-* |
| `POST /sync` wire API | SP-C-* |
| Server row store and cursors | SP-D-* |
| LWW, tombstones, resurrection | SP-E-* |
| Client cycle behavior | SP-F-* |
| Domain prefixes and claims | SP-G-* |
| Bootstrap and forced resync | SP-H-* |
| Errors, retry, scheduling | SP-I-* |
| Diagnostics | SP-J-* |
| Domain reset generations | SP-K-* |

If `sync-v3.md` adds behavior, add at least one `SP-*` case here and cite the
case ID from the test that covers it.
