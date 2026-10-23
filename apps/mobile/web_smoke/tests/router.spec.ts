import { expect, test } from './_app';

import {
  attachConsoleSpy,
  enableFlutterSemantics,
  expectNoConsoleErrors,
  openApp,
} from './_helpers';

const ROUTES = [
  { path: '/', role: 'button', name: 'Add account' },
  { path: '/activity', role: 'banner', name: 'Records' },
  { path: '/wealth', role: 'banner', name: 'Wealth' },
  { path: '/plan', role: 'button', name: 'Budget, Needs setup' },
  { path: '/settings', role: 'button', name: 'Local mode Sync data across devices' },
  { path: '/settings/appearance', role: 'button', name: 'Language System default' },
] as const;

test.describe('go_router (PathUrlStrategy)', () => {
  for (const route of ROUTES) {
    test(`direct hit on ${route.path} renders its destination`, async ({ page }) => {
      const spy = attachConsoleSpy(page);
      await openApp(page, route.path);
      await expect(page.getByRole(route.role, { name: route.name, exact: true })).toBeVisible();
      expect(new URL(page.url()).hash).toBe('');
      expect(new URL(page.url()).pathname).toBe(route.path);
      await expectNoConsoleErrors(spy);
    });
  }

  test('hard refresh preserves the rebalance destination', async ({ page }) => {
    const spy = attachConsoleSpy(page);
    await openApp(page, '/plan/rebalance');
    await expect(page.getByRole('group', { name: /^No data yet Add assets/ })).toBeVisible();
    await page.reload();
    await enableFlutterSemantics(page);
    await expect(page).toHaveURL(/\/plan\/rebalance$/);
    await expect(page.getByRole('group', { name: /^No data yet Add assets/ })).toBeVisible();
    await expectNoConsoleErrors(spy);
  });

  test('tab clicks and browser back/forward restore rendered destinations', async ({ page }) => {
    const spy = attachConsoleSpy(page);
    await openApp(page, '/');
    await expect(page.getByRole('button', { name: 'Add account', exact: true })).toBeVisible();

    await page.getByRole('button', { name: 'Wealth', exact: true }).click();
    await expect(page.getByRole('banner', { name: 'Wealth', exact: true })).toBeVisible();
    await expect(page).toHaveURL(/\/wealth$/);
    await page.getByRole('button', { name: 'Plan', exact: true }).click();
    await expect(page.getByRole('button', { name: 'Budget, Needs setup', exact: true })).toBeVisible();
    await expect(page).toHaveURL(/\/plan$/);

    await page.goBack();
    await expect(page).toHaveURL(/\/wealth$/);
    await expect(page.getByRole('banner', { name: 'Wealth', exact: true })).toBeVisible();
    await page.goForward();
    await expect(page).toHaveURL(/\/plan$/);
    await expect(page.getByRole('button', { name: 'Budget, Needs setup', exact: true })).toBeVisible();
    await expectNoConsoleErrors(spy);
  });
});
