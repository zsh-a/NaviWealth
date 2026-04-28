import { type ConsoleMessage, type Page, expect } from '@playwright/test';

// Drift logs the chosen WasmDatabase implementation in debug builds. We
// build the smoke target with --release, which suppresses kDebugMode logs,
// so we can't rely on the textual line. Instead we infer the choice from
// the storage origin after the app has had a chance to open the DB — see
// `detectDriftImpl` below.

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
 * has started rendering. Either is sufficient evidence of a live app.
 */
export async function waitForFlutterReady(page: Page) {
  await page.waitForSelector(
    'flt-glass-pane, flutter-view, flt-scene-host',
    { timeout: 30_000 },
  );
  // Give the first frame a moment to paint so screenshots / nav clicks
  // don't race the initial route.
  await page.waitForTimeout(500);
}

/**
 * Drift's WasmDatabase persists per `databaseName` ("naviwealth"). We can
 * observe which storage implementation was chosen by inspecting the
 * IndexedDB databases the app created.
 *
 * Returns one of: 'opfs', 'sharedIndexedDb', 'unsafeIndexedDb', 'inMemory',
 * 'unknown'. Anything other than 'inMemory' / 'unknown' counts as
 * persistent for our assertions.
 */
export async function detectDriftImpl(page: Page): Promise<string> {
  return await page.evaluate(async () => {
    // OPFS: drift creates an entry under the storage root for our DB.
    // We can't always async-iterate FileSystemDirectoryHandle (the iter
    // protocol isn't uniform across engines yet), so probe via the
    // public entries() iterator and fall back to a direct lookup.
    if (
      typeof navigator !== 'undefined' &&
      navigator.storage &&
      typeof (navigator.storage as { getDirectory?: () => Promise<unknown> })
        .getDirectory === 'function'
    ) {
      try {
        const root = (await (
          navigator.storage as { getDirectory: () => Promise<unknown> }
        ).getDirectory()) as {
          entries?: () => AsyncIterable<[string, unknown]>;
          getDirectoryHandle?: (
            name: string,
            options?: { create?: boolean },
          ) => Promise<unknown>;
          getFileHandle?: (
            name: string,
            options?: { create?: boolean },
          ) => Promise<unknown>;
        };
        if (typeof root.entries === 'function') {
          for await (const [name] of root.entries()) {
            if (name.includes('naviwealth')) return 'opfs';
          }
        }
        if (root.getDirectoryHandle) {
          try {
            await root.getDirectoryHandle('naviwealth', { create: false });
            return 'opfs';
          } catch {
            /* not OPFS-backed */
          }
        }
      } catch {
        /* OPFS not available in this context — fall through */
      }
    }
    // IndexedDB: drift creates a DB whose name embeds our `databaseName`.
    // We don't distinguish shared vs unsafe — either is a persistent path
    // and acceptable for the smoke (Firefox lands here per FIR-40 §4.1).
    if (typeof indexedDB !== 'undefined' && 'databases' in indexedDB) {
      try {
        const dbs = await (
          indexedDB as unknown as { databases: () => Promise<{ name?: string }[]> }
        ).databases();
        if (dbs.some((d) => (d.name ?? '').includes('naviwealth'))) {
          return 'sharedIndexedDb';
        }
      } catch {
        /* Some browsers (older Safari) don't expose .databases() */
      }
    }
    return 'unknown';
  });
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
