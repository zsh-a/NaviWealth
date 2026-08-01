import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import {
  renderMarkdown,
  summarizeTestEvents,
} from '../summarize-test-events.mjs';

test('summarizes shard wall time, results, and slowest tests', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'navi-test-events-'));
  try {
    const file = path.join(directory, 'shard-0.json');
    fs.writeFileSync(
      file,
      [
        {type: 'start', time: 0},
        {
          type: 'testStart',
          time: 10,
          test: {id: 1, name: 'fast', url: 'file:///repo/test/fast_test.dart'},
        },
        {type: 'testDone', time: 30, testID: 1, result: 'success'},
        {
          type: 'testStart',
          time: 40,
          test: {id: 2, name: 'slow', url: 'file:///repo/test/slow_test.dart'},
        },
        {type: 'testDone', time: 140, testID: 2, result: 'failure'},
      ]
        .map(JSON.stringify)
        .join('\n'),
    );

    const summary = summarizeTestEvents([directory]);
    assert.equal(summary.tests.length, 2);
    assert.equal(summary.shards[0].wallTimeMs, 140);
    assert.equal(summary.resultCounts.get('success'), 1);
    assert.equal(summary.resultCounts.get('failure'), 1);
    assert.equal(summary.slowest[0].name, 'slow');
    assert.equal(summary.slowest[0].durationMs, 100);
    assert.match(renderMarkdown(summary), /slowest tests/i);
  } finally {
    fs.rmSync(directory, {recursive: true, force: true});
  }
});

test('reports malformed lines without dropping valid events', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'navi-test-events-'));
  try {
    const file = path.join(directory, 'shard-1.json');
    fs.writeFileSync(
      file,
      [
        'not-json',
        JSON.stringify({
          type: 'testStart',
          time: 5,
          test: {id: 7, name: 'valid', url: 'file:///repo/test/valid_test.dart'},
        }),
        JSON.stringify({type: 'testDone', time: 15, testID: 7, result: 'success'}),
      ].join('\n'),
    );

    const summary = summarizeTestEvents([file]);
    assert.equal(summary.tests.length, 1);
    assert.equal(summary.warnings.length, 1);
  } finally {
    fs.rmSync(directory, {recursive: true, force: true});
  }
});
