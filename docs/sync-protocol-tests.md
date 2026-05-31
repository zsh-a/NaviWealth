# Sync Protocol — Test Case Catalogue

Companion to [`sync-protocol.md`](./sync-protocol.md). These are
**protocol-level** scenarios that both the client (Flutter) and server
(Workers + Rust) test suites must cover. Implementation tickets:

- Server: Sync API implementation.
- Client: SyncEngine implementation.

Each case lists: **setup → action → expected outcome**. Test names follow
`SP-<group>-<n>` for cross-referencing in PRs.

---

## A. HLC mechanics (unit-level, both client and server)

### SP-A-1 — `next` advances logical when phys equal

- **Setup**: `local = (1000, 5)`, `now_ms = 1000`.
- **Action**: `next(local, now_ms, dev)`.
- **Expect**: `(1000, 6, dev)`.

### SP-A-2 — `next` resets logical when phys advances

- **Setup**: `local = (1000, 99)`, `now_ms = 1500`.
- **Action**: `next(local, now_ms, dev)`.
- **Expect**: `(1500, 0, dev)`.

### SP-A-3 — `next` keeps `pmax` when local > now

- **Setup**: `local = (2000, 0)`, `now_ms = 1500` (clock went backwards).
- **Action**: `next(...)`.
- **Expect**: `(2000, 1, dev)`.

### SP-A-4 — `merge` takes max of three sources

- **Setup**: `local = (1000, 3)`, `recv = (1500, 7)`, `now = 1200`.
- **Action**: `merge(...)`.
- **Expect**: `(1500, 8, dev)`.

### SP-A-5 — Logical overflow bumps phys

- **Setup**: `local = (1000, 65535)`, `now_ms = 1000`.
- **Action**: `next(...)`.
- **Expect**: `(1001, 0, dev)`.

### SP-A-6 — Canonical string round-trip

- **Setup**: `hlc = (1714291200000, 1, "1f5b...c01")`.
- **Action**: serialise, parse.
- **Expect**: input == output bit-for-bit.

### SP-A-7 — Lex order matches tuple order (random fuzz, 1k pairs)

- **Action**: for each pair `(a, b)` of random HLCs, assert
  `cmp(serialise(a), serialise(b)) == cmp_tuple(a, b)`.

---

## B. OpLog encoding

### SP-B-1 — Insert encodes full row (incl. PK)

- **Setup**: new `Account { id="A1", name="Cash", currency="USD", … }`.
- **Action**: encode op.
- **Expect**: `op_type == "insert"`, `fields_diff` contains `id`, `name`,
  `currency`, all required cols.

### SP-B-2 — Update encodes only changed fields

- **Setup**: existing row with `name="Cash"`, user changes name to `"Wallet"`.
- **Action**: encode op.
- **Expect**: `fields_diff == {"name":"Wallet","updated_at":"…Z"}` (no other
  cols).

### SP-B-3 — Delete encodes null diff

- **Action**: delete op for row.
- **Expect**: `fields_diff == null`, `op_type == "delete"`.

### SP-B-4 — Empty update is rejected client-side before push

- **Setup**: caller passes `{}` to repo.update.
- **Expect**: error raised at repo layer; no op_log row written.

### SP-B-5 — `null` vs absent column distinction

- **Setup**: row has `notes = "x"`. User clears notes (sets to NULL).
- **Action**: encode update.
- **Expect**: `fields_diff` contains `"notes": null`. Subsequent test of a
  no-op edit: `"notes"` key absent.

### SP-B-6 — DateTime serialised UTC RFC3339 with millisecond precision

- **Setup**: `created_at = 2026-04-28T12:00:00.123 in Asia/Shanghai`.
- **Expect**: encoded as `"2026-04-28T04:00:00.123Z"`.

### SP-B-7 — `fields_diff` rejected when > 64 KB serialised

- **Setup**: synthetic op with 70 KB `note`.
- **Action**: push.
- **Expect**: server returns per-op `payload_too_large`. Client drops op,
  records to `sync_errors`.

---

## C. Push API

### SP-C-1 — Happy path push of 3 ops

- **Setup**: client outbox has 3 ops (insert, update, delete).
- **Action**: `POST /sync/push`.
- **Expect**: 200, `accepted == 3`, `rejected == []`. Rows materialised on
  server. `op_log` has 3 rows with `server_hlc > 0`.

### SP-C-2 — Idempotent re-push

- **Setup**: SP-C-1 succeeded. Client did not delete outbox (simulate
  partial-failure resume).
- **Action**: re-push the same batch.
- **Expect**: 200, `accepted == 3`. No duplicate rows in `op_log` (PK on
  `op_id`). No double-apply on materialised tables.

### SP-C-3 — `op_id_mutated` on conflicting re-push

