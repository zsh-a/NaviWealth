import 'package:decimal/decimal.dart';

import '../models/lot.dart';
import 'cost_basis_method.dart';
import 'cost_basis_strategy.dart';

/// Last-In-First-Out: consume the newest open lot first.
class LifoStrategy extends CostBasisStrategy {
  const LifoStrategy();

  @override
  CostBasisMethod get method => CostBasisMethod.lifo;

  @override
  LotConsumptionPlan plan(Iterable<Lot> openLots, Decimal quantity) {
    final ordered = openLots.where((l) => !l.isClosed).toList()
      ..sort((a, b) => b.openedAt.compareTo(a.openedAt));
    return consumeOrdered(ordered, quantity);
  }
}
