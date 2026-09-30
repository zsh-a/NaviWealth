import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/execution/data/providers.dart';
import 'package:naviwealth/features/execution/domain/execution_models.dart';
import 'package:naviwealth/features/execution/ui/execution_action_sheet.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

Widget _wrap({ExecutionAction? action}) => ProviderScope(
  overrides: [
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
