part of 'cost_basis_engine.dart';

Lot _applyBuy(CostBasisEngine engine, BuyEvent event) {
  _requirePositive(event.quantity, 'BuyEvent.quantity');
  final totalCost = event.quantity * event.pricePerUnit + event.fee;
  final costPerUnit = (totalCost / event.quantity).toDecimal(
    scaleOnInfinitePrecision: engine._scale,
  );
  return Lot(
    id: engine._idGenerator(),
    openingTransactionId: event.transactionId,
    accountId: event.accountId,
    assetId: event.assetId,
    currency: event.currency,
    originalQuantity: event.quantity,
    remainingQuantity: event.quantity,
    costPerUnit: costPerUnit,
    openedAt: event.tradeDate,
  );
}

SellResult _applySell(
  CostBasisEngine engine,
  SellEvent event,
  List<Lot> openLots,
) {
  _requirePositive(event.quantity, 'SellEvent.quantity');
  final eligible = openLots
      .where(
        (l) => l.assetId == event.assetId && l.accountId == event.accountId,
      )
      .toList();
  final plan = engine.strategy.plan(eligible, event.quantity);

  final totalConsumed = plan.consumptions.fold<Decimal>(
    Decimal.zero,
    (s, c) => s + c.quantity,
  );
  final lotsById = {for (final l in openLots) l.id: l};
  final updatedLotsById = <String, Lot>{...lotsById};
  final realized = <RealizedPnL>[];

  for (final c in plan.consumptions) {
    final lot = lotsById[c.lotId];
    if (lot == null) continue;
    final proceeds = c.quantity * event.pricePerUnit;
    final fees = totalConsumed.sign <= 0
        ? Decimal.zero
        : (event.fee * c.quantity / totalConsumed).toDecimal(
            scaleOnInfinitePrecision: engine._scale,
          );
    realized.add(
      RealizedPnL(
        id: engine._idGenerator(),
        sellTransactionId: event.transactionId,
        lotId: lot.id,
        accountId: event.accountId,
        assetId: event.assetId,
        currency: event.currency,
        quantity: c.quantity,
        costBasis: c.costBasis,
        proceeds: proceeds,
        fees: fees,
        realizedAt: event.tradeDate,
        lotOpenedAt: lot.openedAt,
      ),
    );
    updatedLotsById[lot.id] = lot.copyWith(
      remainingQuantity: lot.remainingQuantity - c.quantity,
    );
  }

  return SellResult(
    updatedLots: openLots.map((l) => updatedLotsById[l.id] ?? l).toList(),
    realizedPnL: realized,
    unfulfilledQuantity: plan.unfulfilledQuantity,
  );
}
