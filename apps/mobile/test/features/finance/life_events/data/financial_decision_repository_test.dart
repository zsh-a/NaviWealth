import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/features/finance/life_events/data/financial_decision_repository.dart';
import 'package:naviwealth/features/finance/life_events/domain/financial_decision.dart';
import 'package:naviwealth/features/finance/life_events/domain/life_event_scenario.dart';

import '../../../../core/persistence/test_database.dart';
import '../../data/repositories/_stub_stamper.dart';

void main() {
  late AppDatabase db;
  late InMemoryOutboxStore outbox;
  late FinancialDecisionRepository repository;

  setUp(() {
    db = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    repository = FinancialDecisionRepository(
      db: db,
      outbox: outbox,
      stamper: makeStubStamper(),
    );
  });

  tearDown(() => db.close());

  test('create and review preserve evidence and enqueue sync', () async {
    final baseline = LifeEventBaseline(
      liquidBalance: Decimal.fromInt(100000),
      monthlyIncome: Decimal.fromInt(20000),
      monthlyOutflow: Decimal.fromInt(10000),
      currency: 'CNY',
      fireMonthsToTarget: 120,
    );
    const engine = LifeEventScenarioEngine();
    final assumptions = engine.preset(LifeEventTemplate.careerBreak, baseline);
    final predicted = engine.simulate(baseline, assumptions);

    final created = await repository.create(
      template: LifeEventTemplate.careerBreak,
      selectedVariant: LifeEventVariant.baseline,
      baseline: baseline,
      assumptions: assumptions,
      outcome: predicted,
      reviewDate: DateTime.utc(2026, 8, 18),
      now: DateTime.utc(2026, 7, 19),
    );
    expect(created.baseline.liquidBalance, Decimal.fromInt(100000));
    expect(
      created.calculatorVersion,
      LifeEventScenarioEngine.calculatorVersion,
    );
    expect(await outbox.depth(), 1);

    await repository.linkAction(id: created.id, actionId: 'action-1');
    expect((await repository.watchAll().first).single.actionId, 'action-1');

    await repository.review(
      id: created.id,
      actualOutcome: engine.observe(baseline),
      evidence: FinancialDecisionReviewEvidence(
        observedAt: DateTime.utc(2026, 10, 17),
        sourceRowFamilies: const <String>['fin:accounts'],
        dataCompleteness: 0.8,
      ),
      now: DateTime.utc(2026, 10, 17),
    );
    final restored = await repository.watchAll().first;
    expect(restored.single.actualOutcome, isNotNull);
    expect(restored.single.reviewEvidence?.dataCompleteness, 0.8);
    expect(restored.single.reviewedAt?.toUtc(), DateTime.utc(2026, 10, 17));
    expect(await outbox.depth(), 3);

    await repository.remove(created.id);
    expect(await repository.watchAll().first, isEmpty);
    expect(await outbox.depth(), 4);
  });
}
