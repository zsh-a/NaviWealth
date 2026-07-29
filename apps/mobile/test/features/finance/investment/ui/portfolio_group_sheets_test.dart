import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/finance/investment/data/investment_portfolio_providers.dart';
import 'package:naviwealth/features/finance/investment/domain/strategy/portfolio_strategy.dart';
import 'package:naviwealth/features/finance/investment/domain/strategy/portfolio_strategy_template.dart';
import 'package:naviwealth/features/finance/investment/ui/portfolio_group_sheets.dart';
import 'package:naviwealth/features/finance/rebalance/domain/portfolio_rebalance_group.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_models.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  testWidgets('sleeve editor exposes sleeve and rule delete actions', (
    tester,
  ) async {
    final sync = SyncMeta(
      ownerUserId: 'u-test',
      updatedAt: DateTime.utc(2026, 7, 29),
      updatedByDevice: 'test',
      hlc: Hlc.zero('test'),
    );
    final group = PortfolioRebalanceGroup(
      id: 'portfolio::group::index',
      portfolioId: 'portfolio',
      name: 'Core',
      strategyKind: PortfolioStrategyKind.indexCore,
      targetWeightBps: 10000,
      driftBandBps: 500,
      transferPolicy: GroupTransferPolicy.bidirectional,
      internalTarget: const TargetAllocation(weights: {AssetCategory.etf: 1}),
      createdAt: DateTime.utc(2026, 7, 29),
      archived: false,
      sync: sync,
    );
    final destinationGroup = PortfolioRebalanceGroup(
      id: 'portfolio::group::income',
      portfolioId: 'portfolio',
      name: 'Income',
      strategyKind: PortfolioStrategyKind.dividendIncome,
      targetWeightBps: 0,
      driftBandBps: 500,
      transferPolicy: GroupTransferPolicy.inflowsOnly,
      internalTarget: const TargetAllocation(weights: {AssetCategory.stock: 1}),
      createdAt: DateTime.utc(2026, 7, 29),
      archived: false,
      sync: sync,
    );
    const overlayKind = PortfolioStrategyKind('user:guard');
    final overlay = PortfolioStrategyConfig(
      id: 'portfolio::strategy::guard',
      portfolioId: 'portfolio',
      kind: overlayKind,
      schemaVersion: 1,
      enabled: true,
      capitalRole: StrategyCapitalRole.overlay,
      rebalanceGroupId: group.id,
      settings: const OpaquePortfolioStrategySettings({}),
      sync: sync,
    );
    final overlayTemplate = PortfolioStrategyTemplate(
      kind: overlayKind,
      localizedNames: const {'en': 'Risk guard'},
      iconToken: 'shield',
      schemaVersion: 1,
      defaultCapitalRole: StrategyCapitalRole.overlay,
      defaultSettings: const OpaquePortfolioStrategySettings({}),
      defaultInternalTarget: const TargetAllocation(
        weights: {AssetCategory.cash: 1},
      ),
      defaultDriftBandBps: 500,
      defaultTransferPolicy: GroupTransferPolicy.isolated,
      createdAt: DateTime.utc(2026, 7, 29),
      archived: false,
      sync: sync,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          portfolioRebalanceGroupsProvider.overrideWith(
            (ref) => Stream.value([group, destinationGroup]),
          ),
          portfolioStrategyConfigsProvider.overrideWith(
            (ref) => Stream.value([overlay]),
          ),
          portfolioStrategyTemplatesProvider.overrideWithValue(
            AsyncData([...kBuiltInPortfolioStrategyTemplates, overlayTemplate]),
          ),
        ],
        child: FTheme(
          data: FThemes.slate.light.desktop,
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Scaffold(
              body: SingleChildScrollView(
                child: PortfolioGroupsSection(portfolioId: group.portfolioId),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Core'));
    await tester.pumpAndSettle();

    expect(find.text('Rules and enhancements'), findsOneWidget);
    expect(find.text('Risk guard'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Delete sleeve'), findsOneWidget);

    await tester.tap(find.text('Delete sleeve'));
    await tester.pumpAndSettle();

    expect(find.text('Transfer to'), findsOneWidget);
    expect(find.text('Income'), findsWidgets);
    expect(find.text('Transfer and delete'), findsOneWidget);
  });
}
