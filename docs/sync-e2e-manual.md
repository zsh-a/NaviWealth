# Multi-device Sync — Manual E2E Checklist (FIR-61)

Complements the automated suites (`apps/mobile/test/e2e/sync_e2e_test.dart`, `apps/mobile/web_smoke/tests/multi_tab.spec.ts`) and the protocol catalogue in [`sync-protocol-tests.md`](./sync-protocol-tests.md). Covers what automation can't: real OS background schedulers, real network jitter, real human-eye latency, and Flutter UI flows unreachable from Playwright (canvas, no semantics).

Run before each release tagged `*-rc.*`. File a bug for any FAIL / DEGRADED; mark PASS or SKIP (reason) inline in the run log on the release ticket.

## Pre-flight (once per run)

1. Sign in on every test device with the same user. Confirm
   **Settings → Sync → Status** is `Online` on all of them.
2. **Settings → Sync → Last sync** is within 60 s on all devices.
3. Capture the build number on each device — paste into the run log.

## S1 — Daily-life round-trip (iPhone → Mac → iPad)

Spec coverage: 单端写入 → 其它端可见; HLC LWW; tombstone hide.

| # | Device | Action | Expected (other devices, within 60 s) |
|---|--------|--------|---------------------------------------|
| 1 | iPhone | Add transaction "Coffee, ¥35" at 09:00 local | iPhone shows immediately. Mac and iPad show it after foreground / Sync now. |
| 2 | Mac (web) | Edit the transaction note to "Coffee w/ Lisa" | iPhone + iPad show the new note within 60 s (foreground polling) or on Sync now. |
| 3 | iPad | Delete the transaction | iPhone + Mac stop showing it. **The row must not reappear** if you background and re-foreground each device. |

**FAIL** if a peer still shows the deleted row after a foreground refresh.

## S2 — Offline editing then reconcile

Spec coverage: 离线编辑 → 上线后批量上传.

1. Put **iPhone** in airplane mode. Confirm **Settings → Sync → Status**
   becomes `Offline` within 30 s.
2. Over ~10 min, do all of:
   - Add 2 manual assets.
   - Edit one of them twice.
   - Delete one existing transaction.
3. Force-quit the app on iPhone. Re-open it (still offline). The local
   edits must still be present (outbox survived restart).
4. Disable airplane mode. **Sync → Status** should flip to `Syncing` then
   `Online`. **Outbox depth** drops to 0.
5. On **Mac (web)**, run **Sync now**. All five effects from step 2
   appear in their final state. No intermediate flicker that resolves
   wrong.

**DEGRADED** if reconcile takes more than two foreground cycles
(120 s end-to-end) on a normal network.
**FAIL** if any of step 2's edits is lost.

## S3 — Concurrent same-row edits

Spec coverage: HLC LWW, no UI flicker resolving to wrong value.

1. Pick a transaction visible on both **iPhone** and **iPad**.
2. Disable network on both (airplane mode each).
3. On iPhone, edit the note to "iPhone wins?". On iPad, edit the note to
   "iPad wins?". Both apps must show their own edit immediately.
4. Re-enable network on iPhone first. Wait for `Online`.
5. Re-enable network on iPad. Wait for `Online`.
6. After the next foreground cycle on the device that synced first, both
   devices must agree on a single value — exactly one of the two edits.
   The "loser" device must not still display its own version.

**FAIL** if devices disagree after both have synced twice. **FAIL** if a
device transiently shows the loser's value, then snaps to the winner —
that's an apply-order bug.

## S4 — Web multi-tab concurrency

Spec coverage: 浏览器多 Tab 并发写; Service Worker doesn't break sync.

1. Open the web app in **two tabs** in the same browser (same profile,
   same window). Confirm both reach the dashboard.
2. In tab A, add a manual asset "MultiTab-A". In tab B, add a manual
   asset "MultiTab-B".
3. Run **Sync now** in tab A.
4. Reload tab B (Cmd-R / Ctrl-R). **Both** assets must appear.
5. Edit "MultiTab-A" in tab A. Within 60 s of foreground polling on
   tab B (or on **Sync now**), tab B reflects the edit.

**FAIL** if tab B shows neither asset, or only its own. (That means the
two tabs opened separate Drift backends — covered automatically by
`multi_tab.spec.ts`, but worth confirming the user-visible flow too.)

## S5 — Background sync (mobile)

Spec coverage: BackgroundTasks / WorkManager push backlog.

1. On **iPhone**, edit a transaction note. Background the app
   immediately (don't kill — just home).
2. Wait at least 30 minutes (let iOS schedule a background task; this is
   intentionally outside the 30 s foreground polling cadence).
3. On **Mac (web)** without touching iPhone, run **Sync now**. The
   edit is present.

**SKIP** if the device has Low Power Mode on (iOS suspends background
work). **FAIL** if iPhone goes another foreground cycle without the
edit having reached Mac.

## S6 — Service Worker continuity (web)

Spec coverage: 浏览器 Service Worker 后台续传.

1. On **Mac (web)**, edit a transaction note in tab A. Note the time.
2. Switch to a different tab in the browser (don't close the
   NaviWealth tab). Wait ~30 s.
3. On **iPhone**, run **Sync now**. The edit is present on iPhone within
   60 s.

**FAIL** if the edit only reaches iPhone after refocusing the
NaviWealth tab. (Means the SW is not backing up the foreground polling.)

## S7 — Bulk import / large delta

Spec coverage: 1000+ op batch over real network.

1. Generate a CSV of ~1000 transactions (a prior export from another instance, or any ad-hoc generator).
2. Import on **Mac (web)**. Watch **Sync → Outbox depth** drop in waves
   of ≤ 500 (the spec batch cap).
3. After outbox is 0, on **iPhone** run **Sync now**. iPad pulls in
   pages — confirm `Pulling…` is shown for at least 1 of the cycles.
4. Counts on all three devices match (use **Settings → Diagnostics →
   Row counts**).

**DEGRADED** if total reconcile takes > 5 min on a 50 Mbps connection.
**FAIL** if counts differ after both peers have completed two full
foreground cycles.

## Run log template

Paste this into the release ticket; fill in inline.

```
Build: <commit-sha>  Date: <YYYY-MM-DD>
Devices:
  iPhone: <model, iOS version, app build>
  iPad:   <model, iPadOS version, app build>
  Mac:    <macOS, browser+version, app build>

S1 — daily round-trip:        [ PASS / FAIL / SKIP ] notes:
S2 — offline reconcile:        [ PASS / FAIL / SKIP ] notes:
S3 — concurrent same-row:      [ PASS / FAIL / SKIP ] notes:
S4 — web multi-tab:            [ PASS / FAIL / SKIP ] notes:
S5 — mobile background sync:   [ PASS / FAIL / SKIP ] notes:
S6 — web Service Worker:       [ PASS / FAIL / SKIP ] notes:
S7 — bulk delta:               [ PASS / FAIL / SKIP ] notes:
```

## Triage shortcuts

If something fails, capture before filing:

- **Mobile**: `Settings → Diagnostics → Export sync log` — attaches
  the last 24 h of `sync_status` events + `sync_errors`.
- **Web**: DevTools → Application → IndexedDB → `naviwealth` — paste
  the row count of `op_log` and `op_outbox`.
- **Server**: ask oncall to pull
  `wrangler tail naviwealth-backend --format=pretty` for the same window
  — see [`sync-monitoring.md`](./sync-monitoring.md) for the dashboards
  oncall watches.
