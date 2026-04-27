import 'package:decimal/decimal.dart';

import '../models/lot.dart';
import 'cost_basis_method.dart';
import 'cost_basis_strategy.dart';

/// Weighted-average cost. The aggregate average cost is computed across all
/// open lots, then [quantity] is distributed proportionally to each lot's
/// [Lot.remainingQuantity]. Each per-lot cost basis is the consumed quantity
/// times the global weighted average — so all consumptions from one sell
/// share the same effective cost-per-unit, while preserving lot identity.
///
/// The last lot in the proportional walk absorbs any rounding remainder so
/// the sum of consumed quantities equals the requested quantity exactly.
class AverageCostStrategy extends CostBasisStrategy {
  const AverageCostStrategy({this.decimalScale = 16});

  final int decimalScale;

  @override
  CostBasisMethod get method => CostBasisMethod.average;

  @override
  LotConsumptionPlan plan(Iterable<Lot> openLots, Decimal quantity) {
    if (quantity.sign <= 0) {
      return LotConsumptionPlan(
        consumptions: const [],
        unfulfilledQuantity: Decimal.zero,
      );
    }
    final lots = openLots.where((l) => !l.isClosed).toList()
      ..sort((a, b) => a.openedAt.compareTo(b.openedAt));
    if (lots.isEmpty) {
      return LotConsumptionPlan(
        consumptions: const [],
        unfulfilledQuantity: quantity,
      );
    }
    final totalQty = lots.fold<Decimal>(
      Decimal.zero,
      (s, l) => s + l.remainingQuantity,
    );
    if (totalQty.sign <= 0) {
      return LotConsumptionPlan(
        consumptions: const [],
        unfulfilledQuantity: quantity,
      );
    }
    final totalCost = lots.fold<Decimal>(
      Decimal.zero,
      (s, l) => s + l.remainingCost,
    );
    final avgCost = (totalCost / totalQty).toDecimal(
      scaleOnInfinitePrecision: decimalScale,
    );

    final fulfilled = quantity > totalQty ? totalQty : quantity;
    final unfulfilled = quantity - fulfilled;

    final consumptions = <LotConsumption>[];
    var remaining = fulfilled;
    for (var i = 0; i < lots.length; i++) {
      if (remaining.sign <= 0) break;
      final lot = lots[i];
      final isLast = i == lots.length - 1;
      Decimal consume;
      if (isLast) {
        consume = remaining;
      } else {
        final share = (lot.remainingQuantity * fulfilled / totalQty).toDecimal(
          scaleOnInfinitePrecision: decimalScale,
        );
        consume = share > remaining ? remaining : share;
      }
      if (consume.sign <= 0) continue;
      consumptions.add(
        LotConsumption(
          lotId: lot.id,
          quantity: consume,
          costBasis: consume * avgCost,
        ),
      );
      remaining -= consume;
    }
    return LotConsumptionPlan(
      consumptions: consumptions,
      unfulfilledQuantity: unfulfilled,
    );
  }
}
