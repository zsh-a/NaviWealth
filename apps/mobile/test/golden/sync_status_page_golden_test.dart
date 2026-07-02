import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/auth_session.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/auth/providers.dart';
import 'package:naviwealth/core/config/app_config.dart';
import 'package:naviwealth/core/config/providers.dart';
import 'package:naviwealth/core/lifeos/domain_pack.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/domain_enums.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/providers.dart';
import 'package:naviwealth/core/sync/sync_status.dart';
import 'package:naviwealth/features/finance/data/diagnostics/local_table_counts.dart';
import 'package:naviwealth/features/settings/ui/sync_status_page.dart';

import '../core/persistence/test_database.dart';
import '_golden_setup.dart';

const _deviceId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
final _goldenNow = DateTime.utc(2026, 6, 19, 14);
const _financeDiagnosticsPack = DomainPack(
  scope: DomainScope.finance,
  localTableCountsBuilder: financeLocalTableCounts,
);

void main() {
  runAllVariants('sync_status_page_diagnostics', (tester, variant) async {
    final db = makeTestDatabase();
    final bus = SyncStatusBus(
      initial: SyncStatusEvent(
        status: SyncStatus.offline,
        at: DateTime.utc(2026, 6, 19, 9),
        lastError: 'network down',
        conflicts: const SyncConflictDiagnostics(
          remoteRows: 3,
          appliedRows: 1,
          localWins: 2,
          ignoredRows: 1,
        ),
      ),
    );
    addTearDown(() async {
      await bus.close();
      await db.close();
    });

    await DriftCursorStore(db).writeSeq(42);
    await DriftOutboxStore(db).enqueue(table: 'accounts', rowId: 'acc-1');
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

    await pumpAndSnapshotMobile(
      tester,
      name: 'sync_status_page_diagnostics',
      variant: variant,
      overrides: [
        appDatabaseProvider.overrideWith((_) async => db),
        activeDomainPacksProvider.overrideWithValue([_financeDiagnosticsPack]),
        syncStatusBusProvider.overrideWithValue(bus),
        authSessionProvider.overrideWith(
          (_) => AuthSession(
            accessToken: 'token',
            expiresAt: DateTime.utc(2099),
            userId: 'user-1',
            deviceId: _deviceId,
          ),
        ),
        appConfigProvider.overrideWithValue(
          const AppConfig(
            apiBaseUrl: 'https://api.test',
            environment: AppEnvironment.dev,
          ),
        ),
      ],
      child: SyncStatusPage(now: _goldenNow),
    );
  });
}
