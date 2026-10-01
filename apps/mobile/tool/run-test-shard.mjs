#!/usr/bin/env node

import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import {fileURLToPath, pathToFileURL} from 'node:url';

// These suites have separate visual gates or are generated manually.
const excludedDirectories = new Set(['test/golden', 'test/readme_screenshots']);

export function discoverTestFiles(appRoot) {
  function walk(relativeDirectory) {
    if (excludedDirectories.has(relativeDirectory)) return [];
    return fs
      .readdirSync(path.join(appRoot, relativeDirectory), {withFileTypes: true})
      .flatMap((entry) => {
        const relativePath = `${relativeDirectory}/${entry.name}`;
        if (entry.isDirectory()) return walk(relativePath);
        return entry.isFile() && entry.name.endsWith('_test.dart')
          ? [relativePath]
          : [];
      });
  }
  return walk('test').sort();
}

export function selectTestShard(files, {shardIndex, totalShards}) {
  if (!Number.isSafeInteger(totalShards) || totalShards < 1) {
    throw new Error('total-shards must be a positive integer');
  }
  if (!Number.isSafeInteger(shardIndex) || shardIndex < 0 || shardIndex >= totalShards) {
    throw new Error('shard-index must be an integer in [0, total-shards)');
  }
  if (new Set(files).size !== files.length) {
    throw new Error('test inventory contains duplicate paths');
  }
  // Interleave sorted paths so each shard gets files from every test area.
  const selected = [...files].sort().filter((_, index) => index % totalShards === shardIndex);
  if (selected.length === 0) throw new Error('test shard is empty');
  return selected;
}

export function parseArguments(args) {
  const options = {shardIndex: 0, totalShards: 1, list: false, flutterArgs: []};
  for (let index = 0; index < args.length; index += 1) {
    const argument = args[index];
    if (argument === '--') {
      options.flutterArgs = args.slice(index + 1);
      break;
    }
    if (argument === '--list') {
      options.list = true;
      continue;
    }
    const match = /^--(shard-index|total-shards)=(\d+)$/.exec(argument);
    if (!match) throw new Error(`unknown argument: ${argument}`);
    options[match[1] === 'shard-index' ? 'shardIndex' : 'totalShards'] = Number(match[2]);
  }
  // Native test sharding splits cases after loading every suite. Reject it
  // here so it cannot silently discard cases from our file partition.
  if (options.flutterArgs.some((arg) => /^--(?:total-shards|shard-index)(?:=|$)/.test(arg))) {
    throw new Error('native case sharding cannot be combined with file sharding');
  }
  return options;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const options = parseArguments(process.argv.slice(2));
    const appRoot = fileURLToPath(new URL('../', import.meta.url));
    const inventory = discoverTestFiles(appRoot);
    const selected = selectTestShard(inventory, options);
    if (options.list) {
      process.stdout.write(`${selected.join('\n')}\n`);
    } else {
      console.log(`File shard ${options.shardIndex + 1}/${options.totalShards}: ${selected.length}/${inventory.length} test files`);
      const result = spawnSync(
        'flutter',
        ['test', ...selected, '--exclude-tags=golden', ...options.flutterArgs],
        {cwd: appRoot, stdio: 'inherit'},
      );
      if (result.error) throw result.error;
      if (result.signal) throw new Error(`Flutter terminated by ${result.signal}`);
      process.exitCode = result.status ?? 1;
    }
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
