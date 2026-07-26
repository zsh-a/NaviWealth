import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/features/finance/income_strategy/data/income_strategy_plan_repository.dart';
import 'package:naviwealth/features/finance/income_strategy/domain/income_strategy.dart';

import '../../../../core/persistence/test_database.dart';
import '../../../../core/sync/_outbox_test_ext.dart';
import '../../data/repositories/_stub_stamper.dart';

void main() {
  late AppDatabase db;
  late InMemoryOutboxStore outbox;
  late IncomeStrategyPlanRepository repository;

  setUp(() {
    db = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    repository = IncomeStrategyPlanRepository(
      db: db,
      outbox: outbox,
      stamper: makeStubStamper(),
    );
  });

  tearDown(() => db.close());

  test('round-trips arbitrary sleeve combinations and limits', () async {
    final saved = await repository.upsert(
      assetId: 'us_stock:AAPL',
      symbol: 'AAPL',
      market: 'us_stock',
      currency: 'USD',
      enabledSleeves: const {
        IncomeStrategySleeveKind.dividends,
        IncomeStrategySleeveKind.leapsCall,
      },
      capitalBudget: Decimal.fromInt(50000),
      maxLeapsCost: Decimal.fromInt(5000),
      maxPositionWeight: Decimal.parse('0.2'),
      preserveDividend: true,
      allowSharesCalledAway: false,
    );

    final loaded = await repository.get(saved.assetId);
    expect(loaded?.enabledSleeves, const {
      IncomeStrategySleeveKind.dividends,
      IncomeStrategySleeveKind.leapsCall,
    });
    expect(loaded?.maxLeapsCost, Decimal.fromInt(5000));
    expect(outbox.queued.single.table, 'income_strategy_plans');
  });

  test('soft delete removes the plan from active reads', () async {
    final saved = await repository.upsert(
      assetId: 'us_stock:MSFT',
      symbol: 'MSFT',
      market: 'us_stock',
      currency: 'USD',
      enabledSleeves: const {IncomeStrategySleeveKind.dividends},
      preserveDividend: true,
      allowSharesCalledAway: false,
    );

    await repository.remove(saved);

    expect(await repository.get(saved.assetId), isNull);
    expect(outbox.queued, hasLength(2));
  });
}
