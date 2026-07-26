import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../domain/income_strategy.dart';
import '../domain/income_strategy_plan.dart';

typedef IncomeStrategyLabelBuilder =
    String Function(AppLocalizations localizations);
typedef IncomeStrategyStatusLabelBuilder =
    String Function(AppLocalizations localizations, String status);

enum IncomeStrategySettingControl { toggle, decimal }

class IncomeStrategySettingPresentation {
  const IncomeStrategySettingPresentation({
    required this.key,
    required this.control,
    required this.label,
    this.defaultBool = false,
  });

  final IncomeStrategySettingKey key;
  final IncomeStrategySettingControl control;
  final IncomeStrategyLabelBuilder label;
  final bool defaultBool;
}

class IncomeStrategyCashFlowPresentation {
  const IncomeStrategyCashFlowPresentation({
    required this.kind,
    required this.icon,
    required this.label,
  });

  final IncomeStrategyCashFlowKind kind;
  final IconData icon;
  final IncomeStrategyLabelBuilder label;
}

class IncomeStrategyRiskPresentation {
  const IncomeStrategyRiskPresentation({
    required this.code,
    required this.label,
  });

  final IncomeStrategyRiskCode code;
  final IncomeStrategyLabelBuilder label;
}

class IncomeStrategyModulePresentation {
  const IncomeStrategyModulePresentation({
    required this.icon,
    required this.label,
    required this.statusLabel,
    this.settings = const [],
    this.cashFlows = const [],
    this.risks = const [],
  });

  final IconData icon;
  final IncomeStrategyLabelBuilder label;
  final IncomeStrategyStatusLabelBuilder statusLabel;
  final List<IncomeStrategySettingPresentation> settings;
  final List<IncomeStrategyCashFlowPresentation> cashFlows;
  final List<IncomeStrategyRiskPresentation> risks;
}

/// Single source of truth for risk copy across every income surface
/// (strategy overview, wheel lifecycle, AI evidence). Module-registered
/// presentations win; the fallback switch only covers portfolio-level
/// rules that no module owns.
String incomeStrategyRiskLabel(
  AppLocalizations l10n,
  Iterable<IncomeStrategyModulePresentation> presentations,
  IncomeStrategyRiskCode code,
) {
  for (final presentation in presentations) {
    for (final risk in presentation.risks) {
      if (risk.code == code) return risk.label(l10n);
    }
  }
  return switch (code.wire) {
    'unplanned_sleeve' => l10n.incomeStrategyRiskUnplanned,
    'capital_budget_exceeded' => l10n.incomeStrategyRiskCapitalBudget,
    'assignment_budget_exceeded' => l10n.incomeStrategyRiskAssignment,
    'concentration_exceeded' => l10n.incomeStrategyRiskConcentration,
    'dividend_interruption' => l10n.incomeStrategyRiskDividend,
    'stacked_downside' => l10n.incomeStrategyRiskStacked,
    'leaps_budget_exceeded' => l10n.incomeStrategyRiskLeapsBudget,
    'leaps_cost_not_covered' => l10n.incomeStrategyRiskLeapsCoverage,
    'missing_market_value' => l10n.incomeStrategyRiskMissingMark,
    'missing_delta' => l10n.incomeStrategyRiskMissingDelta,
    'missing_fx_rate' => l10n.incomeStrategyRiskMissingFx,
    'stale_valuation' => l10n.incomeStrategyRiskStaleValuation,
    'expiration_near' => l10n.incomeStrategyRiskExpiration,
    'income_target_at_risk' => l10n.incomeStrategyRiskIncomeTarget,
    _ => code.wire,
  };
}

const dividendIncomeStrategyPresentation = IncomeStrategyModulePresentation(
  icon: FLucideIcons.badgeDollarSign,
  label: _dividendLabel,
  statusLabel: _dividendStatus,
  settings: [
    IncomeStrategySettingPresentation(
      key: DividendIncomeStrategySettings.preservePosition,
      control: IncomeStrategySettingControl.toggle,
      label: _preserveDividendLabel,
      defaultBool: true,
    ),
  ],
  cashFlows: [
    IncomeStrategyCashFlowPresentation(
      kind: IncomeStrategyCashFlowKind.dividend,
      icon: FLucideIcons.badgeDollarSign,
      label: _dividendCashFlowLabel,
    ),
    IncomeStrategyCashFlowPresentation(
      kind: IncomeStrategyCashFlowKind.dividendWithholding,
      icon: FLucideIcons.receipt,
      label: _withholdingCashFlowLabel,
    ),
  ],
  risks: [
    IncomeStrategyRiskPresentation(
      code: IncomeStrategyRiskCode.dividendInterruption,
      label: _dividendInterruptionRiskLabel,
    ),
  ],
);

