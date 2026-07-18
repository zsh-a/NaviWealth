import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/database_encryption.dart';
import 'package:naviwealth/core/persistence/database_unlock_gate.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import 'test_database.dart';

Widget _wrap({
  required Future<AppDatabase> Function() database,
  DatabaseRecoveryController? recovery,
}) {
  return ProviderScope(
    retry: (_, _) => null,
    overrides: [
      appDatabaseProvider.overrideWith((_) => database()),
      if (recovery != null)
        databaseRecoveryControllerProvider.overrideWithValue(recovery),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => FTheme(
        data: FThemes.slate.light.desktop,
        child: AppMessenger.init(child: child ?? const SizedBox.shrink()),
      ),
      home: const DatabaseUnlockGate(child: Text('Private database content')),
    ),
  );
}

void main() {
  testWidgets('shows app content only after the database resolves', (
    tester,
  ) async {
    final completer = Completer<AppDatabase>();
    final database = makeTestDatabase();
    addTearDown(database.close);

    await tester.pumpWidget(_wrap(database: () => completer.future));
    await tester.pump();
    expect(find.text('Unlocking your local data…'), findsOneWidget);
    expect(find.text('Private database content'), findsNothing);

    completer.complete(database);
    await tester.pumpAndSettle();
    expect(find.text('Private database content'), findsOneWidget);
  });

  testWidgets('offers confirmed local reset when the device key is missing', (
    tester,
  ) async {
    var resetCalls = 0;
    final recovery = DatabaseRecoveryController(
      resetDatabase: () async => resetCalls++,
      invalidateDatabase: () {},
    );
    const error = DatabaseEncryptionException(
      DatabaseEncryptionFailureCode.keyMissing,
      'fixture',
    );

    await tester.pumpWidget(
      _wrap(
        database: () => Future<AppDatabase>.error(error),
        recovery: recovery,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Local data is locked'), findsOneWidget);
    expect(find.text('Reset unreadable local data'), findsOneWidget);
    expect(resetCalls, 0);

    await tester.tap(find.text('Reset unreadable local data'));
    await tester.pumpAndSettle();
    expect(find.text('Reset unreadable local data?'), findsOneWidget);
    expect(resetCalls, 0);

    await tester.tap(find.text('Reset local data'));
    await tester.pumpAndSettle();
    expect(resetCalls, 1);
  });

  testWidgets('preserves migration failures and does not offer reset', (
    tester,
  ) async {
    const error = DatabaseEncryptionException(
      DatabaseEncryptionFailureCode.migrationFailed,
      'fixture',
    );

    await tester.pumpWidget(
      _wrap(database: () => Future<AppDatabase>.error(error)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Local data upgrade paused'), findsOneWidget);
    expect(find.text('Retry unlock'), findsOneWidget);
    expect(find.text('Reset unreadable local data'), findsNothing);
  });

  testWidgets('keeps unknown failures non-destructive', (tester) async {
    await tester.pumpWidget(
      _wrap(database: () => Future<AppDatabase>.error(StateError('fixture'))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Local data is unavailable'), findsOneWidget);
    expect(find.text('Retry unlock'), findsOneWidget);
    expect(find.text('Reset unreadable local data'), findsNothing);
  });
}
