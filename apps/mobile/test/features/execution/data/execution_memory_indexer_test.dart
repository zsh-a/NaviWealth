import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/local/embedding/embedder.dart';
import 'package:naviwealth/core/ai/local/memory/event_store.dart';
import 'package:naviwealth/core/ai/local/memory/memory_runtime.dart';
import 'package:naviwealth/core/ai/local/memory/memory_store.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/execution/data/execution_memory_indexer.dart';
import 'package:naviwealth/features/execution/domain/execution_models.dart';

import '../../../core/persistence/test_database.dart';

const _userId = 'u-exec-memory';
const _deviceId = 'dev-exec-memory';

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

MemoryRuntime _runtime() {
  final db = makeTestDatabase();
  return MemoryRuntime(
    embedder: StubEmbedder(),
    memoryStore: SqliteMemoryStore(db: db),
    eventStore: SqliteEventStore(db: db),
  );
}

void main() {
  test('reindex mirrors actions, plans, and progress as events', () async {
    final runtime = _runtime();
    const indexer = ExecutionMemoryIndexer();

    await indexer.reindexActions(runtime, [
      ExecutionAction(
        id: 'act-finance',
        title: 'Review June budget variance',
        status: ExecutionActionStatus.blocked,
        priority: ExecutionPriority.high,
        source: const ExecutionSourceRef(
          domain: 'finance',
          rowFamily: 'fin:budgets',
          rowId: 'budget-2026-06',
          labelSnapshot: 'June budget',
        ),
        createdAt: DateTime.utc(2026, 6, 1),
        sync: _sync(1),
      ),
    ], ownerUserId: _userId);
    await indexer.reindexPlans(runtime, [
      ExecutionPlan(
        id: 'plan-health',
        title: 'Stabilize recovery routine',
        source: const ExecutionSourceRef(
          domain: 'health',
          rowFamily: 'health:health_metrics',
          rowId: 'sleep-1',
          labelSnapshot: 'Short sleep trend',
        ),
        createdAt: DateTime.utc(2026, 6, 1),
        sync: _sync(2),
      ),
    ], ownerUserId: _userId);
    await indexer.reindexProgress(runtime, [
      ExecutionProgressEntry(
        id: 'progress-blocker',
        actionId: 'act-finance',
        planId: 'plan-health',
        kind: ExecutionProgressKind.blocker,
        note: 'Waiting for a verified budget snapshot.',
        createdAt: DateTime.utc(2026, 6, 2),
        sync: _sync(3),
      ),
    ], ownerUserId: _userId);

    final events = await runtime.recentEvents(
      ownerUserId: _userId,
      window: const Duration(days: 9999),
    );

    expect(events, hasLength(3));
    final action = events.firstWhere(
      (event) =>
          event.sourceIdentity.rowFamily == kExecutionActionEventSourceFamily,
    );
    expect(action.kind.name, kExecutionActionEventType);
    expect(action.facts['source_domain'], 'finance');
    expect(action.facts['source_row_family'], 'fin:budgets');
    expect(action.entities, contains('source_domain:finance'));
    expect(action.entities, contains('status:blocked'));

    final plan = events.firstWhere(
      (event) =>
          event.sourceIdentity.rowFamily == kExecutionPlanEventSourceFamily,
    );
    expect(plan.facts['source_domain'], 'health');
    expect(plan.entities, contains('source_domain:health'));

    final progress = events.firstWhere(
      (event) =>
          event.sourceIdentity.rowFamily == kExecutionProgressEventSourceFamily,
    );
    expect(progress.kind.name, kExecutionProgressEventType);
    expect(progress.facts['kind'], 'blocker');
    expect(progress.entities, contains('execution_action:act-finance'));
    expect(progress.importance, greaterThan(0.8));
  });

  test('event ids are stable across repeated reindex', () async {
    final runtime = _runtime();
    const indexer = ExecutionMemoryIndexer();
    final actions = [
      ExecutionAction(
        id: 'act-stable',
        title: 'Keep event id stable',
        createdAt: DateTime.utc(2026, 6, 1),
        sync: _sync(1),
      ),
    ];

    await indexer.reindexActions(runtime, actions, ownerUserId: _userId);
    await indexer.reindexActions(runtime, actions, ownerUserId: _userId);

    final events = await runtime.recentEvents(
      ownerUserId: _userId,
      window: const Duration(days: 9999),
    );
    expect(events, hasLength(1));
    expect(events.single.id, '$kExecutionActionMemorySource:act-stable');
  });
}
