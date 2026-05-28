import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_repository.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';

import '../../../core/persistence/test_database.dart';
import '../../../core/sync/_outbox_test_ext.dart';

void main() {
  late AppDatabase db;
  late InMemoryOutboxStore outbox;
  late KnowledgeRepository repo;

  const owner = 'u-test';

  setUp(() {
    db = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    repo = KnowledgeRepository(db: db, outbox: outbox);
  });

  tearDown(() async => db.close());

  SyncMeta meta(DateTime at) => SyncMeta(
        ownerUserId: owner,
        updatedAt: at,
        updatedByDevice: 'dev-test',
        hlc: Hlc.zero('dev-test'),
      );

  KnowledgeRoutine makeRoutine({
    required String id,
    required DateTime nextDueAt,
    int intervalDays = 180,
    String statement = '港卡做一次活跃交易',
    String scope = 'finance/cards/hk',
    RoutineStatus status = RoutineStatus.active,
    DateTime? createdAt,
  }) {
    final now = createdAt ?? DateTime.utc(2026, 1, 1);
    return KnowledgeRoutine(
      id: id,
      statement: statement,
      intervalDays: intervalDays,
      nextDueAt: nextDueAt,
      scope: scope,
      status: status,
      createdAt: now,
      sync: meta(now),
    );
  }

  test('upsertRoutine persists and queues a sync outbox entry', () async {
    final r = makeRoutine(
      id: 'r-1',
      nextDueAt: DateTime.utc(2026, 6, 1),
    );

    await repo.upsertRoutine(r);

    final found = await repo.findRoutine('r-1');
    expect(found, isNotNull);
    expect(found!.statement, '港卡做一次活跃交易');
    expect(found.intervalDays, 180);
    expect(found.status, RoutineStatus.active);

    expect(outbox.queued, hasLength(1));
    expect(outbox.queued.single.table, 'knowledge_routines');
    expect(outbox.queued.single.rowId, 'r-1');
  });

  test(
    'listDueRoutines returns only active routines with next_due_at <= asOf, '
    'ordered ascending',
    () async {
      // Two due, one upcoming, one paused (must be filtered out).
      await repo.upsertRoutine(makeRoutine(
        id: 'overdue',
        nextDueAt: DateTime.utc(2026, 5, 1),
      ));
      await repo.upsertRoutine(makeRoutine(
        id: 'today',
        nextDueAt: DateTime.utc(2026, 5, 29),
      ));
      await repo.upsertRoutine(makeRoutine(
        id: 'next-month',
        nextDueAt: DateTime.utc(2026, 7, 1),
      ));
      await repo.upsertRoutine(makeRoutine(
        id: 'paused-but-overdue',
        nextDueAt: DateTime.utc(2026, 4, 1),
        status: RoutineStatus.paused,
      ));

      final due = await repo.listDueRoutines(
        ownerUserId: owner,
        asOf: DateTime.utc(2026, 5, 29),
      );
      expect(due.map((r) => r.id), <String>['overdue', 'today']);
    },
  );

  test('listDueRoutines respects the 7-day lookahead window', () async {
    await repo.upsertRoutine(makeRoutine(
      id: 'within-week',
      nextDueAt: DateTime.utc(2026, 6, 3),
    ));
    await repo.upsertRoutine(makeRoutine(
      id: 'beyond-week',
      nextDueAt: DateTime.utc(2026, 6, 10),
    ));

    final asOf = DateTime.utc(2026, 5, 29).add(const Duration(days: 7));
    final due = await repo.listDueRoutines(
      ownerUserId: owner,
      asOf: asOf,
    );
    expect(due.map((r) => r.id), <String>['within-week']);
  });

  test(
    'simulated markDone bumps nextDueAt by intervalDays and sets lastDoneAt',
    () async {
      final created = DateTime.utc(2026, 1, 1);
      final r = makeRoutine(
        id: 'hk-card',
        nextDueAt: DateTime.utc(2026, 5, 29),
        createdAt: created,
      );
      await repo.upsertRoutine(r);

      // Mark done at 2026-05-30 — mirrors what the Review tab "已处理"
      // button does.
      final doneAt = DateTime.utc(2026, 5, 30);
      final bumped = KnowledgeRoutine(
        id: r.id,
        statement: r.statement,
        intervalDays: r.intervalDays,
        nextDueAt: doneAt.add(Duration(days: r.intervalDays)),
        lastDoneAt: doneAt,
        scope: r.scope,
        status: r.status,
        createdAt: r.createdAt,
        sync: meta(doneAt),
      );
      await repo.upsertRoutine(bumped);

      final after = await repo.findRoutine('hk-card');
      // Drift's dateTime column round-trips through unix-millis, so a
      // UTC value comes back as the local-timezone representation of
      // the same instant. Compare in UTC so the assertion is timezone-
      // independent.
      expect(after!.lastDoneAt!.toUtc(), doneAt);
      expect(after.nextDueAt.toUtc(), doneAt.add(const Duration(days: 180)));

      final due = await repo.listDueRoutines(
        ownerUserId: owner,
        asOf: doneAt.add(const Duration(days: 7)),
      );
      expect(due, isEmpty, reason: 'bumped routine no longer in this-week window');
    },
  );
}
