import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/features/finance/data/repositories/price_repository.dart';

import '../../../../core/persistence/test_database.dart';
import '../../../../core/sync/_outbox_test_ext.dart';
import '_stub_stamper.dart';

void main() {
  late AppDatabase db;
  late InMemoryOutboxStore outbox;
  late PriceRepository repo;

  setUp(() {
    db = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    repo = PriceRepository(db: db, outbox: outbox, stamper: makeStubStamper());
  });

  tearDown(() async {
    await db.close();
  });

  test('record inserts a row and queues a dirty pointer', () async {
    final p = await repo.record(
      unit: 'us_stock:AAPL',
      quoteCurrency: 'USD',
      observedOn: DateTime.utc(2026, 5, 1),
      perUnit: Decimal.parse('190.55'),
      source: 'manual',
    );
    expect(p.perUnit, Decimal.parse('190.55'));
    final batch = outbox.queued;
    expect(batch, hasLength(1));
    expect(batch.single.table, 'prices');
    expect(batch.single.rowId, p.id);
  });

  test(
    'latestAt returns the most recent observation on or before the date',
    () async {
      await repo.record(
        unit: 'us_stock:AAPL',
        quoteCurrency: 'USD',
        observedOn: DateTime.utc(2026, 4, 1),
        perUnit: Decimal.parse('150.00'),
        source: 'manual',
      );
      await repo.record(
        unit: 'us_stock:AAPL',
        quoteCurrency: 'USD',
        observedOn: DateTime.utc(2026, 5, 1),
        perUnit: Decimal.parse('190.00'),
        source: 'manual',
      );
      await repo.record(
        unit: 'us_stock:AAPL',
        quoteCurrency: 'USD',
        observedOn: DateTime.utc(2026, 6, 1),
        perUnit: Decimal.parse('210.00'),
        source: 'manual',
      );
      final mid = await repo.latestAt(
        unit: 'us_stock:AAPL',
        quoteCurrency: 'USD',
        asOf: DateTime.utc(2026, 5, 15),
      );
      expect(mid?.perUnit, Decimal.parse('190.00'));
      final start = await repo.latestAt(
        unit: 'us_stock:AAPL',
        quoteCurrency: 'USD',
        asOf: DateTime.utc(2026, 3, 1),
      );
      expect(start, isNull);
    },
  );

  test('softDelete tombstones the row and queues a dirty pointer', () async {
    final p = await repo.record(
      unit: 'us_stock:AAPL',
      quoteCurrency: 'USD',
      observedOn: DateTime.utc(2026, 5, 1),
      perUnit: Decimal.parse('190.55'),
      source: 'manual',
    );
    outbox.clearQueued();

    await repo.softDelete(p.id);
    final latest = await repo.latestAt(
      unit: 'us_stock:AAPL',
      quoteCurrency: 'USD',
      asOf: DateTime.utc(2026, 6, 1),
    );
    expect(latest, isNull, reason: 'softDelete should hide the row');
    final batch = outbox.queued;
    expect(batch, hasLength(1));
    expect(batch.single.table, 'prices');
    expect(batch.single.rowId, p.id);
  });

  test('record rejects non-positive prices', () async {
    expect(
      () => repo.record(
        unit: 'us_stock:AAPL',
        quoteCurrency: 'USD',
        observedOn: DateTime.utc(2026, 5, 1),
        perUnit: Decimal.zero,
        source: 'manual',
      ),
      throwsArgumentError,
    );
  });
}
