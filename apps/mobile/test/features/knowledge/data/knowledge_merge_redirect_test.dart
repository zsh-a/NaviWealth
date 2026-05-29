import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_repository.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';

import '../../../core/persistence/test_database.dart';

/// Covers the §15.3 P1 merge **reference redirection** added in the v22→v23
/// migration: merging an assumption / principle / decision must re-point the
/// rows that referenced the duplicate, not leave dangling ids.
void main() {
  late AppDatabase db;
  late KnowledgeRepository repo;

  const owner = 'u-test';
  final t0 = DateTime.utc(2026, 1, 1);

  setUp(() {
    db = makeTestDatabase();
    repo = KnowledgeRepository(db: db, outbox: InMemoryOutboxStore());
  });

  tearDown(() async => db.close());

  var stampCounter = 0;
  Future<SyncMeta> stamp() async {
    stampCounter++;
    return SyncMeta(
      ownerUserId: owner,
      updatedAt: t0.add(Duration(seconds: stampCounter)),
      updatedByDevice: 'dev-test',
      hlc: Hlc.zero('dev-test'),
    );
  }

  SyncMeta meta() => SyncMeta(
        ownerUserId: owner,
        updatedAt: t0,
        updatedByDevice: 'dev-test',
        hlc: Hlc.zero('dev-test'),
      );

  KnowledgeAssumption assumption(String id, {List<String> evidence = const []}) =>
      KnowledgeAssumption(
        id: id,
        statement: 'assumption $id',
        confidence: 0.7,
        scope: '*',
        evidenceIds: evidence,
        status: AssumptionStatus.active,
        declaredAt: t0,
        sync: meta(),
      );

  KnowledgePrinciple principle(String id) => KnowledgePrinciple(
        id: id,
        statement: 'principle $id',
        rationaleMd: '',
        scope: '*',
        status: PrincipleStatus.active,
        declaredAt: t0,
        sync: meta(),
      );

  KnowledgeDecision decision(
    String id, {
    List<String> principleIds = const [],
    List<String> assumptionIds = const [],
    String? supersededBy,
  }) =>
      KnowledgeDecision(
        id: id,
        question: 'decision $id',
        options: const [],
        selectedLabel: '',
        rationaleMd: '',
        principleIds: principleIds,
        assumptionIds: assumptionIds,
        status: DecisionStatus.active,
        supersededByDecisionId: supersededBy,
        decidedAt: t0,
        sync: meta(),
      );

  KnowledgeExperiment experiment(
    String id, {
    String? target,
    List<String> metrics = const [],
  }) =>
      KnowledgeExperiment(
        id: id,
        hypothesis: 'experiment $id',
        methodMd: '',
        metrics: metrics,
        status: ExperimentStatus.running,
        targetAssumptionId: target,
        startedAt: t0,
        sync: meta(),
      );

  test(
    'mergeAssumptions re-points Decision.assumptionIds + Experiment.target '
    'and unions evidence; duplicate is tombstoned',
    () async {
      await repo.upsertAssumption(assumption('a-keep', evidence: ['m-1']));
      await repo.upsertAssumption(assumption('a-dup', evidence: ['m-2']));
      await repo.upsertDecision(
        decision('d-1', assumptionIds: ['a-dup', 'x-other']),
      );
      await repo.upsertExperiment(experiment('e-1', target: 'a-dup'));

      final primary = (await repo.findAssumption('a-keep'))!;
      final dup = (await repo.findAssumption('a-dup'))!;
      await repo.mergeAssumptions(
        primary: primary,
        duplicates: [dup],
        stamp: stamp,
      );

      // Duplicate tombstoned + pointer recorded.
      final dupAfter = await repo.findAssumption('a-dup');
      expect(dupAfter!.mergedIntoId, 'a-keep');
      expect(dupAfter.sync.deletedAt, isNotNull);

      // Survivor unions evidence.
      final keep = await repo.findAssumption('a-keep');
      expect(keep!.evidenceIds, containsAll(<String>['m-1', 'm-2']));

      // Inbound refs re-pointed, no dangling 'a-dup'.
      final d = await repo.findDecision('d-1');
      expect(d!.assumptionIds, containsAll(<String>['a-keep', 'x-other']));
      expect(d.assumptionIds, isNot(contains('a-dup')));

      final e = await repo.findExperiment('e-1');
      expect(e!.targetAssumptionId, 'a-keep');
    },
  );

  test('mergePrinciples re-points Decision.principleIds', () async {
    await repo.upsertPrinciple(principle('p-keep'));
    await repo.upsertPrinciple(principle('p-dup'));
    await repo.upsertDecision(decision('d-1', principleIds: ['p-dup']));

    final primary = (await repo.findPrinciple('p-keep'))!;
    final dup = (await repo.findPrinciple('p-dup'))!;
    await repo.mergePrinciples(primary: primary, duplicates: [dup], stamp: stamp);

    expect((await repo.findPrinciple('p-dup'))!.mergedIntoId, 'p-keep');
    final d = await repo.findDecision('d-1');
    expect(d!.principleIds, <String>['p-keep']);
  });

  test('mergeDecisions re-points other decisions supersededByDecisionId',
      () async {
    await repo.upsertDecision(decision('d-keep'));
    await repo.upsertDecision(decision('d-dup'));
    // d-old was superseded by the duplicate; after merge it should point at
    // the survivor so the evolution chain stays intact.
    await repo.upsertDecision(decision('d-old', supersededBy: 'd-dup'));

    final primary = (await repo.findDecision('d-keep'))!;
    final dup = (await repo.findDecision('d-dup'))!;
    await repo.mergeDecisions(primary: primary, duplicates: [dup], stamp: stamp);

    expect((await repo.findDecision('d-dup'))!.mergedIntoId, 'd-keep');
    expect(
      (await repo.findDecision('d-old'))!.supersededByDecisionId,
      'd-keep',
    );
  });

  test('mergeExperiments unions metrics and tombstones (no inbound refs)',
      () async {
    await repo.upsertExperiment(experiment('e-keep', metrics: ['roi']));
    await repo.upsertExperiment(experiment('e-dup', metrics: ['sharpe']));

    final primary = (await repo.findExperiment('e-keep'))!;
    final dup = (await repo.findExperiment('e-dup'))!;
    await repo.mergeExperiments(
      primary: primary,
      duplicates: [dup],
      stamp: stamp,
    );

    final keep = await repo.findExperiment('e-keep');
    expect(keep!.metrics, containsAll(<String>['roi', 'sharpe']));
    expect((await repo.findExperiment('e-dup'))!.mergedIntoId, 'e-keep');
  });
}
