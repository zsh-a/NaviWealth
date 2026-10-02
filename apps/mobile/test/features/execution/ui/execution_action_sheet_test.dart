import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/forms/local_form_draft.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/execution/data/providers.dart';
import 'package:naviwealth/features/execution/domain/execution_models.dart';
import 'package:naviwealth/features/execution/ui/execution_action_sheet.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap({ExecutionAction? action, SharedPreferences? preferences}) =>
    ProviderScope(
      overrides: [
        if (preferences != null)
          sharedPreferencesProvider.overrideWithValue(preferences),
        if (preferences != null)
          activeUserIdProvider.overrideWithValue('owner'),
        executionPlansProvider.overrideWith((_) => Stream.value(const [])),
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
                onPressed: () =>
                    showExecutionActionSheet(context: context, action: action),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('action draft restores input and explicit discard clears it', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final store = LocalFormDraftStore(preferences, owner: 'owner');
    await store.write('execution.action.new:', {
      'title': 'Continue this action',
      'priority': 'high',
      'note': 'Unfinished note',
    });
    await tester.pumpWidget(_wrap(preferences: preferences));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Restore draft'), findsOneWidget);
    await tester.tap(find.text('Restore draft'));
    await tester.pumpAndSettle();
    expect(find.text('Continue this action'), findsOneWidget);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    final l10n = lookupAppLocalizations(const Locale('en'));
    await tester.tap(find.text(l10n.unsavedChangesDiscard));
    await tester.pumpAndSettle();
    expect(store.read('execution.action.new:'), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('typing an action is protected from barrier dismissal', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).first, 'Keep this action');
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(find.text(l10n.unsavedChangesTitle), findsOneWidget);
    await tester.tap(find.text(l10n.unsavedChangesKeepEditing));
    await tester.pumpAndSettle();
    expect(find.text('Keep this action'), findsOneWidget);
  });

  testWidgets('schedule conflict is shown next to the dates before a write', (
    tester,
  ) async {
    final action = ExecutionAction(
      id: 'a',
      title: 'Review plan',
      createdAt: DateTime.utc(2026),
      scheduledFor: DateTime.utc(2026, 10, 2),
      dueAt: DateTime.utc(2026, 10, 1),
      sync: SyncMeta(
        ownerUserId: 'owner',
        updatedAt: DateTime.utc(2026),
        updatedByDevice: 'device',
        hlc: Hlc.zero('device'),
      ),
    );
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(action: action));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final l10n = lookupAppLocalizations(const Locale('en'));
    await tester.tap(find.text(l10n.commonSave));
    await tester.pumpAndSettle();
    expect(find.text(l10n.executionScheduleAfterDue), findsOneWidget);
    expect(find.text('Review plan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
