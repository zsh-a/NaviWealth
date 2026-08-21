import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

Widget _wrap({required bool hidden}) {
  return MaterialApp(
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: AmountPrivacyScope(
        hidden: hidden,
        child: const AppMetricCluster(
          items: [
            AppMetricItem(
              label: 'Assets',
              value: r'$12,345.00',
              sensitive: true,
            ),
            AppMetricItem(label: 'Accounts', value: '3'),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('masks only sensitive metric values', (tester) async {
    await tester.pumpWidget(_wrap(hidden: true));

    expect(find.text(r'$12,345.00'), findsNothing);
    expect(find.byType(AmountPrivacyPlaceholder), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('shows sensitive metrics when privacy is disabled', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(hidden: false));

    expect(find.text(r'$12,345.00'), findsOneWidget);
    expect(find.byType(AmountPrivacyPlaceholder), findsNothing);
  });
}
