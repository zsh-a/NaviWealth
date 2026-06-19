import { expect, test } from '@playwright/test';

import {
  attachConsoleSpy,
  detectDriftImpl,
  expectNoConsoleErrors,
  waitForFlutterReady,
} from './_helpers';

// FIR-61 §自动化场景: Web 多 Tab 并发写.
//
// We can't drive Flutter widgets from Playwright (canvas, no semantics —
// see web-compat-matrix.md §5), so the multi-tab UX-level scenario lives
// in the manual checklist (`docs/sync-e2e-manual.md`).
//
// What this spec catches automatically is the *prerequisite* for safe
// multi-tab sync: both tabs in the same browser context must open the
// same Drift backing store. If the second tab silently fell back to
// `inMemory` (or to a different storage origin), tabs would diverge and
// the SyncEngine couldn't reconcile across them. Persistence between
// tabs is the property the protocol assumes; this is the regression net.

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

test.describe('multi-tab Drift sharing', () => {
  test('a second tab in the same context shares the Drift backend', async ({
    context,
    browserName,
  }) => {
    const tabA = await context.newPage();
    const spyA = attachConsoleSpy(tabA);
    await tabA.goto('/');
    await waitForFlutterReady(tabA);
    for (const route of ['/activity', '/wealth', '/plan', '/settings']) {
      await tabA.goto(route);
      await waitForFlutterReady(tabA);
    }
    const implA = await probeWithRetries(tabA);
    test.info().annotations.push({
      type: 'drift-impl-tab-a',
      description: `${browserName}: ${implA}`,
    });

    if (implA === 'unknown') {
      test.skip(
        true,
        'Drift not yet exercised by any feature — see persistence.spec note.',
      );
    }

    const tabB = await context.newPage();
    const spyB = attachConsoleSpy(tabB);
    await tabB.goto('/');
    await waitForFlutterReady(tabB);
    for (const route of ['/activity', '/wealth', '/plan', '/settings']) {
      await tabB.goto(route);
      await waitForFlutterReady(tabB);
    }
    const implB = await probeWithRetries(tabB);
    test.info().annotations.push({
      type: 'drift-impl-tab-b',
      description: `${browserName}: ${implB}`,
    });

    expect(
      implB,
      'second tab must land on the same Drift impl as the first',
    ).toBe(implA);

    await expectNoConsoleErrors(spyA);
    await expectNoConsoleErrors(spyB);
  });
});
