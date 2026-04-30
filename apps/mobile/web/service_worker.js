// NaviWealth custom service worker.
//
// Why custom: Flutter's auto-generated `flutter_service_worker.js` only does
// asset precache + cache-first. We need three different strategies for three
// different traffic patterns (offline shell, API, WASM), plus an explicit
// update-available channel back to the Flutter app. Build with
// `flutter build web --pwa-strategy=none` so this file is the only SW served.
//
// Cache layout (versioned via SW_VERSION — bump on shell change):
//   shell-v{n}    Cache-First. App shell + Flutter bootstrap/main chunks.
//   wasm-v{n}     Cache-First, long-lived. sqlite3.wasm, drift_worker.dart.js.
//   runtime-v{n}  Stale-While-Revalidate. Other same-origin assets (fonts,
//                 icons, hashed chunks) discovered at runtime.
//   api-v{n}      Network-First fallback cache for GET /api responses.

'use strict';

// Bump on any shell-affecting change. Old caches are deleted on activate.
const SW_VERSION = 'v1';

const CACHES = {
  shell: `nw-shell-${SW_VERSION}`,
  wasm: `nw-wasm-${SW_VERSION}`,
  runtime: `nw-runtime-${SW_VERSION}`,
  api: `nw-api-${SW_VERSION}`,
};

// Pre-cached on install. Anything else is filled lazily by runtime strategies.
// Hashed assets (e.g. main.dart.js?v=…) are caught by the runtime handler;
// listing only the unhashed entrypoints keeps install lightweight and avoids
// 404 churn when Flutter renames chunks between builds.
const SHELL_PRECACHE = [
  './',
  'index.html',
  'manifest.json',
  'flutter_bootstrap.js',
  'favicon.png',
  'icons/Icon-192.png',
  'icons/Icon-512.png',
  'icons/Icon-maskable-192.png',
  'icons/Icon-maskable-512.png',
];

// API requests that should use Network-First with cache fallback.
// Backend routes (Cloudflare Workers): /auth/*, /sync/*, /ai/*, /health*, /me.
// Only same-origin requests can be intercepted; cross-origin (workers.dev)
// requests pass through to the network directly.
function isApiRequest(url) {
  if (url.origin !== self.location.origin) return false;
  const p = url.pathname;
  return (
    p.startsWith('/auth/') ||
    p.startsWith('/sync/') ||
    p.startsWith('/ai/') ||
    p.startsWith('/health') ||
    p === '/me'
  );
}

function isWasmAsset(url) {
  if (url.origin !== self.location.origin) return false;
  const p = url.pathname;
  return (
    p.endsWith('/sqlite3.wasm') ||
    p.endsWith('/drift_worker.dart.js') ||
    p.endsWith('.wasm')
  );
}

function isShellAsset(url) {
  if (url.origin !== self.location.origin) return false;
  const p = url.pathname;
  return (
    p.endsWith('/') ||
    p.endsWith('/index.html') ||
    p.endsWith('/flutter_bootstrap.js') ||
    p.endsWith('/manifest.json')
  );
}

function isRuntimeCacheable(request, url) {
  if (request.method !== 'GET') return false;
  if (url.origin !== self.location.origin) return false;
  // Skip range requests — partial responses don't survive Cache.put.
  if (request.headers.get('range')) return false;
  return true;
}

self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(CACHES.shell);
      // addAll is atomic; if any URL 404s nothing is cached. Use Promise.all
      // over individual put()s so a single missing icon doesn't break install.
      await Promise.all(
        SHELL_PRECACHE.map(async (url) => {
          try {
            const res = await fetch(url, { cache: 'reload' });
            if (res && res.ok) await cache.put(url, res.clone());
          } catch (_) {
            // Network failures during install are non-fatal — runtime fetch
            // will fill the cache on first successful load.
          }
        }),
      );
      // Don't auto-activate; the page decides when via SKIP_WAITING. This is
      // what lets us show the user a "refresh to update" prompt instead of
      // swapping JS under their feet mid-session.
    })(),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const valid = new Set(Object.values(CACHES));
      const names = await caches.keys();
      await Promise.all(
        names.map((name) => {
          if (name.startsWith('nw-') && !valid.has(name)) {
            return caches.delete(name);
          }
          return undefined;
        }),
      );
      await self.clients.claim();
      // Tell every visible client a new SW just took over so the Dart side
      // can decide whether to surface a "new version available" banner. The
      // banner is actually surfaced earlier from the page (waiting worker
      // detected), this just confirms activation completed.
      const clients = await self.clients.matchAll({ includeUncontrolled: true });
      for (const client of clients) {
        client.postMessage({ type: 'SW_ACTIVATED', version: SW_VERSION });
      }
    })(),
  );
});

