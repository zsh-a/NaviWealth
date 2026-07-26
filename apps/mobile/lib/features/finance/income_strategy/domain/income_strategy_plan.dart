import 'package:decimal/decimal.dart';

import 'package:naviwealth/core/sync/sync_meta.dart';
import 'income_strategy.dart';

const Object _unsetIncomePlanField = Object();

/// User intent and guardrails for freely composing sleeves on one asset.
///
/// Live positions, prices and derived metrics never belong in this synced
/// plan. They are assembled from their owning FinanceOS source models.
class IncomeStrategyPlan {
  const IncomeStrategyPlan({
    required this.assetId,
    required this.symbol,
    required this.market,
    required this.currency,
    required this.enabledSleeves,
    required this.capitalBudget,
    required this.annualIncomeTarget,
    required this.maxPositionWeight,
    required this.maxLeapsCost,
    required this.maxAssignmentValue,
    required this.preserveDividend,
    required this.allowSharesCalledAway,
    required this.notes,
    required this.sync,
  });

  final String assetId;
  final String symbol;
  final String market;
  final String currency;
  final Set<IncomeStrategySleeveKind> enabledSleeves;
  final Decimal? capitalBudget;
  final Decimal? annualIncomeTarget;
  final Decimal? maxPositionWeight;
  final Decimal? maxLeapsCost;
  final Decimal? maxAssignmentValue;
  final bool preserveDividend;
  final bool allowSharesCalledAway;
  final String? notes;
  final SyncMeta sync;

  IncomeStrategyPlan copyWith({
    Set<IncomeStrategySleeveKind>? enabledSleeves,
    Object? capitalBudget = _unsetIncomePlanField,
    Object? annualIncomeTarget = _unsetIncomePlanField,
    Object? maxPositionWeight = _unsetIncomePlanField,
    Object? maxLeapsCost = _unsetIncomePlanField,
    Object? maxAssignmentValue = _unsetIncomePlanField,
    bool? preserveDividend,
    bool? allowSharesCalledAway,
    Object? notes = _unsetIncomePlanField,
    SyncMeta? sync,
  }) => IncomeStrategyPlan(
    assetId: assetId,
    symbol: symbol,
    market: market,
    currency: currency,
    enabledSleeves: enabledSleeves ?? this.enabledSleeves,
    capitalBudget: identical(capitalBudget, _unsetIncomePlanField)
        ? this.capitalBudget
        : capitalBudget as Decimal?,
    annualIncomeTarget: identical(annualIncomeTarget, _unsetIncomePlanField)
        ? this.annualIncomeTarget
        : annualIncomeTarget as Decimal?,
    maxPositionWeight: identical(maxPositionWeight, _unsetIncomePlanField)
        ? this.maxPositionWeight
        : maxPositionWeight as Decimal?,
    maxLeapsCost: identical(maxLeapsCost, _unsetIncomePlanField)
        ? this.maxLeapsCost
        : maxLeapsCost as Decimal?,
    maxAssignmentValue: identical(maxAssignmentValue, _unsetIncomePlanField)
        ? this.maxAssignmentValue
        : maxAssignmentValue as Decimal?,
    preserveDividend: preserveDividend ?? this.preserveDividend,
    allowSharesCalledAway: allowSharesCalledAway ?? this.allowSharesCalledAway,
    notes: identical(notes, _unsetIncomePlanField)
        ? this.notes
        : notes as String?,
    sync: sync ?? this.sync,
  );
}