const wheelIncomeStrategyPresentation = IncomeStrategyModulePresentation(
  icon: FLucideIcons.refreshCw,
  label: _wheelLabel,
  statusLabel: _wheelStatus,
  settings: [
    IncomeStrategySettingPresentation(
      key: WheelIncomeStrategySettings.allowPut,
      control: IncomeStrategySettingControl.toggle,
      label: _allowPutLabel,
      defaultBool: true,
    ),
    IncomeStrategySettingPresentation(
      key: WheelIncomeStrategySettings.allowCall,
      control: IncomeStrategySettingControl.toggle,
      label: _allowCallLabel,
      defaultBool: true,
    ),
    IncomeStrategySettingPresentation(
      key: WheelIncomeStrategySettings.allowSharesCalledAway,
      control: IncomeStrategySettingControl.toggle,
      label: _allowCalledAwayLabel,
    ),
    IncomeStrategySettingPresentation(
      key: WheelIncomeStrategySettings.maxAssignmentValue,
      control: IncomeStrategySettingControl.decimal,
      label: _maxAssignmentLabel,
    ),
    IncomeStrategySettingPresentation(
      key: WheelIncomeStrategySettings.maxBuyPrice,
      control: IncomeStrategySettingControl.decimal,
      label: _maxBuyPriceLabel,
    ),
    IncomeStrategySettingPresentation(
      key: WheelIncomeStrategySettings.minSellPrice,
      control: IncomeStrategySettingControl.decimal,
      label: _minSellPriceLabel,
    ),
  ],
  cashFlows: [
    IncomeStrategyCashFlowPresentation(
      kind: IncomeStrategyCashFlowKind.optionRealized,
      icon: FLucideIcons.refreshCw,
      label: _wheelCashFlowLabel,
    ),
  ],
  risks: [
    IncomeStrategyRiskPresentation(
      code: IncomeStrategyRiskCode.assignmentBudgetExceeded,
      label: _assignmentRiskLabel,
    ),
    IncomeStrategyRiskPresentation(
      code: IncomeStrategyRiskCode.stackedDownside,
      label: _stackedRiskLabel,
    ),
  ],
);

const leapsIncomeStrategyPresentation = IncomeStrategyModulePresentation(
  icon: FLucideIcons.trendingUp,
  label: _leapsLabel,
  statusLabel: _leapsStatus,
  settings: [
    IncomeStrategySettingPresentation(
      key: LeapsIncomeStrategySettings.maxCost,
      control: IncomeStrategySettingControl.decimal,
      label: _maxLeapsCostLabel,
    ),
  ],
  cashFlows: [
    IncomeStrategyCashFlowPresentation(
      kind: IncomeStrategyCashFlowKind.leapsPurchase,
      icon: FLucideIcons.arrowDownLeft,
      label: _leapsPurchaseCashFlowLabel,
    ),
    IncomeStrategyCashFlowPresentation(
      kind: IncomeStrategyCashFlowKind.leapsSale,
      icon: FLucideIcons.arrowUpRight,
      label: _leapsSaleCashFlowLabel,
    ),
    IncomeStrategyCashFlowPresentation(
      kind: IncomeStrategyCashFlowKind.leapsExercise,
      icon: FLucideIcons.moveUpRight,
      label: _leapsExerciseCashFlowLabel,
    ),
  ],
  risks: [
    IncomeStrategyRiskPresentation(
      code: IncomeStrategyRiskCode.leapsBudgetExceeded,
      label: _leapsBudgetRiskLabel,
    ),
    IncomeStrategyRiskPresentation(
      code: IncomeStrategyRiskCode.leapsCostNotCovered,
      label: _leapsCoverageRiskLabel,
    ),
    IncomeStrategyRiskPresentation(
      code: IncomeStrategyRiskCode.missingMarketValue,
      label: _missingMarkRiskLabel,
    ),
    IncomeStrategyRiskPresentation(
      code: IncomeStrategyRiskCode.missingDelta,
      label: _missingDeltaRiskLabel,
    ),
  ],
);

