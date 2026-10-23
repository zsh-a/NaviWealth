import { test as base } from '@playwright/test';

// Each test gets a fresh browser context and a real local-only identity.
// This is the production preference read by AuthController, not an auth mock.
// Records and domain preferences are written through the UI and real Drift.
export const test = base.extend({
  context: async ({ context }, use) => {
    await context.addInitScript(() => {
      if (location.protocol !== 'http:' && location.protocol !== 'https:') return;
      if (localStorage.getItem('flutter.app.mode.v1') === null) {
        localStorage.setItem('flutter.app.mode.v1', JSON.stringify('local_only'));
      }
    });
    await use(context);
  },
});

export { expect } from '@playwright/test';
