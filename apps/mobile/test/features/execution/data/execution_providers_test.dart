import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/outbox_provider.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/execution/data/providers.dart';
import 'package:naviwealth/features/execution/domain/execution_models.dart';

import '../../../core/persistence/test_database.dart';

const _userId = 'u-exec-providers';
const _deviceId = 'dev-exec-providers';

void main() {
  late AppDatabase db;
  late InMemoryOutboxStore outbox;
  late ProviderContainer container;

  setUp(() {
    db = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((ref) async => db),
        outboxStoreProvider.overrideWith((ref) async => outbox),
        currentUserIdProvider.overrideWithValue(() async => _userId),
        mutationStamperProvider.overrideWith((ref) async => _stamper()),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test(
    'by-id providers resolve lifecycle rows hidden from active lists',
    () async {
      final repo = await container.read(executionRepositoryProvider.future);
      await repo.upsertPlan(
        ExecutionPlan(
          id: 'proj-completed',
          title: 'Completed execution migration',
          status: ExecutionPlanStatus.completed,
          createdAt: DateTime.utc(2026, 6, 1),
          completedAt: DateTime.utc(2026, 6, 2),
          sync: _sync(1),
        ),
      );
      final plan = await container.read(
        executionPlanByIdProvider('proj-completed').future,
      );

      expect(plan?.title, 'Completed execution migration');
      expect(plan?.status, ExecutionPlanStatus.completed);
    },
  );

  test(
    'review relations resolve relation labels from closed actions',
    () async {
      final repo = await container.read(executionRepositoryProvider.future);
      await repo.upsertPlan(
        ExecutionPlan(
          id: 'proj-1',
          title: 'Completed plan relation',
          createdAt: DateTime.utc(2026, 6, 1),
          sync: _sync(1),
        ),
      );
      final action = ExecutionAction(
        id: 'action-closed',
        title: 'Closed action relation',
        planId: 'proj-1',
        createdAt: DateTime.utc(2026, 6, 1),
        sync: _sync(2),
      );
      await repo.upsertAction(action);
      await repo.updateActionStatus(
        action: action,
        status: ExecutionActionStatus.done,
        sync: _sync(3),
      );

      final subscription = container.listen(
        executionReviewRelationsProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      final relations = await container.read(
        executionReviewRelationsProvider.future,
      );

      expect(relations.actionLabel('action-closed'), 'Closed action relation');
      expect(relations.planLabel('proj-1'), 'Completed plan relation');
    },
  );
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
