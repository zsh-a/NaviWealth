import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/app/routing/route_paths.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/cashflow/data/dividend_center_providers.dart';
import 'package:naviwealth/features/finance/cashflow/domain/dividend_center.dart';
import 'package:naviwealth/features/finance/cashflow/ui/dividend_center_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  testWidgets('empty state CTA routes to corporate action entry page', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: AppRoutes.cashflowDividends,
      routes: [
        GoRoute(
          path: AppRoutes.cashflowDividends,
          builder: (_, _) => const DividendCenterPage(),
        ),
        GoRoute(
          path: AppRoutes.wealthCorporateAction,
          builder: (_, _) => const Scaffold(
            body: Center(child: Text('Corporate action target')),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dividendCenterSnapshotProvider.overrideWith(
            (_) async => _emptySnapshot(),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No dividend records yet'), findsOneWidget);
    await tester.tap(find.byKey(const Key('dividend-center-record-cta')));
    await tester.pumpAndSettle();

    expect(find.text('Corporate action target'), findsOneWidget);
  });
}

DividendCenterSnapshot _emptySnapshot() => DividendCenterSnapshot(
  baseCurrency: 'USD',
  yearToDateGross: Decimal.zero,
  ttmGross: Decimal.zero,
  priorYearToDateGross: Decimal.zero,
  ttmWithholding: Decimal.zero,
  events: const [],
  ranking: const [],
  months: const [],
);
