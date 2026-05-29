import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_repository.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';

import '../../../core/persistence/test_database.dart';

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
    test('findPrinciple resolves a retired principle (not just active ones)',
        () async {
      await repo.upsertPrinciple(KnowledgePrinciple(
        id: 'p-retired',
        statement: '默认 edge-first',
        rationaleMd: '',
        scope: '*',
        status: PrincipleStatus.retired,
        declaredAt: at,
        sync: meta(at),
      ));

      // listActivePrinciples drops it; the generic accessors must not.
      expect(await repo.listActivePrinciples(ownerUserId: owner), isEmpty);
      expect(await repo.listPrinciples(ownerUserId: owner), hasLength(1));
      final found = await repo.findPrinciple('p-retired');
      expect(found, isNotNull);
      expect(found!.status, PrincipleStatus.retired);
    });

    test('findAssumption resolves a falsified assumption', () async {
      await repo.upsertAssumption(KnowledgeAssumption(
        id: 'a-falsified',
        statement: '长期指数增长高于通胀',
        confidence: 0.2,
        scope: '*',
        evidenceIds: const ['m-1'],
        status: AssumptionStatus.falsified,
        declaredAt: at,
        sync: meta(at),
      ));

      expect(await repo.listOpenAssumptions(ownerUserId: owner), isEmpty);
      expect(await repo.listAssumptions(ownerUserId: owner), hasLength(1));
      final found = await repo.findAssumption('a-falsified');
      expect(found, isNotNull);
      expect(found!.status, AssumptionStatus.falsified);
    });

    test('listExperiments / findExperiment round-trip', () async {
      await repo.upsertExperiment(KnowledgeExperiment(
        id: 'e-1',
        hypothesis: 'covered call 月度收益 > 持有',
        methodMd: '回测 12 个月',
        metrics: const ['annualized_return'],
        status: ExperimentStatus.running,
        startedAt: at,
        sync: meta(at),
      ));

      expect(await repo.listExperiments(ownerUserId: owner), hasLength(1));
      final found = await repo.findExperiment('e-1');
      expect(found, isNotNull);
      expect(found!.status, ExperimentStatus.running);
    });
  });

  group('Decision lifecycle round-trip (§3 / §9)', () {
    KnowledgeDecision decision({
      required String id,
      required DecisionStatus status,
      String? actualOutcome,
      String? supersededBy,
    }) =>
        KnowledgeDecision(
          id: id,
          question: '是否升级到 QQQ + BOXX 动态对冲?',
          options: [DecisionOption(label: '升级'), DecisionOption(label: '维持')],
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
        await repo.upsertDecision(decision(
          id: 'd-old',
          status: DecisionStatus.superseded,
          actualOutcome: '换成了动态对冲',
          supersededBy: 'd-new',
        ));

        final after = await repo.findDecision('d-old');
        expect(after, isNotNull);
        expect(after!.status, DecisionStatus.superseded);
        expect(after.actualOutcomeMd, '换成了动态对冲');
        expect(after.supersededByDecisionId, 'd-new');
      },
    );
  });
}
