import { expect, test } from '@playwright/test';

import {
  attachConsoleSpy,
  expectNoConsoleErrors,
  waitForFlutterReady,
} from './_helpers';

// PathUrlStrategy is enabled in app/bootstrap.dart, so the routes below
// must work as direct hits without any `#/` fragment. The asserted route
// paths come from app/route_paths.dart and docs/web-routing.md.
const ROUTES = ['/', '/activity', '/wealth', '/plan', '/settings'] as const;

test.describe('go_router (PathUrlStrategy)', () => {
  for (const route of ROUTES) {
    test(`direct hit on ${route} renders without #fragment`, async ({ page }) => {
      const spy = attachConsoleSpy(page);
      await page.goto(route);
      await waitForFlutterReady(page);
      expect(new URL(page.url()).hash).toBe('');
      expect(new URL(page.url()).pathname).toBe(route);
      await expectNoConsoleErrors(spy);
    });
  }

  test('hard refresh on a non-root route re-renders the same route', async ({
    page,
  }) => {
    const spy = attachConsoleSpy(page);
    await page.goto('/plan/rebalance');
    await waitForFlutterReady(page);
    expect(new URL(page.url()).pathname).toBe('/plan/rebalance');

    await page.reload();
    await waitForFlutterReady(page);
    expect(new URL(page.url()).pathname).toBe('/plan/rebalance');

    await expectNoConsoleErrors(spy);
  });

  test('browser back/forward restores prior route', async ({ page }) => {
    const spy = attachConsoleSpy(page);
    await page.goto('/');
    await waitForFlutterReady(page);

    await page.goto('/wealth');
    await waitForFlutterReady(page);
    await page.goto('/settings');
    await waitForFlutterReady(page);

    await page.goBack();
    await waitForFlutterReady(page);
    expect(new URL(page.url()).pathname).toBe('/wealth');

    await page.goForward();
    await waitForFlutterReady(page);
    expect(new URL(page.url()).pathname).toBe('/settings');

    await expectNoConsoleErrors(spy);
  });
});
