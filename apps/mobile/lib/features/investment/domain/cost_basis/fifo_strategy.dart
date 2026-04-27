import 'package:decimal/decimal.dart';

import '../models/lot.dart';
import 'cost_basis_method.dart';
import 'cost_basis_strategy.dart';

/// First-In-First-Out: consume the oldest open lot first.
class FifoStrategy extends CostBasisStrategy {
  const FifoStrategy();

  @override
  CostBasisMethod get method => CostBasisMethod.fifo;

  @override
  LotConsumptionPlan plan(Iterable<Lot> openLots, Decimal quantity) {
    final ordered = openLots.where((l) => !l.isClosed).toList()
      ..sort((a, b) => a.openedAt.compareTo(b.openedAt));
    return consumeOrdered(ordered, quantity);
  }
}
