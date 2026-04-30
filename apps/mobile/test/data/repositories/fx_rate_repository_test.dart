import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/data/db/app_database.dart';
import 'package:naviwealth/data/repositories/fx_rate_repository.dart';

import '../db/test_database.dart';

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
    );
    expect(rate.base, 'USD');
    expect(rate.quote, 'CNY');
    // asOf normalised to a UTC calendar day.
    expect(rate.date, DateTime.utc(2026, 4, 28));

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

  test('deleteByNaturalKey removes the matching (base, quote, day) row',
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
  });
}
