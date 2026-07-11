import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime/persistence/agent_runtime_checkpoint_store.dart';

import '../core/persistence/test_database.dart';

void main() {
  test('Drift checkpoint store journals one effect with revisions', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    var now = DateTime.utc(2026, 7, 11, 8);
    final store = DriftAgentRuntimeCheckpointStore(
      databaseReader: () async => db,
      ownerUserIdReader: () async => 'user-1',
      clock: () => now,
    );

    final created = await store.create(
      requestFingerprint: 'request-1',
      snapshot: _requestedSnapshot(),
      resumeContext: const <String, Object?>{'surface': 'test'},
    );
    expect(created.revision, 0);
    expect(created.status, AgentRuntimeCheckpointStatus.awaitingEffect);
    expect(created.effectId, 'effect-1');

    now = now.add(const Duration(seconds: 1));
    final dispatching = await store.reserveEffect(
      runId: created.runId,
      expectedRevision: created.revision,
      effectKind: 'tool',
      effectId: 'effect-1',
    );
    expect(dispatching.revision, 1);
    expect(dispatching.status, AgentRuntimeCheckpointStatus.dispatching);

    now = now.add(const Duration(seconds: 1));
    final recorded = await store.recordEffectPayload(
      runId: created.runId,
      expectedRevision: dispatching.revision,
      effectKind: 'tool',
      effectId: 'effect-1',
      payload: const <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'effect-1',
        'result': <String, Object?>{'ok': true},
      },
    );
    expect(recorded.revision, 2);
    expect(recorded.status, AgentRuntimeCheckpointStatus.effectRecorded);
    expect(recorded.effectPayload?['id'], 'effect-1');

    now = now.add(const Duration(seconds: 1));
    final terminal = await store.replaceSnapshot(
      runId: created.runId,
      expectedRevision: recorded.revision,
      requestFingerprint: 'request-1',
      snapshot: _terminalSnapshot(),
      resumeContext: recorded.resumeContext,
    );
    expect(terminal.revision, 3);
    expect(terminal.status, AgentRuntimeCheckpointStatus.terminal);
    expect(terminal.effectPayload, isNull);
    expect(
      await store.findResumable(
        agentId: 'execution_review',
        requestFingerprint: 'request-1',
      ),
      isNull,
    );
  });

  test(
    'dispatch reservation survives restart and blocks stale revisions',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final clock = DateTime.utc(2026, 7, 11, 9);
      DriftAgentRuntimeCheckpointStore buildStore() =>
          DriftAgentRuntimeCheckpointStore(
            databaseReader: () async => db,
            ownerUserIdReader: () async => 'user-1',
            clock: () => clock,
          );

      final created = await buildStore().create(
        requestFingerprint: 'request-2',
        snapshot: _requestedSnapshot(runId: 'run-2'),
      );
      await buildStore().reserveEffect(
        runId: created.runId,
        expectedRevision: created.revision,
        effectKind: 'tool',
        effectId: 'effect-1',
      );

      final resumed = await buildStore().findResumable(
        agentId: 'execution_review',
        requestFingerprint: 'request-2',
      );
      expect(resumed?.status, AgentRuntimeCheckpointStatus.dispatching);
      await expectLater(
        buildStore().reserveEffect(
          runId: created.runId,
          expectedRevision: created.revision,
          effectKind: 'tool',
          effectId: 'effect-1',
        ),
        throwsA(
          isA<AgentRuntimeCheckpointException>().having(
            (error) => error.code,
            'code',
            AgentRuntimeCheckpointErrorCode.staleRevision,
          ),
        ),
      );
    },
  );

  test('checkpoint lookup is owner scoped and expires pending rows', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    var now = DateTime.utc(2026, 7, 11, 10);
    String owner = 'user-1';
    final store = DriftAgentRuntimeCheckpointStore(
      databaseReader: () async => db,
      ownerUserIdReader: () async => owner,
      clock: () => now,
      retention: const Duration(minutes: 5),
    );
    await store.create(
      requestFingerprint: 'request-3',
      snapshot: _requestedSnapshot(runId: 'run-3'),
    );

    owner = 'user-2';
    expect(
      await store.findResumable(
        agentId: 'execution_review',
        requestFingerprint: 'request-3',
      ),
      isNull,
    );
    owner = 'user-1';
    now = now.add(const Duration(minutes: 6));
    expect(
      await store.findResumable(
        agentId: 'execution_review',
        requestFingerprint: 'request-3',
      ),
      isNull,
    );
  });

  test('checkpoint lookup rejects snapshot identity corruption', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = DriftAgentRuntimeCheckpointStore(
      databaseReader: () async => db,
      ownerUserIdReader: () async => 'user-1',
    );
    final snapshot = _requestedSnapshot(runId: 'run-corrupt');
    await store.create(
      requestFingerprint: 'request-corrupt',
      snapshot: snapshot,
    );
    final corruptStep = <String, Object?>{
      ...(snapshot['step']! as Map<String, Object?>),
      'agent_id': 'different-agent',
    };
    await db.customStatement(
      'UPDATE agent_runtime_checkpoints SET snapshot_json = ? '
      'WHERE owner_user_id = ? AND run_id = ?',
      <Object?>[
        jsonEncode(<String, Object?>{...snapshot, 'step': corruptStep}),
        'user-1',
        'run-corrupt',
      ],
    );

    await expectLater(
      store.findResumable(
        agentId: 'execution_review',
        requestFingerprint: 'request-corrupt',
      ),
      throwsA(
        isA<AgentRuntimeCheckpointException>().having(
          (error) => error.code,
          'code',
          AgentRuntimeCheckpointErrorCode.corrupt,
        ),
      ),
    );
  });

  test('request fingerprint is stable across map insertion order', () {
    final first = agentRuntimeRequestFingerprint(
      agentId: 'execution_review',
      catalog: const <String, Object?>{
        'protocol_version': 'agent.v1',
        'catalog_version': 'agent_catalog.v1',
      },
      request: const <String, Object?>{
        'input': <String, Object?>{'b': 2, 'a': 1},
        'metadata': <String, Object?>{},
      },
    );
    final second = agentRuntimeRequestFingerprint(
      agentId: 'execution_review',
      catalog: const <String, Object?>{
        'catalog_version': 'agent_catalog.v1',
        'protocol_version': 'agent.v1',
      },
      request: const <String, Object?>{
        'metadata': <String, Object?>{},
        'input': <String, Object?>{'a': 1, 'b': 2},
      },
    );
    expect(first, second);
  });
}

