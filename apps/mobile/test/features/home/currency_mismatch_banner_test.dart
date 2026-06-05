import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/features/home/data/dashboard_providers.dart';
import 'package:naviwealth/features/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/home/ui/currency_mismatch_banner.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

Widget _wrap({
  required List<CurrencyMismatch> mismatches,
  String baseCurrency = 'CNY',
}) {
  return ProviderScope(
    overrides: [
      dashboardCurrencyMismatchesProvider.overrideWithValue(mismatches),
      dashboardBaseCurrencyProvider.overrideWithValue(baseCurrency),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en', 'US'),
      home: FTheme(
        data: FThemes.slate.light.desktop,
        child: const Scaffold(body: CurrencyMismatchNotice()),
      ),
    ),
  );
}

void main() {
  testWidgets('renders nothing when there are no mismatches', (tester) async {
    await tester.pumpWidget(_wrap(mismatches: const []));
    await tester.pumpAndSettle();

    expect(find.byIcon(FLucideIcons.triangleAlert), findsNothing);
  });

  testWidgets('renders warning when mismatches are present', (tester) async {
    await tester.pumpWidget(
      _wrap(
        mismatches: const [
          CurrencyMismatch(id: 'aapl', currency: 'USD'),
          CurrencyMismatch(id: 'tsla', currency: 'USD'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(FLucideIcons.triangleAlert), findsOneWidget);
    // Banner copy mentions the base currency code so the user knows what
    // the totals were expected to convert into.
    expect(find.textContaining('CNY'), findsOneWidget);
  });

  testWidgets('tapping the banner opens the details sheet', (tester) async {
    await tester.pumpWidget(
      _wrap(
        mismatches: const [CurrencyMismatch(id: 'aapl', currency: 'USD')],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(FLucideIcons.triangleAlert));
    await tester.pumpAndSettle();

    // The sheet renders the offending holding's id + the conversion arrow.
    expect(find.text('USD → CNY'), findsOneWidget);
    expect(find.text('aapl'), findsOneWidget);
  });
}
