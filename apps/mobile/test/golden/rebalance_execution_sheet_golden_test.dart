import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/domain/values/money.dart';
import 'package:naviwealth/features/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/rebalance/domain/rebalance_models.dart';
import 'package:naviwealth/features/rebalance/ui/rebalance_execution_sheet.dart';
import 'package:naviwealth/l10n/gen/app_localizations_en.dart';

import '_golden_setup.dart';

void main() {
  runAllVariants('rebalance_execution_sheet', (tester, variant) async {
    final l10n = AppLocalizationsEn();

    await pumpAndSnapshotMobile(
      tester,
      name: 'rebalance_execution_sheet',
      variant: variant,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 820),
            child: AppSheet(
              title: l10n.rebalanceExecutionSheetTitle,
              subtitle: l10n.rebalanceExecutionSheetSubtitle(3),
              footer: AppSheetFooter(
                cancelLabel: l10n.commonCancel,
                submitLabel: l10n.rebalanceExecutionCreateDrafts,
                onSubmit: () {},
              ),
              child: RebalanceExecutionSheet(plan: _plan()),
            ),
          ),
        ),
      ),
    );
  });
}

RebalancePlan _plan() {
  return RebalancePlan(
    target: const TargetAllocation(weights: {}),
    actualWeights: const {},
    drifts: const [],
    trades: [
      SuggestedTrade(
        category: AssetCategory.stock,
        direction: TradeDirection.sell,
        amount: Money(Decimal.parse('18500.45'), 'CNY'),
      ),
      SuggestedTrade(
        category: AssetCategory.etf,
        direction: TradeDirection.buy,
        amount: Money(Decimal.parse('13200.30'), 'CNY'),
      ),
      SuggestedTrade(
        category: AssetCategory.crypto,
        direction: TradeDirection.buy,
        amount: Money(Decimal.parse('5300.25'), 'CNY'),
      ),
    ],
    estimatedFees: Money(Decimal.parse('37.00'), 'CNY'),
    estimatedTaxes: Money(Decimal.parse('18.50'), 'CNY'),
    driftBeforePct: 0.21,
    driftAfterPct: 0.001,
    totalAssets: Money(Decimal.parse('240000'), 'CNY'),
  );
}