Map<String, Object?> _requestedSnapshot({String runId = 'run-1'}) =>
    <String, Object?>{
      'protocol_version': 'agent.v1',
      'snapshot_version': 1,
      'step': <String, Object?>{
        'protocol_version': 'agent.v1',
        'run_id': runId,
        'agent_id': 'execution_review',
        'step_index': 0,
        'status': 'effect_requested',
        'effect': const <String, Object?>{
          'kind': 'tool',
          'effect_id': 'effect-1',
          'name': 'read_snapshot',
          'input': <String, Object?>{},
        },
      },
      'limits': const <String, Object?>{
        'max_effect_steps': 2,
        'max_subagent_depth': 1,
      },
      'progress': const <String, Object?>{
        'dispatched_effect_count': 0,
        'subagent_depth': 0,
        'effect_budget_exhausted': false,
        'subagent_depth_exceeded': false,
      },
    };

Map<String, Object?> _terminalSnapshot() => <String, Object?>{
  ..._requestedSnapshot(),
  'step': const <String, Object?>{
    'protocol_version': 'agent.v1',
    'run_id': 'run-1',
    'agent_id': 'execution_review',
    'step_index': 1,
    'status': 'completed',
    'output': <String, Object?>{'ok': true},
  },
  'progress': const <String, Object?>{
    'dispatched_effect_count': 1,
    'subagent_depth': 0,
    'effect_budget_exhausted': false,
    'subagent_depth_exceeded': false,
  },
};
