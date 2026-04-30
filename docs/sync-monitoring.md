# Sync Monitoring Baseline (FIR-61)

What we expect the sync API to look like in production, where to watch
it, and what should page someone. Companion to
[`sync-protocol.md`](./sync-protocol.md) (the contract) and
[`sync-e2e-manual.md`](./sync-e2e-manual.md) (the manual flows).

## Where the data comes from

| Source | What it tells us | How to access |
|--------|------------------|---------------|
| Cloudflare Workers Analytics | Per-route status code & wall-clock latency, request rate. Free tier on the dash. | Workers dashboard → `naviwealth-backend` → Metrics |
| `wrangler tail` | Structured per-request log line emitted by `apps/backend/src/routes/sync.rs::log_request`. Includes `dur_ms`, batch size, accepted / rejected count, slow flag. | `cd apps/backend && wrangler tail naviwealth-backend --format pretty` |
| D1 query metrics | Per-statement read/write counts and rows-scanned, surfaced by Workers Analytics Engine when the DB is bound. | Workers dashboard → D1 → `naviwealth` → Metrics |
| Mobile `sync_status` table | Client-side status bus events (online / offline / failed) and last error string. Useful to correlate "I had no sync for 3 h" complaints with server-side events. | Settings → Diagnostics → Export sync log |

The structured server log line is the fastest way to see what's
happening *now*. It looks like:

```
[SYNC] op=push status=200 code=ok dur_ms=12 batch=487 acc=487 rej=0 slow=false
[SYNC] op=pull status=200 code=ok dur_ms=8 pulled=42 has_more=false slow=false
[SYNC] op=push status=413 code=payload_too_large dur_ms=2 batch=0 acc=0 rej=0 slow=false
```

Fields are stable; downstream parsers (Logpush JSON sink, the
`workers-analytics-engine` adapter, scratch awk one-liners) should match
on `op=` / `status=` / `code=` literally.

## Baseline targets — v1.0 (single user, polling)

These are the "is the system OK?" thresholds. They're set generously
because we're a 1-user app on the free tier, not an SLA-bearing service.
Tighten as we learn the real distribution.

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

We don't want to wake anyone up over a single 503; we want to wake
someone up when the system is broken for a noticeable window.

| Page | Condition | Why |
|------|-----------|-----|
| **P1** — sync down | 5xx rate ≥ 5 % for 5 min on either route | Users can't sync at all |
| **P1** — D1 budget breach | `slow=true` rate ≥ 25 % for 10 min | We're about to start seeing 50 ms isolate kills |
| **P2** — auth failures | 401 rate ≥ 2 % for 30 min | JWT secret rotation gone wrong, or expired tokens not refreshing |
| **P2** — push backlog stuck | A single device's `op_outbox` depth > 200 for 1 h | Client bug or adversarial state — won't self-heal |
| **P3** — protocol skew | `protocol_version` 426 rate ≥ 0.1 % over 24 h | Old client out there; remind via in-app banner |
| **P3** — slow query stragglers | `dur_ms > 100` rate ≥ 1 % over 24 h | Tail latency creeping up; investigate before it crosses the P1 line |

P1 routes to the on-call number; P2/P3 file Linear tickets in the `OPS`
project (see [the project reference](#references)). Alert wiring lives
outside this repo — Cloudflare Workers Logpush → Logflare or a similar
log-based alerting bus. Set it up before we onboard a second user.

## D1 slow-query sampling

We don't yet have per-query timing on D1 — Cloudflare exposes only
aggregate read/write counts. The structured request log is the proxy:
`dur_ms` includes everything the handler did in D1 (multiple queries
per push). The `slow=true` flag is set when `dur_ms > 30`, which leaves
20 ms of headroom under the platform isolate cap.

When you see a sustained spike of `slow=true`:

1. Check Workers dashboard → D1 → query stats. Look for queries with
   abnormally high `rows_read`. The pull's `MAX(hlc_text)` and the
   `op_log_row` index probe are the prime suspects.
2. Compare `EXPLAIN QUERY PLAN` against
   `apps/backend/src/sync/materialise.rs` — drift between expected
   index and observed scan path is the most common root cause.
3. If it's a push hot-row (one row updated thousands of times), the LWW
   `SELECT current` becomes O(N log N) on op_log scan unless the
   `op_log_row` index is healthy. Re-index the table from a Wrangler
   shell.

## Tail-spotting playbook

When something is wrong but no alert fired:

```bash
# In a real outage, this is the first thing oncall does. Run for 60 s,
# look for clusters of `status>=500` or `slow=true` on adjacent log lines.
cd apps/backend
wrangler tail naviwealth-backend --format pretty | grep '\[SYNC\]'

# Per-error-code breakdown over the last hour (requires Logpush sink).
# If Logpush isn't wired up yet, fall back to wrangler tail + awk.
cat ~/logpush-naviwealth-*.log | \
  awk '/\[SYNC\]/ {for (i=1;i<=NF;i++) if ($i ~ /^code=/) print $i}' | \
  sort | uniq -c | sort -rn

# Slow-request distribution — sanity-check before declaring D1 trouble.
cat ~/logpush-naviwealth-*.log | \
  awk '/\[SYNC\]/ {for (i=1;i<=NF;i++) if ($i ~ /^dur_ms=/) {sub("dur_ms=","",$i); print $i}}' | \
  sort -n | awk '{a[NR]=$1} END {print "p50="a[int(NR*0.5)] " p95="a[int(NR*0.95)] " p99="a[int(NR*0.99)]}'
```

## Promotion checklist before onboarding a 2nd user

- [ ] All P1 alerts wired and a real test page received
- [ ] `wrangler tail --format json` piped to durable log storage (Logpush
      → R2 / Logflare) so awk one-liners work after the fact
- [ ] D1 slow-query baseline captured for a known-good 1-week window
      and stashed in this doc for diff reference
- [ ] Manual checklist (`sync-e2e-manual.md`) green on the most recent
      release tag
- [ ] On-call rotation has at least one person other than the original
      author

## References

- `apps/backend/src/routes/sync.rs::log_request` — emitter of the
  `[SYNC] …` line. Bump its tag if the format changes.
- `docs/sync-protocol.md` §1 (D1 50 ms budget), §5.5 (rate limits).
- `docs/sync-e2e-manual.md` — what to run if a metric goes red.
- `docs/sync-protocol-tests.md` §I — error-code semantics; the alert
  table above maps each code to a severity.
