import { expect, test } from './_app';

import {
  attachConsoleSpy,
  enableFlutterSemantics,
  expectNoConsoleErrors,
  openApp,
} from './_helpers';
import { createNote, enableDomain, openDomainSettings } from './_journeys';

test('two tabs read records written by each other', async ({ page: tabA, context }) => {
  test.setTimeout(120_000);
  const spyA = attachConsoleSpy(tabA);
  await openDomainSettings(tabA);
  await enableDomain(tabA, 'KnowledgeOS');
  await openApp(tabA, '/knowledge');
  const firstPath = await createNote(tabA, 'First tab note', 'Written in the first tab.');

  const tabB = await context.newPage();
  const spyB = attachConsoleSpy(tabB);
  await openApp(tabB, firstPath);
  await expect(tabB.getByRole('group', { name: 'Written in the first tab.', exact: true })).toBeVisible();
  await openApp(tabB, '/knowledge');
  const secondPath = await createNote(tabB, 'Second tab note', 'Written in the second tab.');

  await openApp(tabA, secondPath);
  await expect(tabA.getByRole('group', { name: 'Written in the second tab.', exact: true })).toBeVisible();
  await tabB.close();
  await tabA.reload();
  await enableFlutterSemantics(tabA);
  await expect(tabA.getByRole('group', { name: 'Written in the second tab.', exact: true })).toBeVisible();
  await expectNoConsoleErrors(spyA);
  await expectNoConsoleErrors(spyB);
});
