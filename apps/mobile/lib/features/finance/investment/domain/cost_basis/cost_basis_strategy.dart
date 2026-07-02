import 'package:decimal/decimal.dart';

import '../models/lot.dart';
import 'cost_basis_method.dart';

/// One lot's contribution toward fulfilling a sell. Quantity is what the
/// strategy chose to draw from the lot; [costBasis] is the cost-basis amount
/// associated with that quantity (per-lot cost for FIFO/LIFO, weighted-average
/// cost for [AverageCostStrategy]).
class LotConsumption {
  const LotConsumption({
    required this.lotId,
    required this.quantity,
    required this.costBasis,
  });

  final String lotId;
  final Decimal quantity;
  final Decimal costBasis;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LotConsumption &&
        other.lotId == lotId &&
        other.quantity == quantity &&
        other.costBasis == costBasis;
  }

  @override
  int get hashCode => Object.hash(lotId, quantity, costBasis);

  @override
  String toString() =>
      'LotConsumption(lot: $lotId, qty: $quantity, basis: $costBasis)';
}

/// The full plan for fulfilling a sell — a list of per-lot consumptions plus
/// the leftover quantity that could not be fulfilled (for short sells or
/// data-entry errors). Engines surface [unfulfilledQuantity] so the caller
/// can decide whether to error, allow short positions, or warn the user.
class LotConsumptionPlan {
  const LotConsumptionPlan({
    required this.consumptions,
    required this.unfulfilledQuantity,
  });

  final List<LotConsumption> consumptions;
  final Decimal unfulfilledQuantity;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! LotConsumptionPlan) return false;
    if (other.unfulfilledQuantity != unfulfilledQuantity) return false;
    if (other.consumptions.length != consumptions.length) return false;
    for (var i = 0; i < consumptions.length; i++) {
      if (other.consumptions[i] != consumptions[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(unfulfilledQuantity, Object.hashAll(consumptions));
}

/// Strategy interface for picking which lots a sell consumes. Implementations
/// must be pure: same input → same output, no side effects.
abstract class CostBasisStrategy {
  const CostBasisStrategy();

  CostBasisMethod get method;

  /// Plan how to draw [quantity] units from [openLots]. Lots that are already
  /// closed (remainingQuantity ≤ 0) must be ignored.
  LotConsumptionPlan plan(Iterable<Lot> openLots, Decimal quantity);
}

/// Walks an already-ordered list of open lots and consumes them in turn,
/// recording per-lot cost basis. Used by FIFO and LIFO strategies; exposed
/// for any future strategy that wants the same per-lot accounting.
LotConsumptionPlan consumeOrdered(List<Lot> orderedOpenLots, Decimal quantity) {
  if (quantity.sign <= 0) {
    return LotConsumptionPlan(
      consumptions: const [],
      unfulfilledQuantity: Decimal.zero,
    );
  }
  final consumptions = <LotConsumption>[];
  var remaining = quantity;
  for (final lot in orderedOpenLots) {
    if (remaining.sign <= 0) break;
    if (lot.isClosed) continue;
    final available = lot.remainingQuantity;
    final consume = remaining > available ? available : remaining;
    consumptions.add(
      LotConsumption(
        lotId: lot.id,
        quantity: consume,
        costBasis: consume * lot.costPerUnit,
      ),
    );
    remaining -= consume;
  }
  return LotConsumptionPlan(
    consumptions: consumptions,
    unfulfilledQuantity: remaining.sign < 0 ? Decimal.zero : remaining,
  );
}