- **Setup**: re-push SP-C-1 batch but bump `client_hlc` of one op.
- **Expect**: that op rejected with `op_id_mutated`. Other ops accepted.

### SP-C-4 — Out-of-order batch rejected

- **Setup**: 3 ops with HLCs `[h2, h1, h3]` (h1 < h2 < h3).
- **Action**: push.
- **Expect**: 400 `ops_unordered`, no ops persisted.

### SP-C-5 — Device mismatch rejected

- **Setup**: batch `device_id = D1`, op inside has `device_id = D2`.
- **Action**: push.
- **Expect**: 400 `device_mismatch`.

### SP-C-6 — Clock skew above cap rejected

- **Setup**: client phys_ms = `server_now + 5 min`.
- **Action**: push.
- **Expect**: 409 `clock_skew_too_large`.

### SP-C-7 — Body size cap enforced

- **Setup**: 500 ops × 3 KB each ≈ 1.5 MB body.
- **Action**: push.
- **Expect**: 413 `payload_too_large`. Client splits and retries.

### SP-C-8 — Server stamps server_hlc and persists in op_log.hlc_text

- **Setup**: client_hlc.phys_ms = 1000, server_now = 5000.
- **Action**: push 1 op.
- **Expect**: `op_log.hlc_text.phys_ms == 5000` (server_now wins),
  `op_log.client_hlc.phys_ms == 1000` preserved.

### SP-C-9 — Push response advances client HLC state

- **Setup**: client_hlc state = `(1000, 0)`. Server returns
  `server_hlc_high = (5000, 3)`.
- **Action**: client merges.
- **Expect**: client_hlc state = `(5000, 4, self_device_id)` (next on top).

### SP-C-10 — Stale op records to op_log but doesn't update row

- **Setup**: server has row with `last_hlc = 1000`. Client pushes update
  with `client_hlc.phys_ms = 500` (older than current after server stamp it
  becomes server_hlc > 1000 if `server_now > 1000`; to construct true
  shadow, push two ops in batch where the **second** has higher HLC for
  same row, then a third op for same row with older HLC).
- **Expect**: shadowed op recorded in `op_log` with its stamped `server_hlc`
  but does not change materialised row state. `accepted` count includes it
  (it's not "rejected" — it's recorded but inert for that row).

> **Note**: Because the server always stamps with `next()` on top of the
> current server clock, no incoming op will ever produce a `server_hlc`
> lower than an older op's `server_hlc` for the same row, *unless ops are
> intentionally pre-ordered such that the materialiser sees an older one
> last*. This test is most cleanly written by manually inserting a high-HLC
> op_log row first, then pushing.

---

## D. Pull API

### SP-D-1 — First sync (`since` empty)

- **Setup**: server has 7 ops total for user.
- **Action**: `GET /sync/pull?since=&device_id=D1` (no ops authored by D1).
- **Expect**: 200, 7 ops returned in HLC ascending order, `has_more = false`.

### SP-D-2 — Pull filters out caller's own device

