import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/home/ui/home_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  testWidgets('active home keeps a compact capture and transfer strip', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(240, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: FTheme(
          data: FThemes.slate.light.desktop,
          child: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(8),
              child: HomeQuickActions(mode: HomeQuickActionMode.active),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Record entry'), findsOneWidget);
    expect(find.text('Transfer'), findsOneWidget);
    expect(find.text('Add account'), findsNothing);
    expect(find.text('Import'), findsNothing);
    expect(find.byIcon(FLucideIcons.chevronRight), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('active home keeps the two-column strip on regular widths', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: FTheme(
          data: FThemes.slate.light.desktop,
          child: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(8),
              child: HomeQuickActions(mode: HomeQuickActionMode.active),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Record entry'), findsOneWidget);
    expect(find.text('Transfer'), findsOneWidget);
    expect(find.byIcon(FLucideIcons.chevronRight), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty home offers setup actions without record entry', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: FTheme(
          data: FThemes.slate.light.desktop,
          child: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(8),
              child: HomeQuickActions(mode: HomeQuickActionMode.onboarding),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Add account'), findsOneWidget);
    expect(find.text('Import'), findsOneWidget);
    expect(find.text('Record entry'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
