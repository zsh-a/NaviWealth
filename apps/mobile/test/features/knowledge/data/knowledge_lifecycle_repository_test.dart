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

  final at = DateTime.utc(2026, 1, 1);

  group('generic list/find accessors (API consistency)', () {
    test(
      'findPrinciple resolves a retired principle (not just active ones)',
      () async {
        await repo.upsertPrinciple(
          KnowledgePrinciple(
            id: 'p-retired',
            statement: '默认 edge-first',
            rationaleMd: '',
            scope: '*',
            status: PrincipleStatus.retired,
            declaredAt: at,
            sync: meta(at),
          ),
        );

        // listActivePrinciples drops it; the generic accessors must not.
        expect(await repo.listActivePrinciples(ownerUserId: owner), isEmpty);
        expect(await repo.listPrinciples(ownerUserId: owner), hasLength(1));
        final found = await repo.findPrinciple(
          ownerUserId: owner,
          id: 'p-retired',
        );
        expect(found, isNotNull);
        expect(found!.status, PrincipleStatus.retired);
      },
    );

    test('find accessors are scoped by owner user id', () async {
      await repo.upsertNote(
        KnowledgeNote(
          id: 'shared-id',
          title: 'owner note',
          bodyMd: '',
          tags: const [],
          createdAt: at,
          sync: meta(at),
        ),
      );

      expect(
        await repo.findNote(ownerUserId: 'other-user', id: 'shared-id'),
        isNull,
      );
      expect(
        await repo.findNote(ownerUserId: owner, id: 'shared-id'),
        isNotNull,
      );
    });

    test('findAssumption resolves a falsified assumption', () async {
      await repo.upsertAssumption(
        KnowledgeAssumption(
          id: 'a-falsified',
          statement: '长期指数增长高于通胀',
          confidence: 0.2,
          scope: '*',
          evidenceIds: const ['m-1'],
          status: AssumptionStatus.falsified,
          declaredAt: at,
          sync: meta(at),
        ),
      );

      expect(await repo.listOpenAssumptions(ownerUserId: owner), isEmpty);
      expect(await repo.listAssumptions(ownerUserId: owner), hasLength(1));
      final found = await repo.findAssumption(
        ownerUserId: owner,
        id: 'a-falsified',
      );
      expect(found, isNotNull);
      expect(found!.status, AssumptionStatus.falsified);
    });

    test('listExperiments / findExperiment round-trip', () async {
      await repo.upsertExperiment(
        KnowledgeExperiment(
          id: 'e-1',
          hypothesis: 'covered call 月度收益 > 持有',
          methodMd: '回测 12 个月',
          metrics: const ['annualized_return'],
          status: ExperimentStatus.running,
          startedAt: at,
          sync: meta(at),
        ),
      );

      expect(await repo.listExperiments(ownerUserId: owner), hasLength(1));
      final found = await repo.findExperiment(ownerUserId: owner, id: 'e-1');
      expect(found, isNotNull);
      expect(found!.status, ExperimentStatus.running);
    });
  });

  group('deleteEntry', () {
    test('soft-deletes a note and queues one sync pointer', () async {
      await repo.upsertNote(
        KnowledgeNote(
          id: 'n-delete',
          title: '临时资料',
          bodyMd: 'cleanup',
          tags: const [],
          createdAt: at,
          sync: meta(at),
        ),
      );
      outbox.clearQueued();

      final deletedAt = DateTime.utc(2026, 1, 2);
      await repo.deleteEntry(
        kind: KnowledgeEntryKind.note,
        id: 'n-delete',
        sync: meta(deletedAt).copyWith(deletedAt: deletedAt),
      );

      expect(await repo.listNotes(ownerUserId: owner), isEmpty);
      final tombstone = await repo.findNote(ownerUserId: owner, id: 'n-delete');
      expect(tombstone, isNotNull);
      expect(tombstone!.sync.deletedAt, isNotNull);
      expect(outbox.queued, hasLength(1));
      expect(outbox.queued.single.table, 'knowledge_notes');
      expect(outbox.queued.single.rowId, 'n-delete');
    });

    test('does not delete a row owned by another user', () async {
      await repo.upsertRoutine(
        KnowledgeRoutine(
          id: 'r-keep',
          statement: '港卡活跃',
          intervalDays: 180,
          nextDueAt: at,
          scope: 'finance/cards',
          status: RoutineStatus.active,
          createdAt: at,
          sync: meta(at),
        ),
      );
      outbox.clearQueued();

      final deletedAt = DateTime.utc(2026, 1, 2);
      await repo.deleteEntry(
        kind: KnowledgeEntryKind.routine,
        id: 'r-keep',
        sync: SyncMeta(
          ownerUserId: 'someone-else',
          updatedAt: deletedAt,
          updatedByDevice: 'dev-test',
          hlc: Hlc.zero('dev-test'),
          deletedAt: deletedAt,
        ),
      );

      expect(await repo.listRoutines(ownerUserId: owner), hasLength(1));
      expect(outbox.queued, isEmpty);
    });
  });

  group('Decision lifecycle round-trip (§3 / §9)', () {
    KnowledgeDecision decision({
      required String id,
      required DecisionStatus status,
      String? actualOutcome,
      String? supersededBy,
    }) => KnowledgeDecision(
      id: id,
      question: '是否升级到 QQQ + BOXX 动态对冲?',
      options: [
        DecisionOption(label: '升级'),
        DecisionOption(label: '维持'),
      ],
      selectedLabel: '升级',
      rationaleMd: '当时的判断',
      principleIds: const [],
      assumptionIds: const [],
      status: status,
      actualOutcomeMd: actualOutcome,
      supersededByDecisionId: supersededBy,
      decidedAt: at,
      sync: meta(at),
    );

    test(
      'updating status + actual_outcome + supersededBy persists via upsert',
      () async {
        await repo.upsertDecision(
          decision(id: 'd-old', status: DecisionStatus.active),
        );
        await repo.upsertDecision(
          decision(id: 'd-new', status: DecisionStatus.active),
        );

        // Mirror what the lifecycle sheet writes: old decision becomes
        // superseded, records its outcome and points at the replacement.
        await repo.upsertDecision(
          decision(
            id: 'd-old',
            status: DecisionStatus.superseded,
            actualOutcome: '换成了动态对冲',
            supersededBy: 'd-new',
          ),
        );

        final after = await repo.findDecision(ownerUserId: owner, id: 'd-old');
        expect(after, isNotNull);
        expect(after!.status, DecisionStatus.superseded);
        expect(after.actualOutcomeMd, '换成了动态对冲');
        expect(after.supersededByDecisionId, 'd-new');
      },
    );
  });
}
