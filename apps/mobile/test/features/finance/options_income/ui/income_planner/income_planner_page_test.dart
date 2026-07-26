import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/options_income/data/providers.dart';
import 'package:naviwealth/features/finance/options_income/domain/approved_underlying.dart';
import 'package:naviwealth/features/finance/options_income/domain/opportunity_explanation.dart';
import 'package:naviwealth/features/finance/options_income/domain/option_contract.dart';
import 'package:naviwealth/features/finance/options_income/domain/options_opportunity.dart';
import 'package:naviwealth/features/finance/options_income/domain/options_strategy_profile.dart';
import 'package:naviwealth/features/finance/options_income/ui/income_planner/income_planner_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

SyncMeta _meta() => SyncMeta(
  ownerUserId: 'u',
  updatedAt: DateTime.utc(2026, 6, 20),
  updatedByDevice: 'd',
  hlc: const Hlc(wallMillis: 1, counter: 0, nodeId: 'd'),
);

OptionsStrategyProfile _profile() {
  return defaultProfileForMode(
    OptionsStrategyMode.balanced,
  ).copyWith(riskDisclosureAckAt: DateTime.utc(2026, 6, 20), sync: _meta());
}

ApprovedUnderlying _approvedUnderlying() {
  return ApprovedUnderlying(
    id: ApprovedUnderlying.idFor(market: AssetMarket.usStock, symbol: 'AAPL'),
    symbol: 'AAPL',
    market: AssetMarket.usStock,
    allowPut: true,
    allowCall: false,
    maxBuyPrice: Decimal.parse('200'),
    minSellPrice: null,
    notes: null,
    sync: _meta(),
  );
}

OptionsOpportunity _opportunity() {
  final fetchedAt = DateTime.utc(2026, 6, 20, 12);
  return OptionsOpportunity(
    strategy: OptionsStrategyKind.cashSecuredPut,
    contract: OptionContract(
      underlying: 'AAPL',
      market: AssetMarket.usStock,
      optionSymbol: 'AAPL260720P00190000',
      type: OptionType.put,
      expiration: DateTime.utc(2026, 7, 20),
      dte: 30,
      strike: Money.parse('190', 'USD'),
      bid: Money.parse('2.50', 'USD'),
      ask: Money.parse('2.60', 'USD'),
      mid: Money.parse('2.55', 'USD'),
      volume: 50,
      openInterest: 500,
      impliedVolatility: Decimal.parse('0.25'),
      delta: Decimal.parse('-0.20'),
      underlyingPrice: Money.parse('200', 'USD'),
      bidAskSpreadPct: Decimal.parse('0.0392'),
      fetchedAt: fetchedAt,
    ),
    metrics: OpportunityMetrics(
      premium: Money.parse('255', 'USD'),
      cashRequired: Money.parse('19000', 'USD'),
      breakeven: Money.parse('187.45', 'USD'),
      staticReturn: Decimal.parse('0.0134'),
      annualizedYield: Decimal.parse('0.1630'),
      marginOfSafety: Decimal.parse('0.0627'),
    ),
    risk: OpportunityRiskLevel.moderate,
    explanation: OpportunityExplanation(
      summary: 'AAPL put',
      whyGood: const ['yield'],
      whyRisky: const ['assignment'],
      bestFor: 'cash flow',
      avoidIf: 'no assignment',
      worstCase: 'assigned shares',
      scoreBreakdown: {'yield': Decimal.parse('0.75')},
    ),
    score: Decimal.parse('0.75'),
    scannedAt: fetchedAt,
    scanId: 'scan-1',
  );
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        optionsStrategyProfileProvider.overrideWith((ref) {
          return Stream.value(_profile());
        }),
        approvedUnderlyingsProvider.overrideWith((ref) {
          return Stream.value([_approvedUnderlying()]);
        }),
        cachedOpportunitiesProvider.overrideWith((ref) async {
          return [_opportunity()];
        }),
        latestScanStateProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en', 'US'),
        home: const IncomePlannerPage(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('opportunity card shows total premium', (tester) async {
    await _pump(tester);

    expect(find.text('Total premium'), findsOneWidget);
    expect(find.text('USD 255'), findsOneWidget);
  });
}
