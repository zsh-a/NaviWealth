import { expect, test } from '@playwright/test';

// PWA install itself can't be driven headlessly — that's the manual
// checklist's job (web-compat-matrix.md §3.4). What we *can* check is
// that the prerequisites for installability are present and well-formed:
// the linked manifest, the icon set, and the meta tags iOS Safari needs.

test.describe('PWA prerequisites', () => {
  test('index.html declares the manifest and iOS install meta tags', async ({
    page,
    baseURL,
  }) => {
    const res = await page.request.get(`${baseURL}/index.html`);
    expect(res.status()).toBe(200);
    const html = await res.text();

    expect(html, 'must link manifest.json').toMatch(
      /<link\s+[^>]*rel=["']manifest["'][^>]*href=["']manifest\.json["']/i,
    );
    expect(html, 'must declare apple-mobile-web-app-capable').toMatch(
      /name=["']apple-mobile-web-app-capable["'][^>]*content=["']yes["']|name=["']mobile-web-app-capable["'][^>]*content=["']yes["']/i,
    );
    expect(html, 'must declare an apple-touch-icon').toMatch(
      /<link\s+[^>]*rel=["']apple-touch-icon["'][^>]*sizes=["']180x180["']/i,
    );
    expect(html, 'must disable telephone auto-linking').toMatch(
      /name=["']format-detection["'][^>]*content=["']telephone=no["']/i,
    );
  });

  test('manifest declares the fields installers care about', async ({
    request,
    baseURL,
  }) => {
    const res = await request.get(`${baseURL}/manifest.json`);
    expect(res.status()).toBe(200);
    const m = await res.json();

    expect(m.name, 'name').toBeTruthy();
    expect(m.short_name, 'short_name').toBeTruthy();
    expect(m.start_url, 'start_url').toBeTruthy();
    expect(['standalone', 'fullscreen', 'minimal-ui']).toContain(m.display);
    expect(m.icons, 'icons').toBeInstanceOf(Array);

    const sizes = new Set<string>(
      m.icons.map((i: { sizes?: string }) => i.sizes ?? ''),
    );
    expect(sizes.has('192x192'), 'needs 192px icon').toBe(true);
    expect(sizes.has('512x512'), 'needs 512px icon').toBe(true);

    expect(
      (m.shortcuts as Array<{ url?: string }>).map((shortcut) => shortcut.url),
      'shortcuts must target canonical app routes',
    ).toEqual(['/wealth', '/activity/trade', '/plan']);

    // Maskable icons aren't strictly required, but missing them produces
    // an awkward letterboxed home-screen icon on Android. Treat as a
    // warning by annotation, not a failure.
    const hasMaskable = m.icons.some(
      (i: { purpose?: string }) =>
        typeof i.purpose === 'string' && i.purpose.includes('maskable'),
    );
    if (!hasMaskable) {
      test.info().annotations.push({
        type: 'warn',
        description: 'manifest has no maskable icon',
      });
    }
  });
});
