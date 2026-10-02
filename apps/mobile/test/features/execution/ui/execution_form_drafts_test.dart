import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/forms/forms.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/execution/data/execution_repository.dart';
import 'package:naviwealth/features/execution/data/providers.dart';
import 'package:naviwealth/features/execution/ui/execution_plan_sheet.dart';
import 'package:naviwealth/features/execution/ui/execution_progress_sheet.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/test_database.dart';

void main() {
  for (final progress in [false, true]) {
    testWidgets(
      '${progress ? 'progress' : 'plan'} restores context-scoped draft and explicit discard clears it',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final preferences = await SharedPreferences.getInstance();
        final store = LocalFormDraftStore(preferences, owner: 'owner');
        final key = progress
            ? 'execution.progress.new::plan-one'
            : 'execution.plan.new';
        await store.write(
          key,
          progress
              ? {'note': 'Unfinished progress', 'kind': 'scopeChange'}
              : {
                  'title': 'Unfinished plan',
                  'description': 'Long plan description',
                  'target': '2026-12-01T00:00:00.000Z',
                },
        );
        final db = makeTestDatabase();
        addTearDown(db.close);
        final repo = ExecutionRepository(db: db, outbox: InMemoryOutboxStore());
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(preferences),
              activeUserIdProvider.overrideWithValue('owner'),
              executionOwnerUserIdProvider.overrideWith((_) async => 'owner'),
              executionRepositoryProvider.overrideWith((_) async => repo),
            ],
            child: MaterialApp(
              theme: AppTheme.light(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('en'),
              home: FTheme(
                data: FTheme.neutral.light.desktop,
                child: Builder(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      onPressed: () => progress
                          ? showExecutionProgressSheet(
                              context: context,
                              planId: 'plan-one',
                            )
                          : showExecutionPlanSheet(context: context),
                      child: const Text('Open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.text('Restore draft'), findsOneWidget);
        await tester.tap(find.text('Restore draft'));
        await tester.pumpAndSettle();
        expect(
          find.text(progress ? 'Unfinished progress' : 'Unfinished plan'),
          findsOneWidget,
        );
        if (!progress) {
          expect(find.text('Long plan description'), findsOneWidget);
        }
        await tester.tapAt(const Offset(4, 4));
        await tester.pumpAndSettle();
        final l10n = lookupAppLocalizations(const Locale('en'));
        await tester.tap(find.text(l10n.unsavedChangesDiscard));
        await tester.pumpAndSettle();
        expect(store.read(key), isNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
      },
    );
  }
}
