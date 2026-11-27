import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import {checkDocs, entryPoints} from '../check-docs.mjs';

test('checks first-party indexes and Android docs while excluding upstream docs', (t) => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'navi-docs-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  const write = (name, content) => {
    const file = path.join(root, name);
    fs.mkdirSync(path.dirname(file), {recursive: true});
    fs.writeFileSync(file, content);
  };
  for (const name of entryPoints) write(name, '# Documentation\n');
  write('docs/index.md', '[App](../apps/nsh-client/README.md)\n');
  write('third_party/upstream/README.md', '[Upstream guide](missing.md)\n');
  assert.deepEqual(checkDocs(root).failures, []);

  write('llms.txt', '[Architecture](docs/missing.md)\n');
  write('apps/nsh-client/android/README.md', '[Host](missing.md)\n');
  assert.deepEqual(checkDocs(root).failures, [
    'llms.txt: missing link target docs/missing.md',
    'apps/nsh-client/android/README.md: missing link target missing.md',
  ]);

  write('llms.txt', '`crates/missing/src/lib.rs`\n');
  write('apps/nsh-client/android/README.md', '# Host\n');
  assert.deepEqual(checkDocs(root).failures, [
    'llms.txt: missing code authority crates/missing/src/lib.rs',
  ]);

  write('llms.txt', '# Documentation\n');
  write('third_party/README.md', '[SDK](missing/README.md)\n');
  assert.deepEqual(checkDocs(root).failures, [
    'third_party/README.md: missing link target missing/README.md',
  ]);
});
