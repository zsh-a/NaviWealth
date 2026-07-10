part of 'providers.dart';

final portfolioHoldingReportProvider =
    FutureProvider.autoDispose<PortfolioHoldingReport>((ref) async {
      ref.watch(_ledgerRevisionProvider);
      final now = DateTime.now().toUtc();
      final service = await ref.watch(holdingServiceProvider.future);
      final prices = await ref.watch(holdingPriceSourceProvider.future);
      final converter = ref.watch(returnsCurrencyConverterProvider);
      final base = ref.watch(holdingBaseCurrencyProvider);
      final lots = await service.lotsAt(now);
      return HoldingReportService(
        converter: converter,
        baseCurrency: base,
        prices: prices,
      ).build(lots: lots, asOf: now);
    });

final assetHoldingReportProvider = FutureProvider.autoDispose
    .family<AssetHoldingReport?, String>((ref, assetId) async {
      final report = await ref.watch(portfolioHoldingReportProvider.future);
      return report.assets[assetId];
    });

final portfolioFxPnlProvider = Provider.autoDispose<FxPnLBreakdown>((ref) {
  final report = ref.watch(portfolioHoldingReportProvider).value;
  return report?.totalPnlBreakdown ??
      FxPnLBreakdown.zero(ref.watch(holdingBaseCurrencyProvider));
});

final realizedPnlProvider = FutureProvider.autoDispose<List<RealizedPnL>>((
  ref,
) async {
  ref.watch(_ledgerRevisionProvider);
  final db = await ref.watch(appDatabaseProvider.future);
  final ownerUserId = await ref.watch(_currentOwnerUserIdProvider.future);
  final rows = await LedgerLotReader(
    db,
  ).allMovementsThrough(ownerUserId: ownerUserId, asOf: DateTime.now().toUtc());
  return _realizedPnlFromRows(rows);
});

final portfolioReturnServiceProvider = FutureProvider<PortfolioReturnService>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final ownerUserId = await ref.watch(_currentOwnerUserIdProvider.future);
  final holdings = await ref.watch(holdingServiceProvider.future);
  final converter = ref.watch(returnsCurrencyConverterProvider);
  final base = ref.watch(holdingBaseCurrencyProvider);
  return LedgerPortfolioReturnService(
    db: db,
    ownerUserId: ownerUserId,
    baseCurrency: base,
    holdings: holdings,
    converter: converter,
  );
});

List<RealizedPnL> _realizedPnlFromRows(List<LedgerLotMovement> rows) {
  var id = 0;
  final engine = CostBasisEngine(
    strategy: const FifoStrategy(),
    idGenerator: () => 'realized-${++id}',
  );
  var lots = <Lot>[];
  final realized = <RealizedPnL>[];

  for (final row in rows) {
    final posting = row.posting;
    final cost = posting.costPerUnit;
    final costCurrency = posting.costCurrency;
    if (cost == null || costCurrency == null) continue;

    if (posting.units > Decimal.zero) {
      lots = [
        ...lots,
        Lot(
          id: posting.costLotId ?? posting.id,
          openingTransactionId: posting.journalEntryId,
          accountId: posting.accountId,
          assetId: posting.unit,
          currency: costCurrency,
          originalQuantity: posting.units,
          remainingQuantity: posting.units,
          costPerUnit: cost,
          openedAt: posting.costAcquiredOn ?? row.date,
        ),
      ];
      continue;
    }

    final price = posting.pricePerUnit;
    final priceCurrency = posting.priceCurrency;
    if (posting.units < Decimal.zero &&
        price != null &&
        priceCurrency != null) {
      final result = engine.applySell(
        SellEvent(
          transactionId: posting.journalEntryId,
          accountId: posting.accountId,
          assetId: posting.unit,
          currency: priceCurrency,
          quantity: -posting.units,
          pricePerUnit: price,
          fee: Decimal.zero,
          tradeDate: row.date,
        ),
        lots,
      );
      lots = result.updatedLots;
      realized.addAll(result.realizedPnL);
    }
  }

  realized.sort((a, b) => b.realizedAt.compareTo(a.realizedAt));
  return List.unmodifiable(realized);
}
