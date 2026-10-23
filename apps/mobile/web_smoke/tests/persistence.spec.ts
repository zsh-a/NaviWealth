import { expect, test } from './_app';

import {
  attachConsoleSpy,
  enableFlutterSemantics,
  expectNoConsoleErrors,
  openApp,
} from './_helpers';
import { enterText } from './_journeys';

test('an account created through the UI survives a hard reload', async ({ page }) => {
  const spy = attachConsoleSpy(page);
  await openApp(page, '/wealth/accounts');
  await page.getByRole('button', { name: 'New account', exact: true }).first().click();
  await enterText(page, 'Account name', 'Browser savings');
  await page.getByRole('button', { name: 'Save', exact: true }).click();
  await expect(page.getByRole('textbox', { name: 'Account name', exact: true }))
    .toHaveCount(0);
  const account = page.getByRole('button', { name: /^Browser savings CNY / });
  await expect(account).toBeVisible();

  await page.reload();
  await enableFlutterSemantics(page);
  await expect(account).toBeVisible();
  await expectNoConsoleErrors(spy);
});
