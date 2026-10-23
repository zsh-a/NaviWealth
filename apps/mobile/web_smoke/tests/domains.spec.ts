import { expect, test } from './_app';
import { attachConsoleSpy, enableFlutterSemantics, expectNoConsoleErrors, openApp } from './_helpers';
import { createNote, enableDomain, enterText } from './_journeys';

test.use({ viewport: { width: 390, height: 844 } });

test('optional domains, record details, and workspace navigation survive reload', async ({ page }) => {
  test.setTimeout(120_000);
  const spy = attachConsoleSpy(page);
  // A deep link cannot expose an inactive domain.
  await openApp(page, '/knowledge');
  await expect(page).toHaveURL(/\/settings\/domains\?blocked=knowledge$/);
  await enableDomain(page, 'KnowledgeOS');
  await enableDomain(page, 'ExecutionOS');
  await expect(page.getByRole('switch', { name: 'HealthOS', exact: true })).not.toBeChecked();
  await openApp(page, '/knowledge');

  const content = 'Review the household spending assumptions before the next decision.';
  const notePath = await createNote(page, 'Browser review note', content);
  await page.reload();
  await enableFlutterSemantics(page);
  await expect(page).toHaveURL(new RegExp(`${notePath}$`));
  await expect(page.getByRole('group', { name: content, exact: true })).toBeVisible();

  await page.getByRole('button', { name: 'Go back', exact: true }).click();
  await page.getByRole('button', { name: 'Knowledge', exact: true }).click();
  await page.getByRole('button', { name: 'Execution', exact: true }).click();
  await expect(page).toHaveURL(/\/execution$/);
  await page.getByRole('button', { name: 'New Action', exact: true }).first().click();
  await enterText(page, /^Action(?: |$)/, 'Review browser note');
  await page.getByRole('button', { name: 'Today', exact: true }).click();
  await page.getByRole('button', { name: 'Save', exact: true }).click();
  await page.getByRole('button', { name: /^Review browser note/ }).click();
  await expect(page).toHaveURL(/\/execution\/action\/[^/?]+$/);
  const actionPath = new URL(page.url()).pathname;
  await page.reload();
  await enableFlutterSemantics(page);
  await expect(page).toHaveURL(new RegExp(`${actionPath}$`));
  await expect(page.getByText('Review browser note')).toBeVisible();
  await expectNoConsoleErrors(spy);
});
