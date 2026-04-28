// Tiny static file server for the Flutter web build under test.
//
// We need a real server (not file://) for: Service Worker registration,
// IndexedDB origin partitioning, Drift's worker, and SPA fallback for
// PathUrlStrategy deep links. Unknown paths that don't look like files
// fall back to index.html so go_router routes resolve client-side.
//
// COOP/COEP headers are intentionally NOT set: drift's WasmDatabase.open
// works fine without cross-origin isolation (it picks `sharedIndexedDb`
// instead of OPFS+SharedArrayBuffer). The smoke explicitly asserts the
// chosen impl is in the supported set; we don't need OPFS to pass.

import http from 'node:http';
import { promises as fs } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const buildDir = path.resolve(
  __dirname,
  process.env.WEB_BUILD_DIR ?? '../build/web',
);
const port = Number(process.env.PORT ?? 4173);

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.mjs': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.webmanifest': 'application/manifest+json',
  '.map': 'application/json',
};

async function send(res, filePath, status = 200) {
  const ext = path.extname(filePath).toLowerCase();
  const body = await fs.readFile(filePath);
  res.writeHead(status, {
    'content-type': MIME[ext] ?? 'application/octet-stream',
    'cache-control': 'no-cache',
  });
  res.end(body);
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url ?? '/', `http://127.0.0.1:${port}`);
    let rel = decodeURIComponent(url.pathname);
    if (rel === '/' || rel === '') rel = '/index.html';
    const target = path.join(buildDir, rel);
    // Guard against ../ escape.
    if (!target.startsWith(buildDir)) {
      res.writeHead(403);
      res.end('forbidden');
      return;
    }
    try {
      const stat = await fs.stat(target);
      if (stat.isDirectory()) {
        await send(res, path.join(target, 'index.html'));
      } else {
        await send(res, target);
      }
    } catch {
      // SPA fallback: paths without an extension are go_router routes.
      if (!path.extname(rel)) {
        await send(res, path.join(buildDir, 'index.html'));
      } else {
        res.writeHead(404);
        res.end('not found');
      }
    }
  } catch (err) {
    res.writeHead(500);
    res.end(String(err));
  }
});

server.listen(port, '127.0.0.1', () => {
  // eslint-disable-next-line no-console
  console.log(`web_smoke: serving ${buildDir} on http://127.0.0.1:${port}`);
});
