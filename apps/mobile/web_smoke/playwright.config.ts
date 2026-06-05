import { defineConfig, devices } from '@playwright/test';

// Where the Flutter web release bundle lives. CI sets WEB_BUILD_DIR after
// downloading the `mobile-web-build` artifact; locally it defaults to the
// build/web output relative to this project.
const buildDir = process.env.WEB_BUILD_DIR ?? '../build/web';
const port = Number(process.env.WEB_SMOKE_PORT ?? 4173);
const baseURL = process.env.WEB_SMOKE_BASE_URL ?? `http://127.0.0.1:${port}`;

// Headless WebKit on Linux runners stands in for desktop Safari for the
// rendering / OPFS-fallback paths; real iOS Safari is covered by the
// manual checklist (see docs/web-compat-matrix.md §3.4).
export default defineConfig({
  testDir: './tests',
  timeout: 60_000,
  expect: { timeout: 10_000 },
  retries: process.env.CI ? 1 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: process.env.CI
    ? [['github'], ['html', { open: 'never' }], ['list']]
    : 'list',
  use: {
    baseURL,
    serviceWorkers: 'block',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
    {
      name: 'firefox',
      use: { ...devices['Desktop Firefox'] },
    },
    {
      name: 'webkit',
      use: { ...devices['Desktop Safari'] },
    },
  ],
  // Serve the static Flutter build with the right COOP/COEP headers so
  // OPFS (where supported) can pick the cross-origin-isolated path.
  webServer: process.env.WEB_SMOKE_BASE_URL
    ? undefined
    : {
        command: `node serve.mjs`,
        env: {
          WEB_BUILD_DIR: buildDir,
          PORT: String(port),
        },
        port,
        reuseExistingServer: !process.env.CI,
        stdout: 'pipe',
        stderr: 'pipe',
        timeout: 30_000,
      },
});
