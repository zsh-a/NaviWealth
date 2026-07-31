import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/fire/data/fire_plan_repository.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_plan.dart';

import '../../../../core/persistence/test_database.dart';
import '../../data/repositories/_stub_stamper.dart';

void main() {
  late AppDatabase db;
  late InMemoryOutboxStore outbox;
  late FirePlanRepository repo;

  setUp(() {
    db = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    repo = FirePlanRepository(
      db: db,
      outbox: outbox,
      stamper: makeStubStamper(userId: 'u-fire'),
    );
  });

  tearDown(() => db.close());

  test('upsert restores the complete plan and queues sync', () async {
    final plan = FirePlan.unset(baseCurrency: 'USD').copyWith(
      targetNetWorth: Decimal.parse('1250000.50'),
      monthlyExpenses: Decimal.parse('4500'),
      monthlySurplus: Decimal.parse('7000'),
      inflationRate: 0.025,
      safeWithdrawalRate: 0.035,
      targetCashBucketMonths: 18,
      lifestyleMode: FireLifestyleMode.coast,
      reserves: [
        FireReserve(
          id: 'medical',
          label: 'Medical',
          amount: Money(Decimal.parse('20000'), 'USD'),
          kind: FireReserveKind.medical,
        ),
      ],
      riskSettings: const FireRiskSettings(
        marketDrawdownPct: 0.45,
        expenseShockPct: 0.25,
        fxShockPct: 0.15,
        oneOffShockAmount: 10000,
      ),
    );

    await repo.upsert(plan);
    final restored = await repo.get('u-fire');

    expect(restored, plan);
    expect(await outbox.depth(), 1);
  });

  test('watch emits a later upsert for device restore consumers', () async {
    final emissions = <FirePlan?>[];
    final subscription = repo.watch('u-fire').listen(emissions.add);
    addTearDown(subscription.cancel);

    await Future<void>.delayed(Duration.zero);
    final plan = FirePlan.unset(
      baseCurrency: 'CNY',
    ).copyWith(targetNetWorth: Decimal.fromInt(800000));
    await repo.upsert(plan);
    await Future<void>.delayed(Duration.zero);

    expect(emissions, contains(plan));
  });
}
