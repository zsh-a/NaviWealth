import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/execution/data/execution_repository.dart';
import 'package:naviwealth/features/execution/data/providers.dart';
import 'package:naviwealth/features/execution/ui/execution_action_sheet.dart';
import 'package:naviwealth/features/execution/ui/execution_plan_sheet.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../../support/test_app_theme.dart';

void main() {
  for (final plan in [false, true]) {
    testWidgets(
      '${plan ? 'plan' : 'action'} locks capture fields until a failed save finishes',
      (tester) async {
        final pending = Completer<ExecutionRepository>();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              executionRepositoryProvider.overrideWith((_) => pending.future),
              executionPlansProvider.overrideWith(
                (_) => Stream.value(const []),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.light(),
              builder: buildTestAppTheme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('en'),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => plan
                        ? showExecutionPlanSheet(context: context)
                        : showExecutionActionSheet(context: context),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(EditableText).first,
          'Keep my input',
        );
        await tester.pump();
        final l10n = lookupAppLocalizations(const Locale('en'));
        await tester.tap(find.text(l10n.commonSave));
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          tester.widget<AppBusyButton>(find.byType(AppBusyButton)).busy,
          isTrue,
        );
        expect(
          tester.widget<EditableText>(find.byType(EditableText).first).readOnly,
          isTrue,
        );
        expect(
          tester
              .widgetList<SegmentedRow<dynamic>>(
                find.byWidgetPredicate((widget) => widget is SegmentedRow),
              )
              .every((row) => row.onChanged == null),
          isTrue,
        );
        pending.completeError(StateError('Save unavailable'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          tester.widget<EditableText>(find.byType(EditableText).first).readOnly,
          isFalse,
        );
        expect(find.text('Keep my input'), findsOneWidget);
        expect(
          tester.widget<AppBusyButton>(find.byType(AppBusyButton)).busy,
          isFalse,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 7));
      },
    );
  }
}
