// On-device integration test (docs/testing-strategy.md section 6).
//
// This covers a high-value repository write through the production
// file-backed AppDatabase connection. Headless repository tests use
// NativeDatabase.memory; this test exercises the real platform file,
// migrations, JournalEntryRepository transaction, and Drift-backed sync
// outbox, then proves the data survives a close / reopen.
//
// Run:
//   flutter test integration_test/journal_repository_integration_test.dart -d macos
//   flutter test integration_test/journal_repository_integration_test.dart -d <android|ios device>

import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/features/finance/data/domain/invariants.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../test/features/finance/data/repositories/_stub_stamper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const dbFileName = 'integration_journal_repository.sqlite';
  const deviceId = 'integration-device';

  Future<void> deleteDbFile() async {
    final dir = await getApplicationDocumentsDirectory();
    for (final suffix in ['', '-shm', '-wal']) {
      final file = File(p.join(dir.path, '$dbFileName$suffix'));
      if (file.existsSync()) file.deleteSync();
    }
  }

  setUp(deleteDbFile);
  tearDown(deleteDbFile);

  testWidgets(
    'JournalEntryRepository writes ledger rows and outbox through real DB',
    (tester) async {
      AppDatabase? openDb = AppDatabase.open(dbFileName: dbFileName);
      addTearDown(() async {
        await openDb?.close();
      });

      final repo = JournalEntryRepository(
        db: openDb,
        outbox: DriftOutboxStore(openDb),
        stamper: makeStubStamper(
          userId: 'integration-user',
          deviceId: deviceId,
        ),
        fxRateSource: const IdentityFxRateSource(),
        baseCurrency: 'USD',
      );

      final entry = await repo.create(
        entry: JournalEntryDraft(
          id: 'integration-je',
          date: DateTime.utc(2026, 6, 19),
          narration: 'Integration salary',
          payee: 'NaviWealth Test',
        ),
        postings: [
          PostingDraft(
            id: 'integration-posting-cash',
            accountId: 'cash',
            units: Decimal.parse('-125.50'),
            unit: 'USD',
          ),
          PostingDraft(
            id: 'integration-posting-income',
            accountId: 'income',
            units: Decimal.parse('125.50'),
            unit: 'USD',
          ),
        ],
      );

      expect(entry.entry.id, 'integration-je');
      expect(entry.postings.map((p) => p.id), [
        'integration-posting-cash',
        'integration-posting-income',
      ]);
      expect(
        await repo.balanceByAccountUnit('cash', 'USD'),
        Decimal.parse('-125.50'),
      );
      expect(await DriftOutboxStore(openDb).depth(), 3);

      await openDb.close();
      openDb = null;

      final reopened = AppDatabase.open(dbFileName: dbFileName);
      openDb = reopened;
      final reopenedRepo = JournalEntryRepository(
        db: reopened,
        outbox: DriftOutboxStore(reopened),
        stamper: makeStubStamper(
          userId: 'integration-user',
          deviceId: deviceId,
        ),
        fxRateSource: const IdentityFxRateSource(),
        baseCurrency: 'USD',
      );

      final persisted = await reopenedRepo.getById('integration-je');
      expect(persisted, isNotNull);
      expect(persisted!.entry.narration, 'Integration salary');
      expect(persisted.entry.payee, 'NaviWealth Test');
      expect(persisted.postings.map((p) => p.id), [
        'integration-posting-cash',
        'integration-posting-income',
      ]);
      expect(
        await reopenedRepo.balanceByAccountUnit('cash', 'USD'),
        Decimal.parse('-125.50'),
      );

      final pointers = await DriftPendingRows(reopened).pointers();
      expect(pointers, hasLength(3));
      expect(pointers.map((p) => p.table).toSet(), {
        'journal_entries',
        'postings',
      });
      expect(pointers.map((p) => p.rowId).toSet(), {
        'integration-je',
        'integration-posting-cash',
        'integration-posting-income',
      });
    },
  );
}
