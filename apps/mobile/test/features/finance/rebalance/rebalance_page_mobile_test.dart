import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/investment/domain/strategy/portfolio_strategy.dart';
import 'package:naviwealth/features/finance/rebalance/data/rebalance_providers.dart';
import 'package:naviwealth/features/finance/rebalance/domain/hierarchical_rebalance_engine.dart';
import 'package:naviwealth/features/finance/rebalance/domain/portfolio_rebalance_group.dart';
import 'package:naviwealth/features/finance/rebalance/ui/rebalance_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import 'data/rebalance_execution_test_fixtures.dart';

void main() {
  testWidgets('mobile flow focuses on capital transfers before asset trades', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final internalPlan = testPlan();
    final core = PortfolioRebalanceGroup(
      id: 'core',
      portfolioId: 'portfolio',
      name: 'Core',
      strategyKind: PortfolioStrategyKind.indexCore,
      targetWeightBps: 5000,
      driftBandBps: 500,
      transferPolicy: GroupTransferPolicy.bidirectional,
      internalTarget: internalPlan.target,
      createdAt: testNow,
      archived: false,
      sync: testSync(),
    );
    final income = PortfolioRebalanceGroup(
      id: 'income',
      portfolioId: 'portfolio',
      name: 'Income',
      strategyKind: PortfolioStrategyKind.dividendIncome,
      targetWeightBps: 5000,
      driftBandBps: 500,
      transferPolicy: GroupTransferPolicy.inflowsOnly,
      internalTarget: internalPlan.target,
      createdAt: testNow,
      archived: false,
      sync: testSync(counter: 2),
    );
    final plan = PortfolioRebalancePlan(
      totalAssets: Money(Decimal.fromInt(1000), 'USD'),
      transfers: [
        GroupCapitalTransfer(
          fromGroupId: core.id,
          toGroupId: income.id,
          amount: Money(Decimal.fromInt(100), 'USD'),
          explanation: 'Move excess capital.',
        ),
      ],
      groups: [
        GroupRebalancePlan(
          group: core,
          capitalDecision: GroupCapitalDecision(
            groupId: core.id,
            groupName: core.name,
            actualWeight: 0.6,
            targetWeight: 0.5,
            actualAmount: Money(Decimal.fromInt(600), 'USD'),
            targetAmount: Money(Decimal.fromInt(500), 'USD'),
            action: GroupCapitalAction.transferOut,
            explanation: 'Above target.',
          ),
          internalPlan: internalPlan,
        ),
        GroupRebalancePlan(
          group: income,
          capitalDecision: GroupCapitalDecision(
            groupId: income.id,
            groupName: income.name,
            actualWeight: 0.4,
            targetWeight: 0.5,
            actualAmount: Money(Decimal.fromInt(400), 'USD'),
            targetAmount: Money(Decimal.fromInt(500), 'USD'),
            action: GroupCapitalAction.transferIn,
            explanation: 'Below target.',
          ),
          internalPlan: internalPlan,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rebalancePlanProvider.overrideWithValue(internalPlan),
          hierarchicalRebalancePlanProvider.overrideWithValue(plan),
          universeRebalancePlanProvider.overrideWithValue(null),
          activeRebalanceExecutionProvider.overrideWith((ref) async => null),
          effectiveSelectedPortfolioRebalanceGroupIdProvider.overrideWithValue(
            core.id,
          ),
        ],
        child: FTheme(
          data: FThemes.slate.light.desktop,
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: const RebalancePage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Resolve transfer'), findsOneWidget);
    expect(find.text('Core'), findsWidgets);
    expect(find.text('Income'), findsWidgets);
    expect(find.textContaining('Complete the capital movements'), findsOne);
    expect(find.text('3 · Rebalance assets inside the sleeve'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
