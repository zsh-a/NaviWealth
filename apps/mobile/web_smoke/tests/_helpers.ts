import { type ConsoleMessage, type Page, expect } from '@playwright/test';

/**
 * Errors that are noisy on real Flutter web builds but don't indicate an
 * actual problem. Keep this list as small as possible — every entry is a
 * hole in the smoke. Be specific (substring match) so we don't suppress
 * something we'd want to see fail.
 */
const ALLOWED_CONSOLE_NOISE: RegExp[] = [
  // Flutter's renderer probe announces the chosen renderer (canvaskit/skwasm).
  /Using the .* renderer/i,
  // Flutter sometimes logs an info line when the SW updates the cache.
  /service worker.*update/i,
  // Firefox/Playwright can report an internal juggler worker cancellation
  // during rapid history navigation; it is not emitted by the app page.
  /NS_BINDING_ABORTED: .*chrome:\/\/juggler\/content\/content\/WorkerMain\.js/i,
];

export function attachConsoleSpy(page: Page) {
  const messages: { type: string; text: string }[] = [];
  const pageErrorMessages: string[] = [];
  page.on('console', (msg: ConsoleMessage) => {
    messages.push({ type: msg.type(), text: msg.text() });
  });
  page.on('pageerror', (err) => {
    pageErrorMessages.push(err.message);
  });
  return {
    messages,
    pageErrorMessages,
    errors() {
      return messages.filter(
        (m) =>
          m.type === 'error' &&
          !ALLOWED_CONSOLE_NOISE.some((p) => p.test(m.text)),
      );
    },
  };
}

/**
 * Waits for the Flutter glass-pane element. Flutter web mounts a
 * `<flt-glass-pane>` (CanvasKit) or `<flutter-view>` host once the engine
 * has started rendering. This proves engine startup only; each test must
 * also assert the business content it expects to see.
 */
export async function waitForFlutterReady(page: Page) {
  await page.waitForSelector(
    'flt-glass-pane, flutter-view, flt-scene-host',
    { timeout: 30_000 },
  );
}

/** Enable Flutter's accessibility tree, then use normal role/text locators. */
export async function enableFlutterSemantics(page: Page) {
  await waitForFlutterReady(page);
  await page.locator('flt-semantics-placeholder, flt-semantics').first()
    .waitFor({ state: 'attached' });
  const placeholder = page.locator('flt-semantics-placeholder');
  if (await placeholder.count()) {
    await placeholder.evaluate((element: HTMLElement) => element.click());
  }
}

export async function openApp(page: Page, route: string) {
  await page.goto(route);
  await enableFlutterSemantics(page);
}


export async function expectNoConsoleErrors(spy: ReturnType<typeof attachConsoleSpy>) {
  const errs = spy.errors();
  expect(
    errs,
    `unexpected console errors:\n${errs.map((e) => e.text).join('\n')}`,
  ).toEqual([]);
  expect(
    spy.pageErrorMessages,
    `unhandled page errors:\n${spy.pageErrorMessages.join('\n')}`,
  ).toEqual([]);
}
