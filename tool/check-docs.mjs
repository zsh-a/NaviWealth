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
  path.join(repoRoot, 'apps/nsh-client/README.md'),
  path.join(repoRoot, 'apps/nsh-client/DESIGN.md'),
  path.join(repoRoot, 'tool/asset_catalog/README.md'),
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
  if (file.includes(`${path.sep}adr${path.sep}`)) continue;
  const source = fs.readFileSync(file, 'utf8');
  for (const match of source.matchAll(
    /`((?:apps\/nsh-client|crates|tool|\.github\/workflows|assets\/catalog|third_party\/agent-runtime)\/[^`]+)`/g,
  )) {
    const target = match[1];
    if (/[<*>\s]/.test(target)) continue;
    if (!fs.existsSync(path.join(repoRoot, target))) {
      failures.push(`${relative(file)}: missing code authority ${target}`);
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
