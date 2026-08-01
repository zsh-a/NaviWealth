#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import {pathToFileURL} from 'node:url';

function jsonFiles(target) {
  const stat = fs.statSync(target);
  if (stat.isFile()) return target.endsWith('.json') ? [target] : [];
  return fs.readdirSync(target, {withFileTypes: true}).flatMap((entry) => {
    const child = path.join(target, entry.name);
    return entry.isDirectory()
      ? jsonFiles(child)
      : entry.name.endsWith('.json')
        ? [child]
        : [];
  });
}

export function summarizeTestEvents(targets, {slowestCount = 20} = {}) {
  const files = targets.flatMap(jsonFiles).sort();
  const tests = [];
  const shards = [];
  const warnings = [];

  for (const file of files) {
    const starts = new Map();
    let maxTimeMs = 0;
    let completed = 0;
    for (const [lineIndex, line] of fs
      .readFileSync(file, 'utf8')
      .split('\n')
      .entries()) {
      if (!line.trim()) continue;
      let event;
      try {
        event = JSON.parse(line);
      } catch {
        warnings.push(`${file}:${lineIndex + 1}: invalid JSON event`);
        continue;
      }
      if (typeof event.time === 'number') {
        maxTimeMs = Math.max(maxTimeMs, event.time);
      }
      if (event.type === 'testStart' && event.test) {
        starts.set(event.test.id, {
          name: event.test.name ?? `test ${event.test.id}`,
          url: event.test.url ?? '',
          startMs: event.time ?? 0,
        });
      }
      if (event.type === 'testDone') {
        const start = starts.get(event.testID);
        // The reporter emits a synthetic "loading <file>" test without a
        // URL. Its time is shard startup overhead, not an executable case;
        // retain it in wall time but exclude it from counts and rankings.
        if (!start || !start.url) continue;
        completed += 1;
        tests.push({
          ...start,
          durationMs: Math.max(0, (event.time ?? start.startMs) - start.startMs),
          result: event.result ?? 'unknown',
          shard: path.basename(file),
        });
      }
    }
    shards.push({file: path.basename(file), completed, wallTimeMs: maxTimeMs});
  }

  const resultCounts = new Map();
  for (const test of tests) {
    resultCounts.set(test.result, (resultCounts.get(test.result) ?? 0) + 1);
  }

  return {
    files,
    shards,
    tests,
    resultCounts,
    warnings,
    slowest: [...tests]
      .sort((a, b) => b.durationMs - a.durationMs)
      .slice(0, slowestCount),
  };
}

function seconds(milliseconds) {
  return (milliseconds / 1000).toFixed(2);
}

function displayUrl(url) {
  if (!url) return '—';
  try {
    return path.relative(process.cwd(), new URL(url).pathname) || url;
  } catch {
    return url;
  }
}

export function renderMarkdown(summary) {
  const counts = [...summary.resultCounts.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([result, count]) => `${result}: ${count}`)
    .join(', ');
  const lines = [
    '## Flutter test timing',
    '',
    `Parsed ${summary.tests.length} completed tests from ${summary.files.length} shard files${counts ? ` (${counts})` : ''}.`,
    '',
    '| Shard | Tests | Wall time (s) |',
    '|---|---:|---:|',
    ...summary.shards.map(
      (shard) =>
        `| ${shard.file} | ${shard.completed} | ${seconds(shard.wallTimeMs)} |`,
    ),
    '',
    '### Slowest tests',
    '',
    '| Test | File | Shard | Duration (s) | Result |',
    '|---|---|---|---:|---|',
    ...summary.slowest.map(
      (test) =>
        `| ${test.name.replaceAll('|', '\\|')} | ${displayUrl(test.url)} | ${test.shard} | ${seconds(test.durationMs)} | ${test.result} |`,
    ),
  ];
  if (summary.warnings.length > 0) {
    lines.push('', '### Parser warnings', '', ...summary.warnings.map((w) => `- ${w}`));
  }
  return `${lines.join('\n')}\n`;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const targets = process.argv.slice(2);
  if (targets.length === 0) {
    console.error('usage: summarize-test-events.mjs <json-file-or-directory> [...]');
    process.exit(64);
  }
  const summary = summarizeTestEvents(targets);
  if (summary.files.length === 0) {
    console.error('no JSON event files found');
    process.exit(1);
  }
  process.stdout.write(renderMarkdown(summary));
}
