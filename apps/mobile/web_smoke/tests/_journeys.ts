import { expect, type Page } from '@playwright/test';

import { openApp } from './_helpers';

export async function enableDomain(page: Page, name: 'KnowledgeOS' | 'ExecutionOS') {
  const control = page.getByRole('switch', { name, exact: true });
  await expect(control).not.toBeChecked();
  await control.click();
  await page.getByRole('button', { name: 'Later', exact: true }).click();
  await expect(control).toBeChecked();
  await expect(control).toBeEnabled();
}

export async function createNote(page: Page, title: string, content: string) {
  await page.getByRole('button', { name: 'Quick note', exact: true }).first().click();
  await enterText(page, 'Title (optional)', title);
  await enterText(page, 'Content (Markdown)', content);
  await page.getByRole('button', { name: 'Save', exact: true }).click();
  await expect(page.getByRole('textbox')).toHaveCount(0);
  await page.getByRole('button', { name: title }).click();
  await expect(page).toHaveURL(/\/knowledge\/library\/note\/[^/?]+$/);
  await expect(page.getByRole('group', { name: content, exact: true })).toBeVisible();
  return new URL(page.url()).pathname;
}

// A semantic textbox receives DOM focus before Flutter attaches its editing
// callbacks. Activation applies the editing style to that element, so wait
// for its inline font configuration before typing into a new form field.
export async function enterText(page: Page, name: string | RegExp, value: string) {
  const field = page.getByRole('textbox', { name, exact: typeof name === 'string' });
  await field.click();
  await expect(field).toBeFocused();
  await expect.poll(() => field.evaluate(element => (
    element as HTMLElement
  ).style.fontSize)).not.toBe('');
  await page.keyboard.insertText(value);
  await expect(field).toHaveValue(value);
}

export async function openDomainSettings(page: Page) {
  await openApp(page, '/settings/domains');
  await expect(page.getByRole('banner', { name: 'Domain management' })).toBeVisible();
}
