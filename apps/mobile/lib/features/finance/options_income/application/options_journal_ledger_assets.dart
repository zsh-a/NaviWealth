part of 'options_journal_ledger_service.dart';

Future<Asset> _ensureOptionsUnderlyingAsset({
  required SecuritiesAssetRepository securitiesAssetRepo,
  required TradeJournalEntry entry,
}) async {
  final market =
      assetMarketFromWire(entry.underlyingMarket) ??
      inferAssetMarket(entry.symbol);
  final effectiveMarket = market == AssetMarket.unknown
      ? AssetMarket.usStock
      : market;
  final existing = await securitiesAssetRepo.findBySymbolAndMarket(
    entry.symbol,
    effectiveMarket,
  );
  if (existing != null) return existing;
  return securitiesAssetRepo.upsertSecurity(
    symbol: entry.symbol,
    market: effectiveMarket,
    type: AssetType.stock,
    currency: entry.currency,
    name: entry.symbol,
  );
}

Future<void> _ensureOptionsCashAsset({
  required ManualAssetRepository manualAssetRepo,
  required String accountId,
  required String currency,
}) async {
  final existing = await manualAssetRepo.findCashByAccountId(accountId);
  if (existing != null) return;
  await manualAssetRepo.createCash(
    accountId: accountId,
    currency: currency,
    balance: Decimal.zero,
    nickname: '$currency options cash',
  );
}

Future<_CostBasis> _costBasisForOptionsCalledAway({
  required Future<HoldingService> Function() holdingService,
  required String accountId,
  required String assetId,
  required Decimal quantity,
  required Decimal fallbackPrice,
  required String currency,
  required DateTime asOf,
}) async {
  final service = await holdingService();
  final lots = await service.lotsAt(
    asOf.subtract(const Duration(microseconds: 1)),
  );
  final candidates =
      lots
          .where(
            (lot) =>
                !lot.isClosed &&
                lot.accountId == accountId &&
                lot.assetId == assetId &&
                lot.currency == currency,
          )
          .toList()
        ..sort((a, b) => a.openedAt.compareTo(b.openedAt));
  if (candidates.isEmpty) {
    return _CostBasis(costPerUnit: fallbackPrice, currency: currency);
  }

  var remaining = quantity;
  var cost = Decimal.zero;
  Lot? first;
  for (final lot in candidates) {
    if (remaining <= Decimal.zero) break;
    first ??= lot;
    final take = lot.remainingQuantity < remaining
        ? lot.remainingQuantity
        : remaining;
    cost += take * lot.costPerUnit;
    remaining -= take;
  }
  if (remaining > Decimal.zero || cost == Decimal.zero) {
    return _CostBasis(costPerUnit: fallbackPrice, currency: currency);
  }
  final costPerUnit = (cost / quantity).toDecimal(scaleOnInfinitePrecision: 16);
  return _CostBasis(
    costPerUnit: costPerUnit,
    currency: currency,
    lotId: first?.id,
    acquiredOn: first?.openedAt,
  );
}