String _dividendLabel(AppLocalizations l10n) =>
    l10n.incomeStrategySleeveDividends;
String _wheelLabel(AppLocalizations l10n) => l10n.incomeStrategySleeveWheel;
String _leapsLabel(AppLocalizations l10n) => l10n.incomeStrategySleeveLeaps;
String _dividendStatus(AppLocalizations l10n, String status) =>
    switch (status) {
      'holding' => l10n.incomeStrategyStatusHolding,
      'planned' => l10n.incomeStrategyStatusPlanned,
      _ => status,
    };
String _wheelStatus(AppLocalizations l10n, String status) => switch (status) {
  'between' => l10n.planWheelStageBetween,
  'cashWaiting' => l10n.planWheelStageCashWaiting,
  'shortPut' => l10n.planWheelStageShortPut,
  'putExpired' => l10n.planWheelStagePutExpired,
  'putAssigned' => l10n.planWheelStagePutAssigned,
  'sharesHeld' => l10n.planWheelStageSharesHeld,
  'shortCall' => l10n.planWheelStageShortCall,
  'mixedOpen' => l10n.planWheelStageMixedOpen,
  'callExpired' => l10n.planWheelStageCallExpired,
  'callCalled' => l10n.planWheelStageCallCalled,
  _ => status,
};
String _leapsStatus(AppLocalizations l10n, String status) => switch (status) {
  'open' => l10n.incomeStrategyStatusOpen,
  'resolved' => l10n.incomeStrategyStatusResolved,
  _ => status,
};

String _preserveDividendLabel(AppLocalizations l10n) =>
    l10n.incomeStrategyPlanPreserveDividend;
String _allowCalledAwayLabel(AppLocalizations l10n) =>
    l10n.incomeStrategyPlanAllowCalledAway;
String _allowPutLabel(AppLocalizations l10n) => l10n.incomePlannerAllowPutLabel;
String _allowCallLabel(AppLocalizations l10n) =>
    l10n.incomePlannerAllowCallLabel;
String _maxAssignmentLabel(AppLocalizations l10n) =>
    l10n.incomeStrategyPlanMaxAssignment;
String _maxBuyPriceLabel(AppLocalizations l10n) =>
    l10n.incomePlannerMaxBuyPriceLabel;
String _minSellPriceLabel(AppLocalizations l10n) =>
    l10n.incomePlannerMinSellPriceLabel;
String _maxLeapsCostLabel(AppLocalizations l10n) =>
    l10n.incomeStrategyPlanMaxLeapsCost;

String _dividendCashFlowLabel(AppLocalizations l10n) =>
    l10n.incomeStrategyCashFlowDividend;
String _withholdingCashFlowLabel(AppLocalizations l10n) =>
    l10n.incomeStrategyCashFlowWithholding;
String _wheelCashFlowLabel(AppLocalizations l10n) =>
    l10n.incomeStrategyCashFlowWheel;
String _leapsPurchaseCashFlowLabel(AppLocalizations l10n) =>
    l10n.incomeStrategyCashFlowLeapsPurchase;
String _leapsSaleCashFlowLabel(AppLocalizations l10n) =>
    l10n.incomeStrategyCashFlowLeapsSale;
String _leapsExerciseCashFlowLabel(AppLocalizations l10n) =>
    l10n.incomeStrategyCashFlowLeapsExercise;

String _dividendInterruptionRiskLabel(AppLocalizations l10n) =>
    l10n.incomeStrategyRiskDividend;
String _assignmentRiskLabel(AppLocalizations l10n) =>
    l10n.incomeStrategyRiskAssignment;
String _stackedRiskLabel(AppLocalizations l10n) =>
    l10n.incomeStrategyRiskStacked;
String _leapsBudgetRiskLabel(AppLocalizations l10n) =>
    l10n.incomeStrategyRiskLeapsBudget;
String _leapsCoverageRiskLabel(AppLocalizations l10n) =>
    l10n.incomeStrategyRiskLeapsCoverage;
String _missingMarkRiskLabel(AppLocalizations l10n) =>
    l10n.incomeStrategyRiskMissingMark;
String _missingDeltaRiskLabel(AppLocalizations l10n) =>
    l10n.incomeStrategyRiskMissingDelta;
