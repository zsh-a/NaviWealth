#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import {pathToFileURL} from 'node:url';

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

// Deliberately scoped to maintained first-party entry points and the docs tree.
// Third-party README files describe their upstream projects, not this app.
export const entryPoints = [
  'README.md',
  'AGENTS.md',
  'CLAUDE.md',
  'llms.txt',
  'apps/nsh-client/README.md',
  'apps/nsh-client/DESIGN.md',
  'apps/nsh-client/android/README.md',
  'tool/asset_catalog/README.md',
];

export function checkDocs(repoRoot) {
  const markdownFiles = [
    ...entryPoints.map((name) => path.join(repoRoot, name)),
    ...walkMarkdown(path.join(repoRoot, 'docs')),
  ];
  const failures = [];
  const relative = (file) =>
    path.relative(repoRoot, file).replaceAll(path.sep, '/');

  for (const file of markdownFiles) {
    if (!fs.existsSync(file)) {
      failures.push(`missing documentation entry point ${relative(file)}`);
      continue;
    }
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

  for (const file of markdownFiles.filter((file) => fs.existsSync(file))) {
    const source = fs.readFileSync(file, 'utf8');
    for (const match of source.matchAll(
      /`((?:apps\/nsh-client|crates|tool|\.github\/workflows|third_party)\/[^`]+)`/g,
    )) {
      const target = match[1];
      if (/[<*>\s]/.test(target)) continue;
      if (!fs.existsSync(path.join(repoRoot, target))) {
        failures.push(`${relative(file)}: missing code authority ${target}`);
      }
    }
  }
  return {files: markdownFiles.length, failures};
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href
) {
  const {files, failures} = checkDocs(path.resolve(import.meta.dirname, '..'));
  if (failures.length > 0) {
    console.error(failures.map((failure) => `✖ ${failure}`).join('\n'));
    process.exitCode = 1;
  } else {
    console.log(`✓ documentation checks passed (${files} documentation files)`);
  }
}
