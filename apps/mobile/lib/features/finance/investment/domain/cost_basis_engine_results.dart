part of 'cost_basis_engine.dart';

/// Result of [CostBasisEngine.applyDrip]: the dividend record plus the new
/// lot opened by reinvestment. [updatedLots] is the input lot list with the
/// new lot appended at the end so callers can persist it directly.
class DripResult {
  const DripResult({
    required this.cashDividend,
    required this.newLot,
    required this.updatedLots,
  });

  final CashDividend cashDividend;
  final Lot newLot;
  final List<Lot> updatedLots;
}

/// Result of [CostBasisEngine.applySell]: the post-sell lot state plus the
/// realized P&L records the sell produced.
///
/// [updatedLots] is the full input lot list with consumed lots' quantities
/// reduced (and possibly zero, indicating they are now closed). Callers can
/// either persist [updatedLots] directly or diff against the original to
/// build a minimal update set.
class SellResult {
  const SellResult({
    required this.updatedLots,
    required this.realizedPnL,
    required this.unfulfilledQuantity,
  });

  final List<Lot> updatedLots;
  final List<RealizedPnL> realizedPnL;
  final Decimal unfulfilledQuantity;
}
