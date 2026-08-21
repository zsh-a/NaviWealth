import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/finance/home/ui/currency_mismatch_banner.dart';
import 'package:naviwealth/features/finance/market/domain/price_confidence.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

Widget _wrap({
  required List<CurrencyMismatch> mismatches,
  PriceConfidence? confidence = PriceConfidence.dailyClose,
  int staleHoldingCount = 0,
  bool empty = false,
  String baseCurrency = 'CNY',
  bool showHealthy = true,
}) {
  final zero = Money.zero(baseCurrency);
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en', 'US'),
    home: FTheme(
      data: FTheme.neutral.light.desktop,
      child: Scaffold(
        body: ValuationTrustNotice(
          showHealthy: showHealthy,
          snapshot: DashboardSnapshot(
            asOf: DateTime.utc(2026, 7, 31, 8),
            baseCurrency: baseCurrency,
            allocations: empty
                ? const []
                : [
                    CategoryAllocation(
                      category: AssetCategory.stock,
                      totalInBase: Money(Decimal.fromInt(100), baseCurrency),
                      items: const [],
                    ),
                  ],
            totalAssets: empty
                ? zero
                : Money(Decimal.fromInt(100), baseCurrency),
            totalLiabilities: zero,
            netWorth: empty ? zero : Money(Decimal.fromInt(100), baseCurrency),
            currencyMismatches: mismatches,
            staleHoldingCount: staleHoldingCount,
            confidenceFloor: confidence,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders nothing for an empty snapshot', (tester) async {
    await tester.pumpWidget(_wrap(mismatches: const [], empty: true));
    await tester.pumpAndSettle();

    expect(find.byType(AppStatusBanner), findsNothing);
  });

  testWidgets('shows quality and as-of for a trusted valuation', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(mismatches: const []));
    await tester.pumpAndSettle();

    expect(find.byType(AppStatusLine), findsOneWidget);
    expect(find.byType(AppStatusBanner), findsNothing);
    expect(find.textContaining('Daily close'), findsOneWidget);
  });

  testWidgets('can keep a trusted valuation quiet on summary surfaces', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(mismatches: const [], showHealthy: false));
    await tester.pumpAndSettle();

    expect(find.byType(AppStatusLine), findsNothing);
    expect(find.byType(AppStatusBanner), findsNothing);
  });

  testWidgets('still shows warnings when healthy status is suppressed', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        mismatches: const [CurrencyMismatch(id: 'aapl', currency: 'USD')],
        showHealthy: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppStatusBanner), findsOneWidget);
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

    expect(find.byType(AppStatusBanner), findsOneWidget);
    // Banner copy mentions the base currency code so the user knows what
    // the totals were expected to convert into.
    expect(find.textContaining('CNY'), findsOneWidget);
  });

  testWidgets('renders warning for stale valuations', (tester) async {
    await tester.pumpWidget(
      _wrap(
        mismatches: const [],
        confidence: PriceConfidence.stale,
        staleHoldingCount: 2,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('2 stale'), findsOneWidget);
  });

  testWidgets('tapping the banner opens the details sheet', (tester) async {
    await tester.pumpWidget(
      _wrap(
        mismatches: const [CurrencyMismatch(id: 'aapl', currency: 'USD')],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(AppStatusBanner));
    await tester.pumpAndSettle();

    // The sheet renders the offending holding's id + the conversion arrow.
    expect(find.text('USD → CNY'), findsOneWidget);
    expect(find.text('aapl'), findsOneWidget);
  });
}
