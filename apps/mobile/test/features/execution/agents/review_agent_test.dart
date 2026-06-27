import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/contracts/memory_record.dart';
import 'package:naviwealth/core/ai/local/memory/providers.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/outbox_provider.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/execution/agents/review_agent.dart';
import 'package:naviwealth/features/execution/data/providers.dart';
import 'package:naviwealth/features/execution/domain/execution_models.dart';

import '../../../core/persistence/test_database.dart';

const _userId = 'u-exec-agent';
const _deviceId = 'dev-exec-agent';

Future<T> _withRef<T>(ProviderContainer c, Future<T> Function(Ref ref) body) {
  final probe = FutureProvider<T>((ref) => body(ref));
  c.listen(probe, (_, _) {});
  return c.read(probe.future);
}

SyncMeta _sync(int tick) {
  final wall = DateTime.utc(2026, 6, 1, 9, 0, tick);
  return SyncMeta(
    ownerUserId: _userId,
    updatedAt: wall,
    updatedByDevice: _deviceId,
    hlc: Hlc(
      wallMillis: wall.millisecondsSinceEpoch,
      counter: 0,
      nodeId: _deviceId,
    ),
  );
}

MutationStamper _stamper() {
  var tick = 0;
  return MutationStamper(
    currentUserId: () async => _userId,
    deviceId: () async => _deviceId,
    stampHlc: () async {
      final meta = _sync(tick++);
      return meta.hlc;
    },
  );
}

ProviderContainer _container(AppDatabase db, InMemoryOutboxStore outbox) {
  return ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWith((ref) async => db),
      outboxStoreProvider.overrideWith((ref) async => outbox),
      currentUserIdProvider.overrideWithValue(() async => _userId),
      mutationStamperProvider.overrideWith((ref) async => _stamper()),
    ],
  );
}

void main() {
  late AppDatabase db;
  late InMemoryOutboxStore outbox;
  late ProviderContainer container;

  setUp(() {
    db = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    container = _container(db, outbox);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('writes weekly execution review memory from workflow signals', () async {
    final repo = await container.read(executionRepositoryProvider.future);
    await repo.upsertProject(
      ExecutionProject(
        id: 'project-review',
        title: 'Close execution workflow gaps',
        createdAt: DateTime.utc(2026, 6, 1),
        sync: _sync(1),
      ),
    );
    await repo.upsertCommitment(
      ExecutionCommitment(
        id: 'commit-review',
        title: 'Run weekly execution review',
        projectId: 'project-review',
        createdAt: DateTime.utc(2026, 6, 1),
        sync: _sync(2),
      ),
    );
    await repo.upsertAction(
      ExecutionAction(
        id: 'action-review',
        title: 'Finish review coverage',
        status: ExecutionActionStatus.blocked,
        priority: ExecutionPriority.high,
        projectId: 'project-review',
        commitmentId: 'commit-review',
        dueAt: DateTime.utc(2026, 6, 2),
        createdAt: DateTime.utc(2026, 6, 1),
        sync: _sync(3),
      ),
    );
    await repo.upsertProgress(
      ExecutionProgressEntry(
        id: 'progress-review',
        projectId: 'project-review',
        commitmentId: 'commit-review',
        kind: ExecutionProgressKind.checkin,
        note: 'Review workflow connected to memory.',
        createdAt: DateTime.utc(2026, 6, 3),
        sync: _sync(4),
      ),
    );

    final result = await _withRef(
      container,
      (ref) => const ExecutionReviewAgent().run(
        AgentContext(ref: ref, now: DateTime.utc(2026, 6, 5, 17)),
      ),
    );

    expect(result.status, AgentRunStatus.completed);
    expect(result.memoryId, '$kExecutionReviewMemorySource:2026-06-05');
    expect(result.summary, contains('1 blocked'));
    expect(result.summary, contains('1 active commitments'));

    final runtime = await container.read(memoryRuntimeProvider.future);
    final hits = await runtime.recall(
      ownerUserId: _userId,
      queryText: 'execution review blocked commitments',
      kinds: const {MemoryKind.episodic},
      source: kExecutionReviewMemorySource,
      topK: 5,
    );
    expect(hits, hasLength(1));
    expect(hits.single.record.entities, contains('execution_review'));
    expect(
      hits.single.record.entities,
      contains('execution_action:action-review'),
    );
  });

  test('skips when there is nothing to review', () async {
    final result = await _withRef(
      container,
      (ref) => const ExecutionReviewAgent().run(
        AgentContext(ref: ref, now: DateTime.utc(2026, 6, 5, 17)),
      ),
    );

    expect(result.status, AgentRunStatus.skipped);
    expect(result.summary, 'no execution signals to review');
  });
}