self.addEventListener('message', (event) => {
  const data = event.data;
  if (!data || typeof data !== 'object') return;
  if (data.type === 'SKIP_WAITING') {
    self.skipWaiting();
  } else if (data.type === 'GET_VERSION') {
    if (event.source && 'postMessage' in event.source) {
      event.source.postMessage({ type: 'SW_VERSION', version: SW_VERSION });
    }
  }
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;

  let url;
  try {
    url = new URL(request.url);
  } catch (_) {
    return;
  }

  // Only handle http(s) — chrome-extension://, blob:, data: are passthrough.
  if (url.protocol !== 'http:' && url.protocol !== 'https:') return;

  if (request.mode === 'navigate') {
    event.respondWith(handleNavigate(request));
    return;
  }
  if (isApiRequest(url)) {
    event.respondWith(handleApi(request));
    return;
  }
  if (isWasmAsset(url)) {
    event.respondWith(handleWasm(request));
    return;
  }
  if (isShellAsset(url)) {
    event.respondWith(handleShell(request));
    return;
  }
  if (isRuntimeCacheable(request, url)) {
    event.respondWith(handleRuntime(request));
  }
});

// SPA navigation: always serve index.html so go_router can pick up the route.
// Network-first so a fresh deploy is picked up on next navigation, but fall
// back to cached shell when offline.
async function handleNavigate(request) {
  const cache = await caches.open(CACHES.shell);
  try {
    const network = await fetch(request);
    if (network && network.ok) {
      // Update the shell entry so subsequent offline loads see the latest.
      cache.put('index.html', network.clone()).catch(() => {});
      return network;
    }
  } catch (_) {
    // fall through to cache
  }
  const cached =
    (await cache.match('index.html')) ||
    (await cache.match('./')) ||
    (await caches.match(request));
  if (cached) return cached;
  return new Response(
    '<h1>NaviWealth offline</h1><p>App shell unavailable. Please reconnect and reload.</p>',
    { status: 503, headers: { 'Content-Type': 'text/html; charset=utf-8' } },
  );
}

// Cache-First for shell assets: index.html / bootstrap / manifest. We refresh
// in the background so the next reload sees the new version, then prompt.
async function handleShell(request) {
  const cache = await caches.open(CACHES.shell);
  const cached = await cache.match(request);
  const networkPromise = fetch(request)
    .then((res) => {
      if (res && res.ok) cache.put(request, res.clone()).catch(() => {});
      return res;
    })
    .catch(() => undefined);
  if (cached) return cached;
  const network = await networkPromise;
  if (network) return network;
  return new Response('', { status: 504 });
}

// Cache-First, long-lived. WASM modules are large and hash-busted by URL.
async function handleWasm(request) {
  const cache = await caches.open(CACHES.wasm);
  const cached = await cache.match(request);
  if (cached) return cached;
  try {
    const network = await fetch(request);
    if (network && network.ok) cache.put(request, network.clone()).catch(() => {});
    return network;
  } catch (err) {
    if (cached) return cached;
    throw err;
  }
}

// Network-First with cache fallback for API GETs. Non-GET (mutations) skip
// caching entirely so writes never silently 304 from a stale cache.
// Coordinates with FIR-26's dio cache layer, which owns request-level TTL /
// staleness; this layer only kicks in when the network is fully unreachable.
async function handleApi(request) {
  const cache = await caches.open(CACHES.api);
  try {
    const network = await fetch(request);
    if (network && network.ok && network.type !== 'opaque') {
      cache.put(request, network.clone()).catch(() => {});
    }
    return network;
  } catch (err) {
    const cached = await cache.match(request);
    if (cached) {
      // Tag offline-served responses so dio can surface "stale data" UI.
      const headers = new Headers(cached.headers);
      headers.set('X-NaviWealth-Offline', '1');
      return new Response(await cached.clone().blob(), {
        status: cached.status,
        statusText: cached.statusText,
        headers,
      });
    }
    throw err;
  }
}

// Stale-While-Revalidate for the runtime asset bucket: hashed JS chunks,
// fonts, icons. Returns cached response immediately and refreshes in the
// background so next load is fresh without blocking the current one.
async function handleRuntime(request) {
  const cache = await caches.open(CACHES.runtime);
  const cached = await cache.match(request);
  const networkPromise = fetch(request)
    .then((res) => {
      if (res && res.ok && res.type !== 'opaque') {
        cache.put(request, res.clone()).catch(() => {});
      }
      return res;
    })
    .catch(() => undefined);
  if (cached) {
    networkPromise.catch(() => {});
    return cached;
  }
  const network = await networkPromise;
  if (network) return network;
  return new Response('', { status: 504 });
}
