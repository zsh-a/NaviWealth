import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/data/audit/domain_event.dart';
import 'package:naviwealth/data/audit/event_log_reader.dart';
import 'package:naviwealth/data/audit/event_log_writer.dart';
import 'package:naviwealth/data/db/app_database.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/repositories/account_repository.dart';
import 'package:naviwealth/data/repositories/manual_asset_repository.dart';
import 'package:naviwealth/data/repositories/price_repository.dart';

import '../db/test_database.dart';
import '../repositories/_stub_stamper.dart';

void main() {
  late AppDatabase db;
  late InMemoryOutboxStore outbox;
  late EventLogReader reader;

  setUp(() {
    db = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    reader = EventLogReader(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('EventLogWriter direct API', () {
    test('records created and field_changed with structured before/after',
        () async {
      final stamper = makeStubStamper();
      final writer = EventLogWriter(db: db);
      final created = await stamper.stamp();
      await writer.recordCreated(
        entityTable: 'assets',
        entityId: 'a-1',
        stamp: created,
        after: <String, Object?>{'last_price': '100', 'name': 'cash'},
      );
      final changed = await stamper.stamp();
      await writer.recordFieldChanged(
        entityTable: 'assets',
        entityId: 'a-1',
        stamp: changed,
        before: <String, Object?>{'last_price': '100'},
        after: <String, Object?>{'last_price': '300'},
        reason: '对账修正',
      );

      final events = await reader.listByEntity(
        entityTable: 'assets',
        entityId: 'a-1',
      );
      expect(events, hasLength(2));
      expect(events[0].kind, DomainEventKind.created);
      expect(events[0].after!['name'], 'cash');
      expect(events[0].before, isNull);
      expect(events[1].kind, DomainEventKind.fieldChanged);
      expect(events[1].before!['last_price'], '100');
      expect(events[1].after!['last_price'], '300');
      expect(events[1].reason, '对账修正');
      // Ordering by HLC means the create event comes before the change
      // even when the underlying recorded_at strings tie.
      expect(events[0].hlc.compareTo(events[1].hlc) < 0, isTrue);
    });

    test('field_changed with empty after is a no-op', () async {
      final stamper = makeStubStamper();
      final writer = EventLogWriter(db: db);
      final stamp = await stamper.stamp();
      await writer.recordFieldChanged(
        entityTable: 'assets',
        entityId: 'a-1',
        stamp: stamp,
        before: const <String, Object?>{},
        after: const <String, Object?>{},
      );
      expect(
        await reader.countByEntity(
          entityTable: 'assets',
          entityId: 'a-1',
        ),
        0,
      );
    });

    test('soft_deleted snapshots before-state and leaves after null',
        () async {
      final stamper = makeStubStamper();
      final writer = EventLogWriter(db: db);
      await writer.recordSoftDeleted(
        entityTable: 'accounts',
        entityId: 'acc-1',
        stamp: await stamper.stamp(),
        before: <String, Object?>{'name': '招行储蓄'},
        reason: 'cleanup',
      );
      final events = await reader.listByEntity(
        entityTable: 'accounts',
        entityId: 'acc-1',
      );
      expect(events.single.kind, DomainEventKind.softDeleted);
      expect(events.single.before!['name'], '招行储蓄');
      expect(events.single.after, isNull);
      expect(events.single.reason, 'cleanup');
    });

    test('deleteByEntity is a maintenance escape hatch and counts rows',
        () async {
      final stamper = makeStubStamper();
      final writer = EventLogWriter(db: db);
      await writer.recordCreated(
        entityTable: 'assets',
        entityId: 'a-1',
        stamp: await stamper.stamp(),
        after: const <String, Object?>{'name': 'x'},
      );
      await writer.recordCreated(
        entityTable: 'assets',
        entityId: 'a-2',
        stamp: await stamper.stamp(),
        after: const <String, Object?>{'name': 'y'},
      );
      final removed = await reader.deleteByEntity(
        entityTable: 'assets',
        entityId: 'a-1',
      );
      expect(removed, 1);
      // The other entity's history is untouched.
      expect(
        await reader.countByEntity(entityTable: 'assets', entityId: 'a-2'),
        1,
      );
    });
  });

  group('ManualAssetRepository writes audit rows', () {
    test('recordValuationAdjust 100 → 300 records before/after valuation',
        () async {
      final repo = ManualAssetRepository(
        db: db,
        outbox: outbox,
        stamper: makeStubStamper(),
        priceRepo: PriceRepository(
          db: db,
          outbox: outbox,
          stamper: makeStubStamper(),
        ),
      );
      final asset = await repo.createCash(
        accountId: 'acc-1',
        currency: 'CNY',
        balance: Decimal.parse('100'),
      );
      await repo.recordValuationAdjust(
        assetId: asset.id,
        newValuation: Decimal.parse('300'),
        reason: '对账修正',
      );

      final events = await reader.listByEntity(
        entityTable: 'assets',
        entityId: asset.id,
      );
      expect(events, hasLength(2));
      final change = events[1];
      expect(change.kind, DomainEventKind.fieldChanged);
      expect(change.before!['valuation'], '100');
      expect(change.after!['valuation'], '300');
      expect(change.before!['observed_on'], isA<String>());
      expect(change.after!['observed_on'], isA<String>());
      expect(change.reason, '对账修正');
    });

    test('softDelete records a soft_deleted audit event', () async {
      final repo = ManualAssetRepository(
        db: db,
        outbox: outbox,
        stamper: makeStubStamper(),
        priceRepo: PriceRepository(
          db: db,
          outbox: outbox,
          stamper: makeStubStamper(),
        ),
      );
      final asset = await repo.createCash(
        accountId: 'acc-1',
        currency: 'USD',
        balance: Decimal.parse('10'),
      );
      await repo.softDelete(asset.id);
      final events = await reader.listByEntity(
        entityTable: 'assets',
        entityId: asset.id,
      );
      expect(events.last.kind, DomainEventKind.softDeleted);
    });
  });

  group('AccountRepository writes audit rows', () {
    test('update only emits a row for the changed columns', () async {
      final repo = AccountRepository(
        db: db,
        outbox: outbox,
        stamper: makeStubStamper(),
      );
      final account = await repo.create(
        type: AccountType.bank,
        name: 'Original',
        currency: 'CNY',
      );
      await repo.update(account.id, name: 'Renamed', reason: 'typo');

      final events = await reader.listByEntity(
        entityTable: 'accounts',
        entityId: account.id,
      );
      expect(events, hasLength(2));
      final change = events.last;
      expect(change.kind, DomainEventKind.fieldChanged);
      expect(change.before!['name'], 'Original');
      expect(change.after!['name'], 'Renamed');
      expect(change.before!.containsKey('currency'), isFalse);
      expect(change.after!.containsKey('currency'), isFalse);
      expect(change.reason, 'typo');
    });

    test('clearInstitution serialises a JSON null in the after-snapshot',
        () async {
      final repo = AccountRepository(
        db: db,
        outbox: outbox,
        stamper: makeStubStamper(),
      );
      final account = await repo.create(
        type: AccountType.bank,
        name: 'A',
        currency: 'CNY',
        institution: '招商银行',
      );
      await repo.update(account.id, clearInstitution: true);

      final events = await reader.listByEntity(
        entityTable: 'accounts',
        entityId: account.id,
      );
      final change = events.last;
      expect(change.before!['institution'], '招商银行');
      expect(change.after!.containsKey('institution'), isTrue);
      expect(change.after!['institution'], isNull);
    });
  });

  // `ExpenseRepository` is read-only; all expense writes flow through
  // `JournalEntryRepository`.
}
