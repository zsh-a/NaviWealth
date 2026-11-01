import { expect, test } from './_app';

import { attachConsoleSpy, expectNoConsoleErrors, openApp } from './_helpers';

test('record filter preview stays local until applied', async ({ page }) => {
  const spy = attachConsoleSpy(page);
  await openApp(page, '/activity');
  await expect(page.getByRole('banner', { name: 'Records', exact: true })).toBeVisible();
  const initialURL = page.url();

  await page.getByRole('button', { name: 'Filter', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Show 0 results', exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Income', exact: true }).click();
  await expect(page).toHaveURL(initialURL);
  await page.getByRole('button', { name: 'Cancel', exact: true }).click();
  await expect(page).toHaveURL(initialURL);

  await page.getByRole('button', { name: 'Filter', exact: true }).click();
  await page.getByRole('button', { name: 'Income', exact: true }).click();
  await page.getByRole('button', { name: 'Show 0 results', exact: true }).click();
  await expect(page).toHaveURL(/kinds=income/);
  await expect(page.getByLabel('No activity matches these filters.', { exact: true })).toBeVisible();
  await expectNoConsoleErrors(spy);
});
