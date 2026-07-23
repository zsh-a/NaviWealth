import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime/persistence/agent_runtime_chat_snapshot_store.dart';
import 'package:naviwealth/app/agent_runtime/persistence/drift_agent_runtime_chat_snapshot_store.dart';

import '../core/persistence/test_database.dart';

void main() {
  test('Drift chat snapshot store persists optimistic revisions', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    var now = DateTime.utc(2026, 7, 17, 8);
    DriftAgentRuntimeChatSnapshotStore buildStore() =>
        DriftAgentRuntimeChatSnapshotStore(
          databaseReader: () async => db,
          ownerUserIdReader: () async => 'user-1',
          clock: () => now,
        );

    final created = await buildStore().save(snapshot: _snapshot());
    expect(created.revision, 0);
    expect(created.status, 'requires_tool_results');

    now = now.add(const Duration(seconds: 1));
    final updated = await buildStore().save(
      snapshot: _snapshot(dispatchStatus: 'dispatching'),
      expectedRevision: created.revision,
    );
    expect(updated.revision, 1);
    expect(
      (updated.snapshot['tool_dispatches']! as List).single,
      containsPair('status', 'dispatching'),
    );

    final resumed = await buildStore().loadResumable('turn-1');
    expect(resumed?.revision, 1);
    await expectLater(
      buildStore().save(
        snapshot: _snapshot(dispatchStatus: 'completed'),
        expectedRevision: created.revision,
      ),
      throwsA(
        isA<AgentRuntimeChatSnapshotException>().having(
          (error) => error.code,
          'code',
          AgentRuntimeChatSnapshotErrorCode.staleRevision,
        ),
      ),
    );
  });

  test(
    'chat snapshots are owner scoped and terminal rows do not resume',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      var owner = 'user-1';
      final store = DriftAgentRuntimeChatSnapshotStore(
        databaseReader: () async => db,
        ownerUserIdReader: () async => owner,
      );
      final created = await store.save(snapshot: _snapshot());

      owner = 'user-2';
      expect(await store.loadResumable('turn-1'), isNull);
      owner = 'user-1';
      await store.save(
        snapshot: _snapshot(status: 'completed', dispatches: const <Object?>[]),
        expectedRevision: created.revision,
      );
      expect(await store.loadResumable('turn-1'), isNull);
    },
  );

  test('persists a resumable pending interaction snapshot', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = DriftAgentRuntimeChatSnapshotStore(
      databaseReader: () async => db,
      ownerUserIdReader: () async => 'user-1',
    );

    final created = await store.save(snapshot: _interactionSnapshot());

    expect(created.status, 'requires_interaction');
    expect(
      (await store.loadResumable('turn-interaction'))?.status,
      'requires_interaction',
    );
  });
}

Map<String, Object?> _snapshot({
  String status = 'requires_tool_results',
  String dispatchStatus = 'pending',
  List<Object?>? dispatches,
}) {
  return <String, Object?>{
    'protocol_version': 'agent.v1',
    'snapshot_version': 1,
    'status': status,
    'state': <String, Object?>{
      'turn_id': 'turn-1',
      'round': 1,
      'pending_tool_calls': status == 'requires_tool_results'
          ? const <Object?>[
              <String, Object?>{
                'id': 'call-1',
                'name': 'read_task',
                'input': <String, Object?>{},
              },
            ]
          : const <Object?>[],
    },
    'tool_dispatches':
        dispatches ??
        <Object?>[
          <String, Object?>{
            'call': <String, Object?>{
              'id': 'call-1',
              'name': 'read_task',
              'input': <String, Object?>{},
            },
            'replay_policy': 'safe_retry',
            'status': dispatchStatus,
            if (dispatchStatus == 'completed')
              'result': const <String, Object?>{
                'tool_call_id': 'call-1',
                'tool_name': 'read_task',
                'output': <String, Object?>{'ok': true},
                'is_error': false,
              },
          },
        ],
  };
}

Map<String, Object?> _interactionSnapshot() {
  return <String, Object?>{
    'protocol_version': 'agent.v1',
    'snapshot_version': 1,
    'status': 'requires_interaction',
    'state': <String, Object?>{
      'turn_id': 'turn-interaction',
      'round': 1,
      'pending_tool_calls': const <Object?>[],
      'pending_interaction': <String, Object?>{
        'protocol_version': 'agent.v1',
        'interaction_id': 'interaction-1',
        'kind': 'choice',
        'mode': 'one_tap',
        'status': 'pending',
        'title': 'Choose',
        'options': const <Object?>[
          <String, Object?>{'id': 'a', 'label': 'A'},
          <String, Object?>{'id': 'b', 'label': 'B'},
        ],
        'response_schema': const <String, Object?>{},
        'payload': const <String, Object?>{},
        'metadata': const <String, Object?>{},
        'resume': const <String, Object?>{'kind': 'chat_turn'},
        'created_at': '2026-07-23T00:00:00Z',
      },
    },
    'tool_dispatches': const <Object?>[],
  };
}
