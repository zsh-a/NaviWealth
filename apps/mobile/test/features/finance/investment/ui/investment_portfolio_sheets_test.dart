import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/finance/investment/data/investment_portfolio_providers.dart';
import 'package:naviwealth/features/finance/investment/domain/models/investment_portfolio.dart';
import 'package:naviwealth/features/finance/investment/domain/strategy/portfolio_strategy.dart';
import 'package:naviwealth/features/finance/investment/domain/strategy/portfolio_strategy_template.dart';
import 'package:naviwealth/features/finance/investment/ui/investment_portfolio_sheets.dart';
import 'package:naviwealth/features/finance/rebalance/domain/portfolio_rebalance_group.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_models.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_universe.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  testWidgets(
    'portfolio deletion asks where to transfer target and assignments',
    (tester) async {
      final sync = SyncMeta(
        ownerUserId: 'u-test',
        updatedAt: DateTime.utc(2026, 7, 29),
        updatedByDevice: 'test',
        hlc: Hlc.zero('test'),
      );
      InvestmentPortfolio portfolio(String id, String name) {
        return InvestmentPortfolio(
          id: id,
          name: name,
          baseCurrency: 'USD',
          goalId: null,
          color: null,
          createdAt: DateTime.utc(2026, 7, 29),
          archived: false,
          sync: sync,
        );
      }

      PortfolioRebalanceGroup group({
        required String id,
        required String portfolioId,
        required String name,
        required int weight,
      }) {
        return PortfolioRebalanceGroup(
          id: id,
          portfolioId: portfolioId,
          name: name,
          strategyKind: PortfolioStrategyKind.indexCore,
          targetWeightBps: weight,
          driftBandBps: 500,
          transferPolicy: GroupTransferPolicy.bidirectional,
          internalTarget: const TargetAllocation(
            weights: {AssetCategory.stock: 1},
          ),
          createdAt: DateTime.utc(2026, 7, 29),
          archived: false,
          sync: sync,
        );
      }

      final source = portfolio('source', 'Long term');
      final destination = portfolio('destination', 'Reserve');
      final groups = [
        group(
          id: 'source-group',
          portfolioId: source.id,
          name: 'Core',
          weight: 10000,
        ),
        group(
          id: 'destination-group',
          portfolioId: destination.id,
          name: 'Income',
          weight: 10000,
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            investmentPortfoliosProvider.overrideWith(
              (ref) => Stream.value([source, destination]),
            ),
            portfolioStrategyConfigsProvider.overrideWith(
              (ref) => Stream.value(const []),
            ),
            portfolioRebalanceGroupsProvider.overrideWith(
              (ref) => Stream.value(groups),
            ),
            portfolioCapitalAssignmentsProvider.overrideWith(
              (ref) => Stream.value(const []),
            ),
            portfolioStrategyTemplatesProvider.overrideWithValue(
              const AsyncData(kBuiltInPortfolioStrategyTemplates),
            ),
            activeUniversePortfolioTargetsProvider.overrideWithValue(
              AsyncData([
                PortfolioAllocationTarget(
                  id: 'source-target',
                  universeId: 'universe',
                  portfolioId: source.id,
                  targetWeightBps: 3000,
                  driftBandBps: 500,
                  transferPolicy: GroupTransferPolicy.bidirectional,
                  sync: sync,
                ),
                PortfolioAllocationTarget(
                  id: 'destination-target',
                  universeId: 'universe',
                  portfolioId: destination.id,
                  targetWeightBps: 7000,
                  driftBandBps: 500,
                  transferPolicy: GroupTransferPolicy.bidirectional,
                  sync: sync,
                ),
              ]),
            ),
          ],
          child: FTheme(
            data: FTheme.neutral.light.desktop,
            child: MaterialApp(
              theme: AppTheme.light(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('en'),
              home: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: FButton(
                      onPress: () => showInvestmentPortfolioFormSheet(
                        context,
                        existing: source,
                      ),
                      child: const Text('Open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final deleteButton = find.text('Delete portfolio');
      expect(deleteButton, findsOneWidget);
      await tester.scrollUntilVisible(
        deleteButton,
        200,
        scrollable: find
            .byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            )
            .last,
      );
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();

      expect(find.text('Transfer to'), findsOneWidget);
      expect(find.text('Reserve · Income'), findsOneWidget);
      expect(find.text('Transfer and delete'), findsOneWidget);
      expect(find.textContaining('30% target'), findsOneWidget);
    },
  );
}
