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

test('uses suite ownership for widgets and separates loading, skips, and hooks', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'navi-test-events-'));
  try {
    const file = path.join(directory, 'shard-2.json');
    fs.writeFileSync(file, [
      {type: 'suite', time: 0, suite: {id: 1, path: '/repo/test/flow/widget_test.dart'}},
      {type: 'testStart', time: 0, test: {id: 2, suiteID: 1, name: 'loading /repo/test/flow/widget_test.dart', url: null}},
      {type: 'testDone', time: 100, testID: 2, hidden: true, result: 'success'},
      {type: 'testStart', time: 100, test: {id: 3, suiteID: 1, name: '(setUpAll)', url: null}},
      {type: 'testDone', time: 150, testID: 3, hidden: true, result: 'success'},
      {type: 'testStart', time: 150, test: {id: 4, suiteID: 1, name: 'widget renders', url: 'package:flutter_test/src/widget_tester.dart'}},
      {type: 'testDone', time: 350, testID: 4, result: 'success'},
      {type: 'testStart', time: 350, test: {id: 5, suiteID: 1, name: 'native only', metadata: {skip: true}, url: 'package:flutter_test/src/widget_tester.dart'}},
      {type: 'testDone', time: 400, testID: 5, skipped: true, result: 'success'},
      // Failed hooks must stay visible in the failure ranking.
      {type: 'testStart', time: 400, test: {id: 6, suiteID: 1, name: '(tearDownAll)', url: null}},
      {type: 'testDone', time: 450, testID: 6, hidden: true, result: 'error'},
      {type: 'done', time: 500, success: false},
    ].map(JSON.stringify).join('\n'));

    const summary = summarizeTestEvents([file]);
    assert.equal(summary.tests.length, 2);
    assert.equal(summary.slowest[0].url, 'file:///repo/test/flow/widget_test.dart');
    assert.equal(summary.resultCounts.get('error'), 1);
    assert.equal(summary.shards[0].loadedFiles, 1);
    assert.equal(summary.shards[0].skipped, 1);
    assert.equal(summary.shards[0].loadingMs, 100);
    assert.equal(summary.shards[0].wallTimeMs, 500);
    assert.equal(summary.shards[0].outcome, 'failed');
    assert.equal(summary.slowestFiles[0].completed, 2);
    assert.equal(summary.slowestFiles[0].caseMs, 250);
    const markdown = renderMarkdown(summary);
    assert.match(markdown, /test\/flow\/widget_test.dart/);
    assert.doesNotMatch(markdown, /widget_tester.dart/);
    assert.match(markdown, /may overlap/);
  } finally {
    fs.rmSync(directory, {recursive: true, force: true});
  }
});

test('an unfinished event stream stays incomplete and runner failure stays visible', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'navi-test-events-'));
  try {
    const file = path.join(directory, 'shard.json');
    const events = [
      {type: 'testStart', time: 0, test: {id: 1, name: 'case', url: 'file:///repo/test/case_test.dart'}},
      {type: 'testDone', time: 10, testID: 1, result: 'success'},
    ];
    const write = () => fs.writeFileSync(file, events.map(JSON.stringify).join('\n'));
    write();
    assert.equal(summarizeTestEvents([file]).shards[0].outcome, 'incomplete');
    // Flutter can report a late framework failure after a successful case.
    events.push({type: 'done', time: 20, success: false});
    write();
    const failed = summarizeTestEvents([file]);
    assert.equal(failed.resultCounts.get('success'), 1);
    assert.equal(failed.shards[0].outcome, 'failed');
    assert.match(renderMarkdown(failed), /\| failed \|/);
    events[2].success = true;
    write();
    assert.equal(summarizeTestEvents([file]).shards[0].outcome, 'passed');
  } finally {
    fs.rmSync(directory, {recursive: true, force: true});
  }
});
