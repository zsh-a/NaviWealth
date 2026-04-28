import { expect, test } from '@playwright/test';

import {
  attachConsoleSpy,
  expectNoConsoleErrors,
  waitForFlutterReady,
} from './_helpers';

test.describe('boot', () => {
  test('home loads without console or page errors', async ({ page }) => {
    const spy = attachConsoleSpy(page);

    await page.goto('/');
    await waitForFlutterReady(page);

    // Title is set by MaterialApp.onGenerateTitle. We don't lock the exact
    // string (it's localized) — we just want a non-empty title, which
    // means the engine reached the build phase.
    const title = await page.title();
    expect(title).not.toBe('');

    await expectNoConsoleErrors(spy);
  });

  test('manifest is reachable and well-formed', async ({ page, baseURL }) => {
    const res = await page.request.get(`${baseURL}/manifest.json`);
    expect(res.status(), 'manifest must serve 200').toBe(200);
    const body = await res.json();
    expect(body.name, 'manifest.name').toBeTruthy();
    expect(body.icons, 'manifest.icons').toBeInstanceOf(Array);
    expect(
      body.icons.some(
        (icon: { sizes?: string; purpose?: string }) =>
          icon.sizes === '512x512',
      ),
      'manifest must include a 512px icon for installed-PWA splash',
    ).toBe(true);
  });

  test('drift web assets are reachable', async ({ baseURL, request }) => {
    // These two assets are materialized by tool/setup-drift-web.sh. If
    // either is missing, drift can't open the database on web — we want
    // to fail loud rather than wait for a runtime stack trace.
    for (const path of ['/sqlite3.wasm', '/drift_worker.dart.js']) {
      const res = await request.get(`${baseURL}${path}`);
      expect(res.status(), `${path} must be served`).toBe(200);
    }
  });
});
