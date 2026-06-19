import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/domain_enums.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/providers.dart';
import 'package:naviwealth/core/sync/sync_status.dart';
import 'package:naviwealth/features/finance/data/diagnostics/local_table_counts.dart';

import '../../core/persistence/test_database.dart';

void main() {
  late AppDatabase db;
  late SyncStatusBus bus;
  late ProviderContainer container;

  setUp(() {
    db = makeTestDatabase();
    bus = SyncStatusBus(
      initial: SyncStatusEvent(
        status: SyncStatus.idle,
        at: DateTime.utc(2026, 6, 19, 9),
      ),
    );
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((_) async => db),
        syncStatusBusProvider.overrideWithValue(bus),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await bus.close();
    await db.close();
  });

  Future<void> emitStatus() async {
    bus.emit(
      SyncStatusEvent(
        status: SyncStatus.online,
        at: DateTime.utc(2026, 6, 19, 9, 1),
      ),
    );
    await Future<void>.delayed(Duration.zero);
  }

  Future<T> waitForProviderValue<T>(
    ProviderListenable<AsyncValue<T>> provider,
    bool Function(T value) matches,
  ) async {
    final completer = Completer<T>();
    late final ProviderSubscription<AsyncValue<T>> subscription;
    subscription = container.listen<AsyncValue<T>>(provider, (_, next) {
      next.whenData((value) {
        if (!completer.isCompleted && matches(value)) {
          completer.complete(value);
        }
      });
    }, fireImmediately: true);
    addTearDown(subscription.close);
    return completer.future.timeout(const Duration(seconds: 2));
  }

  group('sync diagnostics providers', () {
    test('status stream seeds late readers with the current event', () async {
      final event = await waitForProviderValue<SyncStatusEvent>(
        syncStatusEventStreamProvider,
        (value) => value.status == SyncStatus.idle,
      );

      expect(event.status, SyncStatus.idle);
      expect(event.at, DateTime.utc(2026, 6, 19, 9));

      bus.emit(
        SyncStatusEvent(
          status: SyncStatus.offline,
          at: DateTime.utc(2026, 6, 19, 9, 2),
          lastError: 'network',
        ),
      );

      final next = await waitForProviderValue<SyncStatusEvent>(
        syncStatusEventStreamProvider,
        (value) => value.status == SyncStatus.offline,
      );
      expect(next.lastError, 'network');
    });

    test(
      'cursor, local HLC, and outbox depth refresh on status events',
      () async {
        await waitForProviderValue<int>(
          syncCursorProvider,
          (value) => value == 0,
        );
        await waitForProviderValue<Hlc?>(
          syncLocalHlcProvider,
          (value) => value == null,
        );
        await waitForProviderValue<int>(
          syncOutboxDepthProvider,
          (value) => value == 0,
        );

        final cursors = DriftCursorStore(db);
        await cursors.writeSeq(42);
        const hlc = Hlc(wallMillis: 42, counter: 1, nodeId: 'dev-1');
        await cursors.writeLocalHlc(hlc);
        await DriftOutboxStore(db).enqueue(table: 'accounts', rowId: 'acc-1');

        await emitStatus();

        expect(
          await waitForProviderValue<int>(
            syncCursorProvider,
            (value) => value == 42,
          ),
          42,
        );
        expect(
          await waitForProviderValue<Hlc?>(
            syncLocalHlcProvider,
            (value) => value == hlc,
          ),
          hlc,
        );
        expect(
          await waitForProviderValue<int>(
            syncOutboxDepthProvider,
            (value) => value == 1,
          ),
          1,
        );
      },
    );

    test('finance local table counts refresh on status events', () async {
      final initial = await waitForProviderValue<LocalTableCounts>(
        financeLocalTableCountsProvider,
        (value) => value['accounts_user'] == 0,
      );
      expect(initial['accounts_user'], 0);

      await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              id: 'acc-1',
              type: AccountCategory.cash,
              name: 'Cash',
              currency: 'CNY',
              category: const Value(AccountSide.asset),
              ownerUserId: 'user-1',
              updatedAt: DateTime.utc(2026, 6, 19),
              updatedByDevice: 'dev-1',
              hlc: const Hlc(wallMillis: 42, counter: 1, nodeId: 'dev-1'),
            ),
          );

      await emitStatus();

      final counts = await waitForProviderValue<LocalTableCounts>(
        financeLocalTableCountsProvider,
        (value) => value['accounts_user'] == 1,
      );
      expect(counts['accounts_user'], 1);
      expect(counts['accounts_system'], 0);
    });
  });
}
