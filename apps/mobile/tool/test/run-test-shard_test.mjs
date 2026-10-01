import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {fileURLToPath} from 'node:url';

import {discoverTestFiles, parseArguments, selectTestShard} from '../run-test-shard.mjs';

test('four file shards are deterministic, disjoint, complete, and balanced', () => {
  const files = Array.from({length: 19}, (_, index) => `test/${index}_test.dart`);
  const shards = Array.from({length: 4}, (_, shardIndex) =>
    selectTestShard(files, {shardIndex, totalShards: 4}),
  );
  assert.deepEqual(shards.flat().sort(), [...files].sort());
  assert.equal(new Set(shards.flat()).size, files.length);
  assert.equal(Math.max(...shards.map((s) => s.length)) - Math.min(...shards.map((s) => s.length)), 1);
  assert.deepEqual(selectTestShard([...files].reverse(), {shardIndex: 2, totalShards: 4}), shards[2]);
});

test('inventory excludes only visual suites, screenshots, and non-test helpers', () => {
  const appRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'navi-test-inventory-'));
  try {
    const paths = [
      'test/core/unit_test.dart',
      'test/flow/task_test.dart',
      'test/features/golden_named_test.dart',
      'test/golden/nested/visual_test.dart',
      'test/readme_screenshots/screenshot_test.dart',
      'test/support/helper.dart',
      'test/performance_benchmark.dart',
    ];
    for (const relativePath of paths) {
      const file = path.join(appRoot, relativePath);
      fs.mkdirSync(path.dirname(file), {recursive: true});
      fs.writeFileSync(file, '');
    }
    assert.deepEqual(discoverTestFiles(appRoot), paths.slice(0, 3).sort());
  } finally {
    fs.rmSync(appRoot, {recursive: true, force: true});
  }
});

test('invalid, empty, or duplicated shards cannot silently pass', () => {
  const files = ['test/a_test.dart'];
  for (const [shardIndex, totalShards] of [[-1, 4], [4, 4], [0.5, 4], [0, 0], [0, 1.5], [NaN, 4], [0, Infinity]]) {
    assert.throws(() => selectTestShard(files, {shardIndex, totalShards}));
  }
  assert.throws(() => selectTestShard([], {shardIndex: 0, totalShards: 1}), /empty/);
  assert.throws(() => selectTestShard(files, {shardIndex: 1, totalShards: 4}), /empty/);
  assert.throws(() => selectTestShard([...files, ...files], {shardIndex: 0, totalShards: 1}), /duplicate/);
});

test('Flutter flags are passed separately and native case sharding is rejected', () => {
  assert.deepEqual(parseArguments(['--shard-index=2', '--total-shards=4', '--list', '--', '--concurrency=4']), {
    shardIndex: 2, totalShards: 4, list: true, flutterArgs: ['--concurrency=4'],
  });
  assert.throws(() => parseArguments(['--shard-index=2oops']), /unknown/);
  assert.throws(() => parseArguments(['--concurrency=4']), /unknown/);
  assert.throws(() => parseArguments(['--', '--total-shards=4']), /native/);
  assert.throws(() => parseArguments(['--', '--shard-index', '0']), /native/);
});

test('repository inventory assigns every regular test and token export exactly once', () => {
  const appRoot = fileURLToPath(new URL('../../', import.meta.url));
  const files = discoverTestFiles(appRoot);
  const shards = Array.from({length: 4}, (_, shardIndex) => selectTestShard(files, {shardIndex, totalShards: 4}));
  assert.deepEqual(shards.flat().sort(), files);
  assert.equal(new Set(shards.flat()).size, files.length);
  assert.equal(shards.filter((s) => s.includes('test/tools/export_design_tokens_test.dart')).length, 1);
});

test('CLI launches Flutter once with literal file/flag arguments and preserves failure', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'navi-shard-cli-'));
  try {
    const capture = path.join(directory, 'arguments.json');
    const flutter = path.join(directory, 'flutter');
    fs.writeFileSync(flutter, `#!${process.execPath}\nconst fs = require('node:fs');\nfs.writeFileSync(process.env.SHARD_ARGS_CAPTURE, JSON.stringify({cwd: process.cwd(), args: process.argv.slice(2)}));\nprocess.exit(9);\n`, {mode: 0o755});
    const runner = fileURLToPath(new URL('../run-test-shard.mjs', import.meta.url));
    const literalName = 'name with spaces $(do-not-execute)';
    const result = spawnSync(process.execPath, [runner, '--shard-index=1', '--total-shards=4', '--', '--name', literalName], {
      cwd: directory,
      env: {...process.env, PATH: `${directory}${path.delimiter}${process.env.PATH}`, SHARD_ARGS_CAPTURE: capture},
      encoding: 'utf8',
    });
    assert.equal(result.status, 9, result.stderr);
    const invocation = JSON.parse(fs.readFileSync(capture, 'utf8'));
    const appRoot = fileURLToPath(new URL('../../', import.meta.url));
    const selected = selectTestShard(discoverTestFiles(appRoot), {shardIndex: 1, totalShards: 4});
    assert.equal(invocation.cwd, appRoot.replace(/\/$/, ''));
    assert.deepEqual(invocation.args, ['test', ...selected, '--exclude-tags=golden', '--name', literalName]);
  } finally {
    fs.rmSync(directory, {recursive: true, force: true});
  }
});
