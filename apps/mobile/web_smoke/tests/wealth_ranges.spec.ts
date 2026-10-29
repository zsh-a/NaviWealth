import { expect, test } from './_app';

import {
  attachConsoleSpy,
  expectNoConsoleErrors,
  openApp,
} from './_helpers';
import { enterText } from './_journeys';

test('wealth ranges support pointer, keyboard and resizing with real balances', async ({ page }) => {
  const spy = attachConsoleSpy(page);
  await openApp(page, '/wealth/accounts');
  await page.getByRole('button', { name: 'New account', exact: true }).first().click();
  await enterText(page, 'Account name', 'Range savings');
  await page.getByRole('button', { name: 'Save', exact: true }).click();
  await page.getByRole('button', { name: /^Range savings CNY / }).click();
  await page.getByRole('button', { name: 'Add cash balance', exact: true }).click();
  await enterText(page, 'Balance *', '12500');
  await page.getByRole('button', { name: 'Save', exact: true }).click();
  await expect(page.getByRole('textbox', { name: 'Balance *', exact: true })).toHaveCount(0);
  await openApp(page, '/wealth');

  const range = (label: string) => page.getByRole('button', {
    name: `Wealth trend: ${label}`,
    exact: true,
  });
  await expect(range('1Y')).toHaveAttribute('aria-current', 'true');
  await range('3M').click();
  await expect(range('3M')).toHaveAttribute('aria-current', 'true');
  await expect(range('3M')).toBeFocused();
  await expect(range('1Y')).toHaveAttribute('aria-current', 'false');
  await page.keyboard.press('ArrowRight');
  await expect(range('1Y')).toHaveAttribute('aria-current', 'true');
  await page.keyboard.press('End');
  await expect(range('All')).toHaveAttribute('aria-current', 'true');

  await page.setViewportSize({ width: 320, height: 844 });
  for (const label of ['1M', '3M', '1Y', '3Y', 'All']) {
    await expect(range(label)).toBeVisible();
    const bounds = await range(label).boundingBox();
    expect(bounds!.width).toBeGreaterThanOrEqual(48);
    expect(bounds!.height).toBeGreaterThanOrEqual(48);
  }
  await page.keyboard.press('Home');
  await expect(range('1M')).toHaveAttribute('aria-current', 'true');
  await page.setViewportSize({ width: 1200, height: 900 });
  await page.keyboard.press('ArrowLeft');
  await expect(range('All')).toHaveAttribute('aria-current', 'true');
  await expectNoConsoleErrors(spy);
});
