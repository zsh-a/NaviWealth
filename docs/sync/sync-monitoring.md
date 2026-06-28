# Sync Monitoring Baseline

What the sync API should look like in production, where to watch it, and what
should page someone. Companion to [`sync-v2.md`](./sync-v2.md) (active
contract) and [`sync-e2e-manual.md`](./sync-e2e-manual.md) (manual flows).

## Where the data comes from

| Source | What it tells us | How to access |
|--------|------------------|---------------|
| Cloudflare Workers Analytics | Per-route status code & wall-clock latency, request rate. Free tier on the dash. | Workers dashboard → `naviwealth-backend` → Metrics |
| `wrangler tail` | Structured per-request log line emitted by `apps/backend/src/routes/sync.rs::log_request`. Includes `dur_ms`, batch size, accepted / rejected count, slow flag. | `cd apps/backend && wrangler tail naviwealth-backend --format pretty` |
| D1 query metrics | Per-statement read/write counts and rows-scanned, surfaced by Workers Analytics Engine when the DB is bound. | Workers dashboard → D1 → `naviwealth` → Metrics |
| Mobile `sync_status` table | Client-side status bus events (online / offline / failed) and last error string. Useful to correlate "I had no sync for 3 h" complaints with server-side events. | Settings → Diagnostics → Export sync log |

The structured server log line is the fastest way to see what's happening *now*:

```
[SYNC] op=push status=200 code=ok dur_ms=12 batch=487 acc=487 rej=0 slow=false
[SYNC] op=pull status=200 code=ok dur_ms=8 pulled=42 has_more=false slow=false
[SYNC] op=push status=413 code=payload_too_large dur_ms=2 batch=0 acc=0 rej=0 slow=false
```

Field names are stable; downstream parsers should match on `op=` / `status=` / `code=` literally.

## Baseline targets — v1.0 (single user, polling)

Set generously for a 1-user app on the free tier. Tighten as the real distribution emerges.

| Metric | Target | Definition |
|--------|--------|------------|
| `/sync/push` p95 latency | ≤ 250 ms | Wall-clock, including auth + D1 round-trips |
| `/sync/push` p99 latency | ≤ 500 ms | Tail; an isolated slow request is fine |
| `/sync/pull` p95 latency | ≤ 200 ms | Single page; clients drain pages serially so p95 matters more than p99 |
| `dur_ms > 30` rate | ≤ 5 % of sync requests | The `slow=true` flag — early signal that the D1 50 ms budget is tight |
| 5xx error rate (push + pull) | ≤ 0.5 % over 1 h | Anything above that is a bug, not a transient blip |
| `clock_skew_too_large` rate | ≤ 0.1 % | Clients should self-correct via `/me`. Sustained means a client bug |
| `op_id_mutated` rate | 0 over 24 h | Always a client bug — never expected to fire |
| Pull cursor drift (server lag) | ≤ 60 s | The newest op in `op_log` is at most 1 min ahead of the slowest device's cursor |

## Alerts

Page on sustained breakage, not single 503s.

| Page | Condition | Why |
|------|-----------|-----|
| **P1** — sync down | 5xx rate ≥ 5 % for 5 min on either route | Users can't sync at all |
| **P1** — D1 budget breach | `slow=true` rate ≥ 25 % for 10 min | We're about to start seeing 50 ms isolate kills |
| **P2** — auth failures | 401 rate ≥ 2 % for 30 min | JWT secret rotation gone wrong, or expired tokens not refreshing |
| **P2** — push backlog stuck | A single device's `op_outbox` depth > 200 for 1 h | Client bug or adversarial state — won't self-heal |
| **P3** — protocol skew | `protocol_version` 426 rate ≥ 0.1 % over 24 h | Old client out there; remind via in-app banner |
| **P3** — slow query stragglers | `dur_ms > 100` rate ≥ 1 % over 24 h | Tail latency creeping up; investigate before it crosses the P1 line |

P1 routes to on-call; P2/P3 file Linear tickets in the `OPS` project. Alert wiring lives outside this repo — Cloudflare Workers Logpush → Logflare or similar. Set it up before onboarding a second user.

## D1 slow-query sampling

D1 doesn't expose per-query timing — only aggregate read/write counts. The structured request log is our proxy: `dur_ms` covers everything the handler did in D1, and `slow=true` fires at `dur_ms > 30` (20 ms headroom under the 50 ms isolate cap).

On a sustained `slow=true` spike:

1. Workers dashboard → D1 → query stats. Look for queries with abnormally high `rows_read`. Pull's `MAX(hlc_text)` and the `op_log_row` index probe are prime suspects.
2. Diff `EXPLAIN QUERY PLAN` against `apps/backend/src/sync/materialise.rs` — index drift is the most common root cause.
3. Push hot-row (one row updated thousands of times): LWW `SELECT current` degrades to O(N log N) on op_log scan if `op_log_row` isn't healthy — re-index from a Wrangler shell.

## Tail-spotting playbook

When something is wrong but no alert fired:

```bash
# Live tail — first thing oncall runs. Look for clusters of status>=500 or slow=true.
cd apps/backend && wrangler tail naviwealth-backend --format pretty | grep '\[SYNC\]'

# Per-code breakdown over the last hour (Logpush sink).
awk '/\[SYNC\]/ {for (i=1;i<=NF;i++) if ($i ~ /^code=/) print $i}' ~/logpush-naviwealth-*.log \
  | sort | uniq -c | sort -rn

# Latency distribution from logs.
awk '/\[SYNC\]/ {for (i=1;i<=NF;i++) if ($i ~ /^dur_ms=/) {sub("dur_ms=","",$i); print $i}}' \
  ~/logpush-naviwealth-*.log | sort -n \
  | awk '{a[NR]=$1} END {print "p50="a[int(NR*0.5)] " p95="a[int(NR*0.95)] " p99="a[int(NR*0.99)]}'
```

## Promotion checklist (before onboarding a 2nd user)

- [ ] All P1 alerts wired; real test page received.
- [ ] `wrangler tail --format json` piped to durable log storage (Logpush → R2 / Logflare).
- [ ] D1 slow-query baseline captured for a known-good 1-week window and stashed here for diff reference.
- [ ] `sync-e2e-manual.md` green on the most recent release tag.
- [ ] On-call rotation has at least one person other than the original author.

## References

- `apps/backend/src/routes/sync.rs::log_request` — emitter of the `[SYNC] …` line. Bump its tag if format changes.
- [`sync-v2.md`](./sync-v2.md) — active sync contract and limits.
- [`sync-e2e-manual.md`](./sync-e2e-manual.md) — what to run when a metric goes red.
- [`sync-protocol-tests.md`](./sync-protocol-tests.md) §I — error-code semantics mapped to severities above.
