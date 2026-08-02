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

test.describe('responsive application shell', () => {
  for (const viewport of VIEWPORTS) {
    test(`${viewport.name} keeps core Finance routes inside the viewport`, async ({
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

      for (const route of CORE_ROUTES) {
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
