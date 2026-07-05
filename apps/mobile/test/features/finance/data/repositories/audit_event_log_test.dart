import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/audit/domain_event.dart';
import 'package:naviwealth/core/audit/event_log_reader.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/features/finance/data/repositories/account_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/manual_asset_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/price_repository.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';

import '../../../../core/persistence/test_database.dart';
import '_stub_stamper.dart';

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

  group('ManualAssetRepository writes audit rows', () {
    test(
      'recordValuationAdjust 100 -> 300 records before/after valuation',
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
      },
    );

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
        type: AccountCategory.bank,
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

    test(
      'clearInstitution serialises a JSON null in the after-snapshot',
      () async {
        final repo = AccountRepository(
          db: db,
          outbox: outbox,
          stamper: makeStubStamper(),
        );
        final account = await repo.create(
          type: AccountCategory.bank,
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
      },
    );
  });
}
