import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/home/ui/home_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  testWidgets('home quick actions stay stable on narrow screens', (
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
              child: HomeQuickActions(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Add account'), findsOneWidget);
    expect(find.text('Record entry'), findsOneWidget);
    expect(find.text('Import'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
