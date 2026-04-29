import 'package:decimal/decimal.dart';

import 'cost_basis_engine.dart';
import 'models/cash_dividend.dart';
import 'models/corporate_actions.dart';
import 'models/lot.dart';

/// Per-lot before/after view for an action that mutates existing lots
/// (split, stock dividend). For actions that only add new lots
/// (rights issue, DRIP), [LotDelta] is not produced — the new lot appears
/// in [CorporateActionPreview.newLots].
class LotDelta {
  const LotDelta({required this.before, required this.after});

  final Lot before;
  final Lot after;

  Decimal get quantityDelta => after.remainingQuantity - before.remainingQuantity;
  Decimal get costPerUnitDelta => after.costPerUnit - before.costPerUnit;

  /// True when total cost has changed by more than [tolerance]. Splits and
  /// stock dividends should preserve total cost exactly when the ratio
  /// divides cleanly at the engine's scale; this helper flags rounding
  /// drift if it occurs.
  bool costPreserved({Decimal? tolerance}) {
    final tol = tolerance ?? Decimal.parse('0.0000000001');
    final diff = (after.remainingCost - before.remainingCost);
    return diff.abs() <= tol;
  }
}

/// Structured preview of applying a [CorporateAction] to a starting lot
/// list. Computed via [CorporateActionPreview.compute] using the engine,
/// without persisting anything. Designed for UI "review before submit"
/// screens and for tests that assert on the engine's effects.
class CorporateActionPreview {
  const CorporateActionPreview({
    required this.action,
    required this.startingLots,
    required this.updatedLots,
    required this.lotDeltas,
    required this.newLots,
    required this.cashDividend,
    required this.cashFlow,
    required this.cashFlowCurrency,
  });

  final CorporateAction action;
  final List<Lot> startingLots;

  /// Full lot list after the action applies. For split/stock-dividend this
  /// has the same length as [startingLots] with mutated entries; for
  /// rights-issue / DRIP it appends one new lot. For cash dividend it is
  /// identical to [startingLots].
  final List<Lot> updatedLots;

  /// Lots that were modified by the action (split / stock dividend). Empty
  /// for actions that only add new lots or only emit cash flows.
  final List<LotDelta> lotDeltas;

  /// Lots opened by the action (rights issue / DRIP). Empty for everything
  /// else.
  final List<Lot> newLots;

  /// Cash-dividend record emitted by [CashDividendAction] / [DripAction].
  /// Null for split / stock dividend / rights issue.
  final CashDividend? cashDividend;

  /// Net cash flow into the account at [action.effectiveDate]. Positive for
  /// cash dividends, negative for rights-issue subscription cost, zero for
  /// stock dividend / split / DRIP (DRIP is reinvested in shares, not cash).
  final Decimal cashFlow;

  final String cashFlowCurrency;

  /// Compute a preview. Pure: no IO, no mutation of inputs.
  static CorporateActionPreview compute({
    required CostBasisEngine engine,
    required CorporateAction action,
    required List<Lot> startingLots,
  }) {
    switch (action) {
      case CashDividendAction a:
        final dividend = engine.applyCashDividend(a, startingLots);
        return CorporateActionPreview(
          action: a,
          startingLots: startingLots,
          updatedLots: List.unmodifiable(startingLots),
          lotDeltas: const [],
          newLots: const [],
          cashDividend: dividend,
          cashFlow: dividend?.netAmount ?? Decimal.zero,
          cashFlowCurrency: a.currency,
        );
      case StockDividendAction a:
        final after = engine.applyStockDividend(a, startingLots);
        final deltas = _diff(startingLots, after);
        return CorporateActionPreview(
          action: a,
          startingLots: startingLots,
          updatedLots: after,
          lotDeltas: deltas,
          newLots: const [],
          cashDividend: null,
          cashFlow: Decimal.zero,
          cashFlowCurrency: _currencyOf(deltas, fallback: ''),
        );
      case SplitAction a:
        final after = engine.applySplit(a, startingLots);
        final deltas = _diff(startingLots, after);
        return CorporateActionPreview(
          action: a,
          startingLots: startingLots,
          updatedLots: after,
          lotDeltas: deltas,
          newLots: const [],
          cashDividend: null,
          cashFlow: Decimal.zero,
          cashFlowCurrency: _currencyOf(deltas, fallback: ''),
        );
      case RightsIssueAction a:
        final newLot = engine.applyRightsIssue(a);
        return CorporateActionPreview(
          action: a,
          startingLots: startingLots,
          updatedLots: [...startingLots, newLot],
          lotDeltas: const [],
          newLots: [newLot],
          cashDividend: null,
          cashFlow: -(a.subscribedQuantity * a.pricePerUnit + a.fee),
          cashFlowCurrency: a.currency,
        );
      case DripAction a:
        final result = engine.applyDrip(a, startingLots);
        return CorporateActionPreview(
          action: a,
          startingLots: startingLots,
          updatedLots: result.updatedLots,
          lotDeltas: const [],
          newLots: [result.newLot],
          cashDividend: result.cashDividend,
          cashFlow: Decimal.zero,
          cashFlowCurrency: a.currency,
        );
    }
  }

  static List<LotDelta> _diff(List<Lot> before, List<Lot> after) {
    final byId = {for (final l in before) l.id: l};
    final deltas = <LotDelta>[];
    for (final a in after) {
      final b = byId[a.id];
      if (b == null) continue;
      if (b.remainingQuantity == a.remainingQuantity &&
          b.costPerUnit == a.costPerUnit &&
          b.originalQuantity == a.originalQuantity) {
        continue;
      }
      deltas.add(LotDelta(before: b, after: a));
    }
    return deltas;
  }

  static String _currencyOf(List<LotDelta> deltas, {required String fallback}) {
    if (deltas.isEmpty) return fallback;
    return deltas.first.after.currency;
  }
}
