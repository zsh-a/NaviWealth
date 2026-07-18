import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
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
import 'package:naviwealth/core/sync/sync_stability.dart';
import 'package:naviwealth/core/sync/sync_status.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/data/diagnostics/local_table_counts.dart';
import 'package:naviwealth/features/settings/ui/sync/sync_status_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../../core/persistence/test_database.dart';

const _deviceId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const _financeDiagnosticsPack = DomainPack(
  scope: DomainScope.finance,
  localTableCountsBuilder: financeLocalTableCounts,
);

SyncStabilitySample _stabilitySample({
  required DateTime at,
  bool success = true,
  int fatalFailures = 0,
  int generationResetFailures = 0,
}) => SyncStabilitySample(
  at: at,
  success: success,
  retryableFailures: success ? 0 : 1,
  fatalFailures: fatalFailures,
  localWins: 0,
  ignoredRows: 0,
  generationResets: 0,
  generationResetFailures: generationResetFailures,
);

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
    final stability = DriftSyncStabilityStore(db);
    for (var index = 0; index < 10; index++) {
      await stability.record(
        SyncStabilitySample(
          at: DateTime.utc(2026, 6, 1).add(Duration(days: index * 2)),
          success: true,
          retryableFailures: 0,
          fatalFailures: 0,
          localWins: 0,
          ignoredRows: 0,
          generationResets: 0,
          generationResetFailures: 0,
        ),
      );
    }
  }

  Widget wrap({
    bool disableAnimations = false,
    SyncStabilityReport? stabilityReport,
  }) {
    return ProviderScope(
      key: ValueKey<String>(
        'sync-${stabilityReport?.gateStatus.name ?? 'database'}',
      ),
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
        if (stabilityReport != null)
          syncStabilityReportProvider.overrideWith(
            (ref) async => stabilityReport,
          ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(disableAnimations: disableAnimations),
            child: child!,
          );
        },
        home: FTheme(
          data: FThemes.slate.light.desktop,
          child: const SyncStatusPage(),
        ),
      ),
    );
  }

  Future<void> pumpPage(
    WidgetTester tester,
    Size size, {
    bool disableAnimations = false,
    SyncStabilityReport? stabilityReport,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await seedDiagnostics();
    await tester.pumpWidget(
      wrap(
        disableAnimations: disableAnimations,
        stabilityReport: stabilityReport,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets('renders diagnostics and reacts to status updates', (
    tester,
  ) async {
    MethodCall? clipboardCall;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') clipboardCall = call;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pumpPage(tester, const Size(900, 1600));

    expect(find.text('Sync Status'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('network down'), findsOneWidget);
    expect(find.text('Conflict diagnostics'), findsOneWidget);
    expect(find.text('Stability gate passed'), findsOneWidget);
    expect(
      find.text('All local release thresholds are currently met'),
      findsOneWidget,
    );
    expect(find.text('Success 100%'), findsOneWidget);
    expect(
      find.text('Device-local aggregate · no row payloads or ids retained'),
      findsOneWidget,
    );
    expect(find.text('Copy evidence'), findsOneWidget);
    await tester.tap(find.text('Copy evidence'));
    await tester.pumpAndSettle();
    expect(clipboardCall?.method, 'Clipboard.setData');
    final clipboardArguments =
        clipboardCall?.arguments as Map<Object?, Object?>;
    final evidence =
        jsonDecode(clipboardArguments['text']! as String)
            as Map<String, Object?>;
    expect(evidence['gate_status'], 'passing');
    expect(evidence, isNot(contains('row_ids')));
    expect(evidence, isNot(contains('payloads')));
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

  testWidgets('explains collecting and failing stability thresholds', (
    tester,
  ) async {
    final start = DateTime.utc(2026, 6, 1);
    await pumpPage(
      tester,
      const Size(900, 1600),
      stabilityReport: SyncStabilityReport(
        samples: <SyncStabilitySample>[
          for (var day = 0; day < 3; day++)
            _stabilitySample(at: start.add(Duration(days: day))),
        ],
      ),
    );

    expect(find.text('Collecting stability evidence'), findsOneWidget);
    expect(
      find.text(
        '7 more terminal cycles needed · 12 more observation days needed',
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(
      wrap(
        stabilityReport: SyncStabilityReport(
          samples: <SyncStabilitySample>[
            for (var index = 0; index < 9; index++)
              _stabilitySample(at: start.add(Duration(days: index * 2))),
            _stabilitySample(
              at: start.add(const Duration(days: 18)),
              success: false,
              fatalFailures: 1,
              generationResetFailures: 1,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sync stability needs attention'), findsOneWidget);
    expect(
      find.text(
        'Needs at least 95% success · Fatal protocol errors must return to zero · Generation-reset failures must return to zero',
      ),
      findsOneWidget,
    );
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

  testWidgets('syncing status is static when motion is disabled', (
    tester,
  ) async {
    await pumpPage(tester, const Size(900, 1400), disableAnimations: true);
    bus.emit(
      SyncStatusEvent(
        status: SyncStatus.syncing,
        at: DateTime.utc(2026, 6, 19, 9, 1),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Syncing…'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