- **Setup**: server has 5 ops from D1, 3 ops from D2.
- **Action**: pull as D1.
- **Expect**: 3 ops returned (only D2's). All 3 have `device_id == D2`.

### SP-D-3 — Strictly greater-than `since`

- **Setup**: 3 ops with HLCs `h1 < h2 < h3`.
- **Action**: pull with `since = h2`.
- **Expect**: only the op with HLC `h3` returned (h2 is **not** included).

### SP-D-4 — Pagination, `has_more` true on full page

- **Setup**: 1200 ops on server.
- **Action**: pull with `limit=500`.
- **Expect**: 500 ops, `has_more = true`. Repeat with `since = last.hlc` →
  500 more, still `has_more = true`. Third call → 200, `has_more = false`.

### SP-D-5 — Pagination cursor advances even on empty page

- **Setup**: server has ops only from caller's own device (filtered out).
- **Action**: pull.
- **Expect**: `ops == []`, `server_hlc_high` set to current max HLC,
  `has_more = false`. Client persists `server_hlc_high` as cursor.

### SP-D-6 — Body-size cap shortens page

- **Setup**: 500 ops on server, each ~3 KB.
- **Action**: pull with `limit=500`.
- **Expect**: < 500 ops returned, `has_more = true`. Total response body
  ≤ 1 MB.

### SP-D-7 — `invalid_hlc` on garbage `since`

- **Action**: `GET /sync/pull?since=banana&device_id=D1`.
- **Expect**: 400 `invalid_hlc`.

---

## E. Conflict resolution (LWW)

### SP-E-1 — Two devices update same row, higher HLC wins

- **Setup**: D1 sets `name="Foo"` at HLC h_a. D2 sets `name="Bar"` at HLC
  h_b > h_a. Both push (any order).
- **Action**: D1 pulls.
- **Expect**: D1's local row reflects `name="Bar"`. Server row also `"Bar"`.

### SP-E-2 — Same scenario but D2's clock is behind

- **Setup**: D1 HLC phys=2000, D2 HLC phys=1000. D2 sets `name="Bar"` at
  (1000, 0). D1 sets `name="Foo"` at (2000, 0).
- **Action**: both push, D1 pulls.
- **Expect**: D1 unchanged (`Foo`), D2 after pull also `Foo`. (Higher HLC
  is D1's, regardless of arrival order.)

### SP-E-3 — Insert vs insert tie-break by node_id

- **Setup**: pathological — both devices generate ops with identical
  `(phys_ms, logical)`. (Achievable in tests by faking clocks.)
- **Expect**: deterministic winner = the one with lex-greater `node_id`
  UUID. Both devices converge to that row.

### SP-E-4 — Delete then late update resurrects

- **Setup**: D1 deletes row at h_d. D2 (offline before delete) updates row at
  h_u > h_d.
- **Action**: D1 pushes, then D2 pushes, both pull.
- **Expect**: server and both clients show row alive (`deleted_at = null`)
  with D2's update applied. `last_hlc = h_u`.

### SP-E-5 — Late delete wins over earlier update

- **Setup**: D1 update at h_u, D2 delete at h_d > h_u.
- **Expect**: row marked deleted (`deleted_at` set, `last_hlc = h_d`).

### SP-E-6 — Update on a deleted row before resurrection is shadowed

- **Setup**: row already deleted at h_d. New op with `op_type=update` at
  hlc h_u < h_d arrives.
- **Expect**: shadowed; row remains deleted. OpLog still records.

### SP-E-7 — Insert on a row that already exists is treated as update

- **Setup**: row exists with `name="A"`. Op `insert` arrives with
  `name="B"` and higher HLC.
- **Expect**: row materialises as if it were an update — `name="B"`,
  `last_hlc = new`. No PK conflict error.

---

## F. Offline editing

### SP-F-1 — Many local edits while offline, single push when online

- **Setup**: airplane mode. User creates 3 accounts, edits 2, deletes 1
  over 10 minutes.
- **Action**: come online.
- **Expect**: SyncEngine pushes a batch of 6 ops. All accepted. Server
  state matches client. `op_outbox` empty.

### SP-F-2 — Outbox survives app restart

- **Setup**: SP-F-1 setup, then kill app before going online.
- **Action**: relaunch app, come online.
- **Expect**: outbox replayed; same outcome as SP-F-1.

### SP-F-3 — Long offline divergence between two devices, then reconcile

- **Setup**: D1 and D2 both offline 24 h, each edits ~50 rows independently.
- **Action**: both come online, both push, both pull.
- **Expect**: both converge to the same materialised state. For
  same-row collisions: row reflects the higher-HLC op. No data loss in
  OpLog.

### SP-F-4 — Local row already reflects un-pushed op

- **Setup**: user creates row offline. Goes online before push completes
  (simulated via slow network).
- **Action**: pull runs first, returns no ops for this row (no other
  device has it). Push runs after.
- **Expect**: no double-apply; local row matches server after push.

---

## G. Concurrency & echo prevention

### SP-G-1 — Push on D1, pull on D1 right after — no echo

- **Setup**: D1 pushes 3 ops successfully.
- **Action**: D1 pulls.
- **Expect**: own 3 ops are **not** returned (server filters by `device_id
  != D1`). Cursor still advances to `server_hlc_high`.

### SP-G-2 — Push on D1, pull on D2 — D2 receives them

- **Action**: D2 pulls after SP-G-1's push.
- **Expect**: D2 gets all 3 ops. After local apply, materialised state
  matches server.

### SP-G-3 — Concurrent push from same device serialised

- **Setup**: client triggers two pushes back-to-back (simulate UI bug).
- **Expect**: SyncEngine mutex enforces serial execution; second push waits
  for first. No duplicate ops on server.

### SP-G-4 — Push and pull from same device do not interleave

- **Action**: kick a push, immediately ask for a pull on the same engine.
- **Expect**: pull blocks until push completes. Verified by counting
  state-machine transitions in test instrumentation.

---

## H. Tombstones

### SP-H-1 — Deleted rows hidden from default queries

- **Setup**: row with `deleted_at != null`.
- **Action**: query `accountRepo.list()`.
- **Expect**: row not returned. `accountRepo.listIncludingDeleted()`
  (admin/diag) does return it.

### SP-H-2 — Tombstone propagates across devices

- **Setup**: D1 deletes row at h_d.
- **Action**: D2 pulls.
- **Expect**: D2's local row has `deleted_at = …`, hidden from list.

### SP-H-3 — Tombstone replays idempotently

- **Setup**: D2 has already applied delete. Pulls again with old `since`.
- **Expect**: re-applying the delete leaves state unchanged
  (`deleted_at` not bumped to a different value, `last_hlc` not regressed).

### SP-H-4 — Resurrection clears `deleted_at` on materialised row

- **Setup**: SP-E-4 setup.
- **Action**: pull on a third device.
- **Expect**: row appears alive in queries. `deleted_at = null`.

---

## I. Auth, drift, errors

### SP-I-1 — Missing JWT → 401

- **Action**: any sync endpoint without `Authorization`.
- **Expect**: 401 `unauthorized`. Client triggers re-auth.

### SP-I-2 — Expired JWT → 401, refresh, retry

- **Action**: pull with expired token.
- **Expect**: client refreshes via auth flow and retries
  transparently.

### SP-I-3 — Wrong protocol version → 426

- **Action**: send `Sync-Protocol-Version: 999`.
- **Expect**: 426 `protocol_version`. Client surfaces "update required" UX.

### SP-I-4 — Drift correction via `/me`

- **Setup**: device clock 2 hours fast.
- **Action**: call `/me` on launch.
- **Expect**: client logs warning, biases first HLC after sync toward
  server_now. Subsequent push: server stamps `server_hlc.phys_ms ≈
  server_now`, client merges back into a sane state.

### SP-I-5 — `429` honours `Retry-After`

- **Setup**: server returns 429 with `Retry-After: 10`.
- **Expect**: SyncEngine waits ≥ 10 s before retrying push or pull.

### SP-I-6 — `5xx` exponential backoff

- **Setup**: server returns 500 three times in a row.
- **Expect**: client backs off 1 s, 2 s, 4 s. Cap 5 minutes. Resets on
  success.

---

## J. Bootstrap & re-sync

### SP-J-1 — Fresh device first sync

- **Setup**: brand new device, never synced. Server has 250 ops for user.
- **Action**: launch, login, sync.
- **Expect**: pull drains all 250 ops (1 page or 1+ pages depending on size).
  Local DB materialised. Cursor = max HLC.

### SP-J-2 — Cursor reset / forced full re-sync

- **Setup**: existing device, `last_pulled_hlc` cleared (e.g. user nuked
  local cache).
- **Action**: pull.
- **Expect**: same outcome as SP-J-1. Materialised state converges (no
  duplicate inserts because LWW + idempotent op_id).

### SP-J-3 — Cursor ahead of server (impossible / corrupted state)

- **Setup**: client cursor `= 9999999999000`, server max HLC much lower.
- **Action**: pull.
- **Expect**: 200, 0 ops, `has_more = false`. Client logs and continues —
  no harm done. (Server SELECT trivially returns empty.)

### SP-J-4 — Mixed: pull + simultaneous local edits

- **Action**: while a multi-page pull is in progress, user creates 2 new
  rows.
- **Expect**: local rows are written immediately; SyncEngine queues the new
  ops in outbox. After pull completes, push runs and ships them. No
  ordering anomaly.

---

## K. Misc / smoke

### SP-K-1 — `/me` returns user, server_now, server_hlc

- **Action**: call `/me` with valid JWT.
- **Expect**: 200 with all three fields. `server_now` within 100 ms of test
  clock.

### SP-K-2 — Health endpoints unaffected

- **Action**: hit `/health`, `/health/db`.
- **Expect**: 200 (existing baseline still passes).

### SP-K-3 — Unknown table in op rejected

- **Setup**: client somehow submits op with `table = "secret_diary"`.
- **Action**: push.
- **Expect**: server rejects per-op with `unknown_table` (subtype of
  `bad_request`). Client logs to `sync_errors`.

### SP-K-4 — Unknown column in `fields_diff` ignored on apply, recorded raw

- **Setup**: server schema knows columns `a, b`. Client sends
  `{"a":1,"c":2}`.
- **Expect**: row updates `a`. `c` is silently dropped from the
  materialiser but the **op_log row preserves the original diff** — so a
  future schema migration can replay and pick up `c`.

---

## Coverage matrix

| Section | Lines of spec covered |
|---------|-----------------------|
| HLC (§3) | A-1 … A-7 |
| OpLog (§4) | B-1 … B-7 |
| Push API (§5.2) | C-1 … C-10 |
| Pull API (§5.3) | D-1 … D-7 |
| Conflict (§6) | E-1 … E-7 |
| Client flow (§7) | F-1 … F-4, G-1 … G-4, J-4 |
| Server flow (§8) | C-*, D-*, E-* |
| Tombstones (§4.3, §6.3) | H-1 … H-4 |
| Errors / version (§5.4, §10) | I-1 … I-6, K-3, K-4 |
| Bootstrap | J-1 … J-3 |

If you add a new behaviour to the spec, add at least one SP-* case here and
cite it in the spec section that introduces the behaviour.
