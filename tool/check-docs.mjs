#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const repoRoot = path.resolve(import.meta.dirname, '..');
const docsRoot = path.join(repoRoot, 'docs');

function walkMarkdown(directory) {
  return fs.readdirSync(directory, {withFileTypes: true}).flatMap((entry) => {
    const target = path.join(directory, entry.name);
    return entry.isDirectory()
      ? walkMarkdown(target)
      : entry.name.endsWith('.md')
        ? [target]
        : [];
  });
}

function relative(file) {
  return path.relative(repoRoot, file).replaceAll(path.sep, '/');
}

const markdownFiles = [
  path.join(repoRoot, 'README.md'),
  path.join(repoRoot, 'CLAUDE.md'),
  path.join(repoRoot, 'apps/mobile/README.md'),
  ...walkMarkdown(docsRoot),
];
const failures = [];

for (const file of markdownFiles) {
  const source = fs.readFileSync(file, 'utf8');
  for (const match of source.matchAll(/!?\[[^\]]*\]\(([^)]+)\)/g)) {
    const rawTarget = match[1].replace(/\s+".*"$/, '');
    const target = rawTarget.split('#', 1)[0];
    if (!target || /^(?:https?:|mailto:)/.test(target)) continue;
    const resolved = path.resolve(path.dirname(file), target);
    if (!fs.existsSync(resolved)) {
      failures.push(`${relative(file)}: missing link target ${target}`);
    }
  }
}

const mkdocs = fs.readFileSync(path.join(repoRoot, 'mkdocs.yml'), 'utf8');
for (const match of mkdocs.matchAll(/^\s+-\s+[^:]+:\s+(\S+\.md)$/gm)) {
  const target = path.join(docsRoot, match[1]);
  if (!fs.existsSync(target)) {
    failures.push(`mkdocs.yml: missing nav target ${match[1]}`);
  }
}

for (const file of markdownFiles) {
  const source = fs.readFileSync(file, 'utf8');
  for (const match of source.matchAll(
    /`((?:apps\/mobile\/lib|apps\/mobile\/native\/lifeos_native\/src|apps\/backend\/src|tool|\.github\/workflows)\/[^`]+)`/g,
  )) {
    const target = match[1];
    if (/[<*>\s]/.test(target)) continue;
    if (!fs.existsSync(path.join(repoRoot, target))) {
      failures.push(`${relative(file)}: missing code authority ${target}`);
    }
  }

  for (const block of source.matchAll(/```[^\n]*\n([\s\S]*?)```/g)) {
    let codeRoot;
    for (const line of block[1].split('\n')) {
      if (/^apps\/(?:mobile|backend)\/\S+\/$/.test(line)) {
        codeRoot = line;
      } else if (codeRoot) {
        const entry = line.match(/^ {2}(\S+\.(?:dart|rs|kt|cpp))\s/);
        if (!entry || /[<*>]/.test(entry[1])) continue;
        const target = path.join(codeRoot, entry[1]);
        if (!fs.existsSync(path.join(repoRoot, target))) {
          failures.push(`${relative(file)}: missing code-map file ${target}`);
        }
      }
    }
  }
}

const staleReferences = new Map([
  ['Sync is v2', 'Sync v3 is the active protocol'],
  ['v2 row-state', 'Sync v3 is the active protocol'],
  [
    'apps/mobile/lib/app/route_error_page.dart',
    'RouteErrorPage lives under core/shell',
  ],
  [
    'apps/mobile/lib/data/db/connection_web.dart',
    'the Web connection lives under core/persistence',
  ],
  [
    'apps/backend/src/routes/market/options.rs',
    'the Backend has no options route',
  ],
]);

for (const file of markdownFiles) {
  const source = fs.readFileSync(file, 'utf8');
  for (const [needle, reason] of staleReferences) {
    if (source.includes(needle)) {
      failures.push(`${relative(file)}: stale reference "${needle}"; ${reason}`);
    }
  }
}

if (failures.length > 0) {
  console.error(failures.map((failure) => `✖ ${failure}`).join('\n'));
  process.exit(1);
}

console.log(
  `✓ documentation checks passed (${markdownFiles.length} Markdown files)`,
);
