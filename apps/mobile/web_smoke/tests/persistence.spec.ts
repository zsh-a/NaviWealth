import { expect, test } from '@playwright/test';

import {
  attachConsoleSpy,
  detectDriftImpl,
  expectNoConsoleErrors,
  waitForFlutterReady,
} from './_helpers';

// FIR-40 §4.1: Firefox falls back to IndexedDB because dedicated workers
// don't expose OPFS. The smoke must catch a regression where Firefox
// silently lands on `inMemory` (which would mean we lost persistence).
//
// As of FIR-40, no UI surface forces the database open at boot — the
// `appDatabaseProvider` is materialized lazily by the first widget that
// reads it. Until DB-backed features ship (FIR-37+), `detectDriftImpl`
// can legitimately return 'unknown' because no backing store has been
// created yet. We treat 'unknown' as a soft skip (with a clear reason)
// rather than a hard failure, so this file starts asserting real
// persistence the moment a feature wires up the DB without anyone
// having to remember to update this spec.
async function probeWithRetries(
  page: import('@playwright/test').Page,
  attempts = 8,
  intervalMs = 500,
): Promise<string> {
  let last = 'unknown';
  for (let i = 0; i < attempts; i++) {
    last = await detectDriftImpl(page);
    if (last !== 'unknown') return last;
    await page.waitForTimeout(intervalMs);
  }
  return last;
}

test.describe('Drift persistence', () => {
  test('a persistent storage impl is selected after navigating the app', async ({
    page,
    browserName,
  }) => {
    const spy = attachConsoleSpy(page);
    await page.goto('/');
    await waitForFlutterReady(page);

    // Walk every tab so any DB-touching widget that lands on one of them
    // gets a chance to materialize `appDatabaseProvider`.
    for (const route of ['/assets', '/analytics', '/settings', '/']) {
      await page.goto(route);
      await waitForFlutterReady(page);
    }

    const impl = await probeWithRetries(page);
    test.info().annotations.push({
      type: 'drift-impl',
      description: `${browserName}: ${impl}`,
    });

    if (impl === 'unknown') {
      test.skip(
        true,
        'No widget triggered Drift initialization yet — re-enable the assertion once a DB-backed feature lands.',
      );
    }

    if (browserName === 'firefox') {
      // Tier-2 fallback path — must not silently degrade to inMemory.
      expect(
        ['sharedIndexedDb', 'unsafeIndexedDb', 'opfs'],
        'Firefox must use a persistent backing store',
      ).toContain(impl);
    } else {
      expect(
        ['opfs', 'sharedIndexedDb', 'unsafeIndexedDb', 'inMemory'],
      ).toContain(impl);
    }
    await expectNoConsoleErrors(spy);
  });

  test('reload preserves the storage origin', async ({ page }) => {
    // We can't drive a "create asset → reload → assert" UX path through
    // Playwright (Flutter's canvas isn't reachable without semantics —
    // see web-compat-matrix.md §5). What we *can* assert is the
    // lower-level invariant: once Drift picks an impl, reloading the
    // page must reopen the same one.
    const spy = attachConsoleSpy(page);
    await page.goto('/');
    await waitForFlutterReady(page);
    for (const route of ['/assets', '/analytics', '/settings']) {
      await page.goto(route);
      await waitForFlutterReady(page);
    }

    const before = await probeWithRetries(page);
    if (before === 'unknown') {
      test.skip(
        true,
        'Drift not yet exercised by any feature — see persistence test note.',
      );
    }

    await page.reload();
    await waitForFlutterReady(page);
    for (const route of ['/assets', '/analytics', '/settings']) {
      await page.goto(route);
      await waitForFlutterReady(page);
    }
    const after = await probeWithRetries(page);

    expect(after, 'Drift must reopen the same impl after reload').toBe(before);
    await expectNoConsoleErrors(spy);
  });
});
