import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/features/finance/runway/data/runway_forecast_repository.dart';
import 'package:naviwealth/features/finance/runway/domain/money_runway.dart';

import '../../../../core/persistence/test_database.dart';

void main() {
  late AppDatabase db;
  late RunwayForecastRepository repository;

  setUp(() {
    db = makeTestDatabase();
    repository = RunwayForecastRepository(db: db, ownerUserId: 'owner-1');
  });
  tearDown(() => db.close());

  test(
    'scores a complete target-day balance and preserves its instant',
    () async {
      await repository.recordAndEvaluate(_snapshot(DateTime.utc(2026, 1, 1)));
      final observedAt = DateTime.utc(2026, 1, 31, 17, 42);
      expect(
        await repository.recordAndEvaluate(_snapshot(observedAt, balance: 900)),
        isTrue,
      );
      final quality = await repository.quality();
      expect(quality.evaluatedCount, 1);
      expect(quality.meanRelativeError, closeTo(0.1, 0.0001));

      final row = await _firstForecast(db);
      expect(
        row['target_at'],
        DateTime.utc(2026, 1, 31).millisecondsSinceEpoch,
      );
      expect(row['observed_at'], observedAt.millisecondsSinceEpoch);
      expect(row['evaluation_status'], 'comparable');
      expect(row['observed_balance'], '900');
      expect(row['observed_currency'], 'CNY');
      expect(row['observed_data_completeness'], 1.0);
      expect(row['observed_balance_is_complete'], 1);
    },
  );

  test('a later balance never becomes a missed target-day actual', () async {
    await repository.recordAndEvaluate(_snapshot(DateTime.utc(2026, 1, 1)));
    final later = _snapshot(DateTime.utc(2026, 3, 2), balance: 100);
    await repository.recordAndEvaluate(later);

    final quality = await repository.quality();
    expect(quality.evaluatedCount, 0);
    expect(quality.meanRelativeError, isNull);
    final row = await _firstForecast(db);
    expect(row['evaluation_status'], 'late');
    expect(row['observed_at'], later.observedAt.millisecondsSinceEpoch);
    expect(row['observed_balance'], '100');
    expect(row['absolute_error'], isNull);

    // Reopening cannot rewrite the already classified observation.
    expect(
      await repository.recordAndEvaluate(
        _snapshot(DateTime.utc(2026, 3, 3), balance: 500),
      ),
      isFalse,
    );
    expect((await _firstForecast(db))['observed_balance'], '100');
  });

  test(
    'an observation before the UTC target day leaves evaluation pending',
    () async {
      await repository.recordAndEvaluate(_snapshot(DateTime.utc(2026, 1, 1)));
      await repository.recordAndEvaluate(
        _snapshot(DateTime.parse('2026-01-31T07:59:00+08:00'), balance: 900),
      );
      expect((await _firstForecast(db))['evaluation_status'], isNull);
      expect((await repository.quality()).evaluatedCount, 0);

      await repository.recordAndEvaluate(
        _snapshot(DateTime.parse('2026-01-31T08:00:00+08:00'), balance: 800),
      );
      expect(
        (await repository.quality()).meanRelativeError,
        closeTo(.2, .0001),
      );
    },
  );

  test('incomplete observations can recover only on the target day', () async {
    await repository.recordAndEvaluate(_snapshot(DateTime.utc(2026, 1, 1)));
    await repository.recordAndEvaluate(
      _snapshot(DateTime.utc(2026, 1, 31, 8), balanceIsComplete: false),
    );
    expect((await repository.quality()).evaluatedCount, 0);
    expect((await _firstForecast(db))['evaluation_status'], 'incomplete');
    expect((await _firstForecast(db))['absolute_error'], isNull);

    await repository.recordAndEvaluate(
      _snapshot(DateTime.utc(2026, 1, 31, 9), balance: 900),
    );
    expect((await repository.quality()).evaluatedCount, 1);
    expect((await _firstForecast(db))['evaluation_status'], 'comparable');

    await repository.recordAndEvaluate(
      _snapshot(DateTime.utc(2026, 1, 31, 10), balance: 700),
    );
    expect((await _firstForecast(db))['observed_balance'], '900');
  });

  test(
    'a next-day repair cannot turn incomplete evidence into an error score',
    () async {
      await repository.recordAndEvaluate(_snapshot(DateTime.utc(2026, 1, 1)));
      await repository.recordAndEvaluate(
        _snapshot(DateTime.utc(2026, 1, 31), balanceIsComplete: false),
      );
      await repository.recordAndEvaluate(
        _snapshot(DateTime.utc(2026, 2, 1), balance: 900),
      );
      expect((await repository.quality()).evaluatedCount, 0);
      expect((await _firstForecast(db))['evaluation_status'], 'incomplete');
    },
  );

  test(
    'an incomplete starting balance is never a comparable forecast',
    () async {
      await repository.recordAndEvaluate(
        _snapshot(DateTime.utc(2026, 1, 1), balanceIsComplete: false),
      );
      await repository.recordAndEvaluate(_snapshot(DateTime.utc(2026, 1, 31)));
      expect((await repository.quality()).evaluatedCount, 0);
      expect((await _firstForecast(db))['evaluation_status'], 'incomplete');
    },
  );

  test(
    'short flow history does not make a fully valued cash balance incomplete',
    () async {
      await repository.recordAndEvaluate(
        _snapshot(DateTime.utc(2026, 1, 1), dataCompleteness: .25),
      );
      await repository.recordAndEvaluate(
        _snapshot(
          DateTime.utc(2026, 1, 31),
          balance: 900,
          dataCompleteness: .4,
        ),
      );
      expect((await repository.quality()).evaluatedCount, 1);
      final row = await _firstForecast(db);
      expect(row['data_completeness'], .25);
      expect(row['observed_data_completeness'], .4);
    },
  );

  test(
    'different currencies retain evidence without comparing amounts',
    () async {
      await repository.recordAndEvaluate(_snapshot(DateTime.utc(2026, 1, 1)));
      await repository.recordAndEvaluate(
        _snapshot(DateTime.utc(2026, 1, 31, 8), currency: 'USD', balance: 140),
      );
      expect((await repository.quality()).evaluatedCount, 0);
      final row = await _firstForecast(db);
      expect(row['currency'], 'CNY');
      expect(row['observed_currency'], 'USD');
      expect(row['evaluation_status'], 'currencyMismatch');
      expect(row['absolute_error'], isNull);

      await repository.recordAndEvaluate(
        _snapshot(DateTime.utc(2026, 1, 31, 9), balance: 900),
      );
      expect((await repository.quality()).evaluatedCount, 1);
    },
  );

  test(
    'zero normalization base does not inflate the evaluated count',
    () async {
      await repository.recordAndEvaluate(
        _snapshot(DateTime.utc(2026, 1, 1), balance: 0),
      );
      await repository.recordAndEvaluate(
        _snapshot(DateTime.utc(2026, 1, 31), balance: 100),
      );
      final quality = await repository.quality();
      expect(quality.evaluatedCount, 0);
      expect(quality.meanRelativeError, isNull);
      expect((await _firstForecast(db))['evaluation_status'], 'zeroBaseline');
      expect((await _firstForecast(db))['absolute_error'], isNull);
    },
  );

  test(
    'quality uses the latest twelve comparable observations for its owner',
    () async {
      for (var day = 1; day <= 13; day++) {
        await repository.recordAndEvaluate(
          _snapshot(DateTime.utc(2026, 1, day)),
        );
      }
      for (var day = 1; day <= 13; day++) {
        await repository.recordAndEvaluate(
          _snapshot(
            DateTime.utc(2026, 1, day + 30),
            balance: day == 1 ? 100 : 900,
          ),
        );
      }
      final quality = await repository.quality();
      expect(quality.evaluatedCount, 12);
      expect(quality.meanRelativeError, closeTo(.1, .0001));
      final other = RunwayForecastRepository(db: db, ownerUserId: 'other');
      expect((await other.quality()).evaluatedCount, 0);
    },
  );
}

Future<Map<String, Object?>> _firstForecast(AppDatabase db) async =>
    (await db.customSelect('''
SELECT * FROM runway_forecast_snapshots
WHERE owner_user_id = 'owner-1' AND as_of_day = '2026-01-01'
  AND horizon_days = 30
''').getSingle()).data;

MoneyRunwaySnapshot _snapshot(
  DateTime observedAt, {
  int balance = 1000,
  String currency = 'CNY',
  bool balanceIsComplete = true,
  double dataCompleteness = 1,
}) => buildMoneyRunway(
  asOf: observedAt,
  currency: currency,
  startingBalance: Decimal.fromInt(balance),
  reserveTarget: Decimal.zero,
  averageMonthlyExpense: Decimal.zero,
  estimatedDailyVariableOutflow: Decimal.zero,
  scheduledFlows: const [],
  confidence: MoneyRunwayConfidence.high,
  dataCompleteness: dataCompleteness,
  balanceIsComplete: balanceIsComplete,
);
