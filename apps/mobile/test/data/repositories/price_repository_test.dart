import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/op.dart';
import 'package:naviwealth/data/db/app_database.dart';
import 'package:naviwealth/data/repositories/price_repository.dart';

import '../../core/sync/_outbox_test_ext.dart';
import '../db/test_database.dart';
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

  test('record inserts a row and queues an insert op', () async {
    final p = await repo.record(
      unit: 'us_stock:AAPL',
      quoteCurrency: 'USD',
      observedOn: DateTime.utc(2026, 5, 1),
      perUnit: Decimal.parse('190.55'),
      source: 'manual',
    );
    expect(p.perUnit, Decimal.parse('190.55'));
    final batch = await outbox.peekBatch();
    expect(batch, hasLength(1));
    expect(batch.single.tableName, 'prices');
    expect(batch.single.opType, OpType.insert);
    expect(batch.single.fieldsDiff!['source'], 'manual');
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

  test('softDelete tombstones the row and queues a delete op', () async {
    final p = await repo.record(
      unit: 'us_stock:AAPL',
      quoteCurrency: 'USD',
      observedOn: DateTime.utc(2026, 5, 1),
      perUnit: Decimal.parse('190.55'),
      source: 'manual',
    );
    await outbox.ack((await outbox.peekBatch()).map((o) => o.opId).toList());

    await repo.softDelete(p.id);
    final latest = await repo.latestAt(
      unit: 'us_stock:AAPL',
      quoteCurrency: 'USD',
      asOf: DateTime.utc(2026, 6, 1),
    );
    expect(latest, isNull, reason: 'softDelete should hide the row');
    final batch = await outbox.peekBatch();
    expect(batch.single.opType, OpType.delete);
    expect(batch.single.fieldsDiff, isNull);
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
