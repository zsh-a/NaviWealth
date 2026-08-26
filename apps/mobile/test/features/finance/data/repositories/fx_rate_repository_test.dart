import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/features/finance/data/repositories/fx_rate_repository.dart';
import 'package:naviwealth/features/finance/domain/fx/fx_rate.dart';

import '../../../../core/persistence/test_database.dart';

void main() {
  late AppDatabase db;
  late FxRateRepository repo;

  setUp(() {
    db = makeTestDatabase();
    repo = FxRateRepository(db: db);
  });

  tearDown(() async {
    await db.close();
  });

  test('upsertDaily inserts a new rate and reads back via watchAll', () async {
    final rate = await repo.upsertDaily(
      baseCurrency: 'USD',
      quoteCurrency: 'CNY',
      rate: Decimal.parse('7.2'),
      asOf: DateTime.utc(2026, 4, 28, 13, 30),
      fetchedAt: DateTime.utc(2026, 4, 28, 14),
    );
    expect(rate.base, 'USD');
    expect(rate.quote, 'CNY');
    // asOf normalised to a UTC calendar day.
    expect(rate.date, DateTime.utc(2026, 4, 28));
    expect(rate.fetchedAt, DateTime.utc(2026, 4, 28, 14));

    final all = await repo.listAll();
    expect(all, hasLength(1));
    expect(all.single.rate, Decimal.parse('7.2'));
  });

  test('upsertDaily replaces an existing same-day row', () async {
    await repo.upsertDaily(
      baseCurrency: 'usd',
      quoteCurrency: 'cny',
      rate: Decimal.parse('7.10'),
      asOf: DateTime.utc(2026, 4, 28),
    );
    await repo.upsertDaily(
      baseCurrency: 'USD',
      quoteCurrency: 'CNY',
      rate: Decimal.parse('7.20'),
      asOf: DateTime.utc(2026, 4, 28, 23, 59),
    );
    final all = await repo.listAll();
    expect(all, hasLength(1));
    expect(all.single.rate, Decimal.parse('7.20'));
  });

  test(
    'upsertDailyBatch writes all days and keeps the last duplicate',
    () async {
      final first = FxRate(
        base: 'USD',
        quote: 'CNY',
        date: DateTime.utc(2026, 4, 27),
        rate: Decimal.parse('7.18'),
        source: 'history',
        fetchedAt: DateTime.utc(2026, 4, 28),
      );
      final replacement = FxRate(
        base: 'USD',
        quote: 'CNY',
        date: DateTime.utc(2026, 4, 27, 18),
        rate: Decimal.parse('7.19'),
        source: 'history',
        fetchedAt: DateTime.utc(2026, 4, 29),
      );
      final second = FxRate(
        base: 'USD',
        quote: 'CNY',
        date: DateTime.utc(2026, 4, 28),
        rate: Decimal.parse('7.20'),
        source: 'history',
        fetchedAt: DateTime.utc(2026, 4, 29),
      );

      final written = await repo.upsertDailyBatch([first, replacement, second]);

      expect(written, hasLength(2));
      final all = await repo.listAll();
      expect(all, hasLength(2));
      expect(all.map((rate) => rate.rate), [
        Decimal.parse('7.19'),
        Decimal.parse('7.20'),
      ]);
    },
  );

  test('latestDateForPair returns only the requested pair', () async {
    await repo.upsertDaily(
      baseCurrency: 'USD',
      quoteCurrency: 'CNY',
      rate: Decimal.parse('7.20'),
      asOf: DateTime.utc(2026, 4, 28),
    );
    await repo.upsertDaily(
      baseCurrency: 'HKD',
      quoteCurrency: 'CNY',
      rate: Decimal.parse('0.92'),
      asOf: DateTime.utc(2026, 4, 30),
    );

    expect(
      await repo.latestDateForPair(base: 'usd', quote: 'cny'),
      DateTime.utc(2026, 4, 28),
    );
    expect(await repo.latestDateForPair(base: 'CNY', quote: 'JPY'), isNull);
  });

  test('upsertDaily rejects same-currency pairs and non-positive rates', () {
    expect(
      () => repo.upsertDaily(
        baseCurrency: 'USD',
        quoteCurrency: 'usd',
        rate: Decimal.parse('1'),
        asOf: DateTime.utc(2026, 4, 28),
      ),
      throwsArgumentError,
    );
    expect(
      () => repo.upsertDaily(
        baseCurrency: 'USD',
        quoteCurrency: 'CNY',
        rate: Decimal.zero,
        asOf: DateTime.utc(2026, 4, 28),
      ),
      throwsArgumentError,
    );
  });

  test(
    'deleteByNaturalKey removes the matching (base, quote, day) row',
    () async {
      await repo.upsertDaily(
        baseCurrency: 'USD',
        quoteCurrency: 'CNY',
        rate: Decimal.parse('7.20'),
        asOf: DateTime.utc(2026, 4, 28),
      );
      await repo.upsertDaily(
        baseCurrency: 'HKD',
        quoteCurrency: 'CNY',
        rate: Decimal.parse('0.92'),
        asOf: DateTime.utc(2026, 4, 28),
      );
      await repo.deleteByNaturalKey(
        base: 'usd',
        quote: 'cny',
        // Pass an intra-day timestamp to confirm normalisation works.
        date: DateTime.utc(2026, 4, 28, 9, 15),
      );
      final all = await repo.listAll();
      expect(all, hasLength(1));
      expect(all.single.base, 'HKD');
    },
  );
}
