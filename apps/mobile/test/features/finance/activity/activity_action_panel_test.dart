import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/activity/ui/activity_action_panel.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  testWidgets('activity quick add exposes income as a first-class flow', (
    tester,
  ) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en', 'US'),
        home: FTheme(
          data: FTheme.neutral.light.desktop,
          child: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FButton(
                  onPress: () => showActivityActionPanel(context),
                  child: const Text('Open actions'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Resolve the button's context from the mounted tree so the test does
    // not depend on a router just to inspect the action sheet contents.
    final host = find.ancestor(
      of: find.text('Open actions'),
      matching: find.byType(FButton),
    );
    await tester.tap(host);
    await tester.pumpAndSettle();

    expect(find.text(l10n.superFabIncome), findsOneWidget);
    expect(find.text(l10n.activityActionIncomeHint), findsOneWidget);
  });
}
