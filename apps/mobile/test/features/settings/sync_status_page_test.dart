import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/auth/auth_session.dart';
import 'package:naviwealth/core/auth/providers.dart';
import 'package:naviwealth/core/config/app_config.dart';
import 'package:naviwealth/core/config/providers.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/domain_enums.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/providers.dart';
import 'package:naviwealth/core/sync/sync_status.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/settings/ui/sync_status_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../core/persistence/test_database.dart';

const _deviceId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

void main() {
  late AppDatabase db;
  late SyncStatusBus bus;

  setUp(() {
    db = makeTestDatabase();
    bus = SyncStatusBus(
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
  });

  tearDown(() async {
    await bus.close();
    await db.close();
  });

  Future<void> seedDiagnostics() async {
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
  }

  Widget wrap() {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((_) async => db),
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
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: FTheme(
          data: FThemes.slate.light.desktop,
          child: const SyncStatusPage(),
        ),
      ),
    );
  }

  Future<void> pumpPage(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await seedDiagnostics();
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets('renders diagnostics and reacts to status updates', (
    tester,
  ) async {
    await pumpPage(tester, const Size(900, 1600));

    expect(find.text('Sync Status'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('network down'), findsOneWidget);
    expect(find.text('Conflict diagnostics'), findsOneWidget);
    expect(find.textContaining('2 remote rows'), findsOneWidget);
    expect(find.textContaining('1 remote row was ignored'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Local rows'), findsOneWidget);
    expect(find.text('Pull cursor'), findsOneWidget);
    expect(find.text('#42'), findsOneWidget);
    expect(find.text('Remote rows'), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);
    expect(find.text('Local row counts (debug)'), findsOneWidget);
    expect(find.text('Accounts (user)'), findsOneWidget);

    bus.emit(
      SyncStatusEvent(
        status: SyncStatus.online,
        at: DateTime.utc(2026, 6, 19, 9, 1),
        lastSuccessAt: DateTime.now(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('All synced'), findsOneWidget);
    expect(find.text('Offline'), findsNothing);
    expect(find.text('network down'), findsNothing);
  });

  testWidgets('stacks stat tiles on compact width', (tester) async {
    await pumpPage(tester, const Size(320, 1400));

    final pendingY = tester.getTopLeft(find.text('Pending')).dy;
    final localRowsY = tester.getTopLeft(find.text('Local rows')).dy;
    final lastSyncY = tester.getTopLeft(find.text('Last sync')).dy;

    expect(pendingY, lessThan(localRowsY));
    expect(localRowsY, lessThan(lastSyncY));
  });

  testWidgets('lays out stat tiles in one row on wide width', (tester) async {
    await pumpPage(tester, const Size(900, 1400));

    final pendingY = tester.getTopLeft(find.text('Pending')).dy;
    final localRowsY = tester.getTopLeft(find.text('Local rows')).dy;
    final lastSyncY = tester.getTopLeft(find.text('Last sync')).dy;

    expect((pendingY - localRowsY).abs(), lessThan(1));
    expect((pendingY - lastSyncY).abs(), lessThan(1));
  });
}
