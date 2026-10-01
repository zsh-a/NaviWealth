#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import {fileURLToPath, pathToFileURL} from 'node:url';

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
  const testFiles = new Map();

  function fileTiming(url) {
    if (!testFiles.has(url)) {
      testFiles.set(url, {url, completed: 0, loadingMs: 0, caseMs: 0});
    }
    return testFiles.get(url);
  }

  for (const file of files) {
    const starts = new Map();
    const suites = new Map();
    const loadedFiles = new Set();
    let maxTimeMs = 0;
    let completed = 0;
    let skipped = 0;
    let loadingMs = 0;
    let outcome = 'incomplete';
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
      if (event.type === 'done') {
        outcome = event.success === true ? 'passed' : 'failed';
      }
      if (event.type === 'suite' && event.suite?.path) {
        suites.set(event.suite.id, pathToFileURL(event.suite.path).href);
      }
      if (event.type === 'testStart' && event.test) {
        const url = suites.get(event.test.suiteID) ?? event.test.url ?? '';
        const isLoading = !event.test.url && event.test.name?.startsWith('loading ');
        if (isLoading && url) loadedFiles.add(url);
        starts.set(event.test.id, {
          name: event.test.name ?? `test ${event.test.id}`,
          // Widget test URLs point into flutter_test. suiteID identifies the
          // owning repository file for both widget and ordinary Dart tests.
          url,
          startMs: event.time ?? 0,
          isLoading,
          skipped: event.test.metadata?.skip ?? false,
        });
      }
      if (event.type === 'testDone') {
        const start = starts.get(event.testID);
        if (!start) continue;
        starts.delete(event.testID);
        const durationMs = Math.max(0, (event.time ?? start.startMs) - start.startMs);
        if (start.isLoading) {
          loadingMs += durationMs;
          if (start.url) fileTiming(start.url).loadingMs += durationMs;
          continue;
        }
        if (event.hidden && event.result === 'success') continue;
        if (event.skipped || start.skipped) {
          skipped += 1;
          continue;
        }
        if (!start.url) continue;
        completed += 1;
        const timing = fileTiming(start.url);
        timing.completed += 1;
        timing.caseMs += durationMs;
        tests.push({
          ...start,
          durationMs,
          result: event.result ?? 'unknown',
          shard: path.basename(file),
        });
      }
    }
    shards.push({file: path.basename(file), completed, skipped, loadedFiles: loadedFiles.size, loadingMs, wallTimeMs: maxTimeMs, outcome});
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
    slowestFiles: [...testFiles.values()]
      .sort((a, b) => (b.loadingMs + b.caseMs) - (a.loadingMs + a.caseMs))
      .slice(0, slowestCount),
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
    const file = fileURLToPath(url);
    const testRoot = file.lastIndexOf('/test/');
    return testRoot >= 0 ? file.slice(testRoot + 1) : path.relative(process.cwd(), file) || url;
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
    '| Shard | Outcome | Loaded files | Tests | Skipped | Wall time (s) | Loading sum (s) |',
    '|---|---|---:|---:|---:|---:|---:|',
    ...summary.shards.map(
      (shard) =>
        `| ${shard.file} | ${shard.outcome} | ${shard.loadedFiles} | ${shard.completed} | ${shard.skipped} | ${seconds(shard.wallTimeMs)} | ${seconds(shard.loadingMs)} |`,
    ),
    '',
    'Loading and case durations are cumulative and may overlap; only shard wall time measures elapsed runtime.',
    '',
    '### Slowest files (loading + cases)',
    '',
    '| File | Tests | Loading sum (s) | Case sum (s) |',
    '|---|---:|---:|---:|',
    ...summary.slowestFiles.map(
      (file) => `| ${displayUrl(file.url)} | ${file.completed} | ${seconds(file.loadingMs)} | ${seconds(file.caseMs)} |`,
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
