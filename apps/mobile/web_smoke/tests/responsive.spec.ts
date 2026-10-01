import { expect, test } from '@playwright/test';

import {
  attachConsoleSpy,
  expectNoConsoleErrors,
  waitForFlutterReady,
} from './_helpers';

const VIEWPORTS = [
  { name: 'phone', width: 390, height: 844 },
  { name: 'tablet', width: 840, height: 1024 },
  { name: 'desktop', width: 1200, height: 900 },
  { name: 'wide desktop', width: 1600, height: 1000 },
] as const;

const CORE_ROUTES = [
  '/',
  '/wealth',
  '/wealth/accounts',
  '/plan',
  '/plan/rebalance',
] as const;

// Direct routes, refresh, and history already have a dedicated suite. PRs
// sample content-heavy routes at phone/desktop sizes; weekly/manual runs
// retain every route and breakpoint. Local runs default to the full matrix.
const scope = process.env.WEB_SMOKE_RESPONSIVE ?? 'full';
if (scope !== 'compact' && scope !== 'full') {
  throw new Error(`Unknown WEB_SMOKE_RESPONSIVE scope: ${scope}`);
}
const viewports = scope === 'compact'
  ? VIEWPORTS.filter(({ name }) => name === 'phone' || name === 'desktop')
  : VIEWPORTS;
const routes = scope === 'compact'
  ? ['/wealth/accounts', '/plan/rebalance']
  : CORE_ROUTES;

test.describe('responsive application shell', () => {
  for (const viewport of viewports) {
    test(`${viewport.name} keeps Finance documents inside the viewport`, async ({
      browserName,
      page,
    }) => {
      test.skip(
        browserName !== 'chromium',
        'The cross-browser projects already cover routing; this matrix covers layout breakpoints once.',
      );

      await page.setViewportSize({
        width: viewport.width,
        height: viewport.height,
      });
      const spy = attachConsoleSpy(page);
      const notFoundResponses: string[] = [];
      page.on('response', (response) => {
        if (response.status() === 404) notFoundResponses.push(response.url());
      });

      for (const route of routes) {
        await page.goto(route);
        await waitForFlutterReady(page);

        expect(new URL(page.url()).pathname).toBe(route);
        const dimensions = await page.evaluate(() => ({
          innerWidth: window.innerWidth,
          bodyScrollWidth: document.body.scrollWidth,
          documentScrollWidth: document.documentElement.scrollWidth,
        }));
        expect(dimensions.bodyScrollWidth).toBeLessThanOrEqual(
          dimensions.innerWidth + 1,
        );
        expect(dimensions.documentScrollWidth).toBeLessThanOrEqual(
          dimensions.innerWidth + 1,
        );
      }

      expect(notFoundResponses, 'unexpected 404 responses').toEqual([]);
      await expectNoConsoleErrors(spy);
    });
  }
});
