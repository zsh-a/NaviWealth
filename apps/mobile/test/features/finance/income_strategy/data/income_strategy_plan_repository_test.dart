import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/features/finance/income_strategy/data/income_strategy_plan_repository.dart';
import 'package:naviwealth/features/finance/income_strategy/domain/income_strategy.dart';
import 'package:naviwealth/features/finance/income_strategy/domain/income_strategy_plan.dart';

import '../../../../core/persistence/test_database.dart';
import '../../data/repositories/_stub_stamper.dart';

void main() {
  test('round-trips open module intents and scopes reads by owner', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final outbox = InMemoryOutboxStore();
    final repo = IncomeStrategyPlanRepository(
      db: db,
      outbox: outbox,
      stamper: makeStubStamper(userId: 'user-1'),
    );
    final intents = <IncomeStrategySleeveKind, IncomeStrategySleeveIntent>{
      IncomeStrategySleeveKind.wheel: IncomeStrategySleeveIntent(
        kind: IncomeStrategySleeveKind.wheel,
        enabled: true,
        settings: {
          WheelIncomeStrategySettings.maxAssignmentValue:
              IncomeStrategyDecimalSetting(Decimal.parse('5000')),
        },
      ),
      const IncomeStrategySleeveKind(
        'bond_ladder',
      ): const IncomeStrategySleeveIntent(
        kind: IncomeStrategySleeveKind('bond_ladder'),
        enabled: true,
      ),
    };

    final saved = await repo.upsert(
      assetId: 'nasdaq:AAPL',
      symbol: 'aapl',
      market: 'nasdaq',
      currency: 'usd',
      sleeveIntents: intents,
    );
    final loaded = await repo.get(
      ownerUserId: 'user-1',
      assetId: 'nasdaq:AAPL',
    );

    expect(saved.id, isNot('nasdaq:AAPL'));
    expect(loaded?.symbol, 'AAPL');
    expect(
      loaded
          ?.intent(IncomeStrategySleeveKind.wheel)
          ?.decimalValue(WheelIncomeStrategySettings.maxAssignmentValue),
      Decimal.parse('5000'),
    );
    expect(
      loaded?.enabledSleeves,
      contains(const IncomeStrategySleeveKind('bond_ladder')),
    );
    expect(
      await repo.get(ownerUserId: 'user-2', assetId: 'nasdaq:AAPL'),
      isNull,
    );
  });

  test('round-trips strategy group membership', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final repo = IncomeStrategyPlanRepository(
      db: db,
      outbox: InMemoryOutboxStore(),
      stamper: makeStubStamper(userId: 'user-1'),
    );

    await repo.upsert(
      assetId: 'nasdaq:TQQQ',
      symbol: 'TQQQ',
      market: 'nasdaq',
      currency: 'usd',
      sleeveIntents: {
        IncomeStrategySleeveKind.wheel: const IncomeStrategySleeveIntent(
          kind: IncomeStrategySleeveKind.wheel,
          enabled: true,
        ),
      },
      groupId: 'g1',
      groupLabel: 'QQQ enhanced',
    );

    final loaded = await repo.get(
      ownerUserId: 'user-1',
      assetId: 'nasdaq:TQQQ',
    );
    expect(loaded?.groupId, 'g1');
    expect(loaded?.groupLabel, 'QQQ enhanced');

    // Clearing the group persists null again.
    await repo.upsert(
      assetId: 'nasdaq:TQQQ',
      symbol: 'TQQQ',
      market: 'nasdaq',
      currency: 'usd',
      sleeveIntents: loaded!.sleeveIntents,
    );
    final cleared = await repo.get(
      ownerUserId: 'user-1',
      assetId: 'nasdaq:TQQQ',
    );
    expect(cleared?.groupId, isNull);
    expect(cleared?.groupLabel, isNull);
  });
}
