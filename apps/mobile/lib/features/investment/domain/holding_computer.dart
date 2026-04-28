import 'package:decimal/decimal.dart';

import '../../../data/domain/enums.dart';
import '../../../data/domain/transaction.dart';
import '../../../domain/services/currency_converter.dart';
import '../../../domain/values/money.dart';
import 'cost_basis_engine.dart';
import 'holding_price_source.dart';
import 'models/corporate_actions.dart';
import 'models/holding_snapshot.dart';
import 'models/lot.dart';
import 'models/realized_pnl.dart';
import 'models/trade_events.dart';

/// Result of [HoldingComputer.replay]: the new lot inventory plus realized
/// P&L produced along the way.
///
/// Realized P&L is preserved here (rather than tossed) so the caller — the
/// service layer — can pass it on to FIR-50 (手续费 / 税费 / 汇兑损益建模)
/// without reconstructing it from the sells.
class HoldingReplayResult {
  const HoldingReplayResult({
    required this.lots,
    required this.realizedPnL,
    required this.unfulfilledSells,
  });

  final List<Lot> lots;
  final List<RealizedPnL> realizedPnL;

  /// Sells that could not be fully serviced from the available lots
  /// (oversold). Surfaced rather than silently dropped so the caller can
  /// flag the data and ask the user to reconcile.
  final List<UnfulfilledSell> unfulfilledSells;
}

/// One sell that asked for more shares than were on hand. Carries the
/// originating transaction id so callers can flag the row in the UI.
class UnfulfilledSell {
  const UnfulfilledSell({
    required this.transactionId,
    required this.assetId,
    required this.accountId,
    required this.requestedQuantity,
    required this.unfulfilledQuantity,
  });

  final String transactionId;
  final String assetId;
  final String accountId;
  final Decimal requestedQuantity;
  final Decimal unfulfilledQuantity;
}

/// Pure domain pipeline that turns a stream of transactions + corporate
/// actions into a per-asset [HoldingSnapshot].
///
/// Holds no I/O. Two entry points:
///
/// - [replay] — fold transactions over an initial lot inventory, returning
///   the post-fold lot list plus realized P&L.
/// - [snapshot] — value a lot inventory at [asOf] using a price source and
///   FX converter, returning `Map<assetId, HoldingSnapshot>`.
///
/// The service layer composes these: load yesterday's snapshot, replay
/// today's transactions on top, then call [snapshot] with current prices.
class HoldingComputer {
  HoldingComputer({required this.engine});

  /// Cost-basis engine used to apply buys and sells. Strategy is fixed by
  /// the caller — switching FIFO/LIFO/Avg requires re-running [replay] from
  /// the beginning, since lot consumption order is part of the result.
  final CostBasisEngine engine;

  /// Replay [transactions] (and any [corporateActions]) against
  /// [initialLots], returning the updated lot inventory.
  ///
  /// Events are applied in chronological order (`tradeDate` for transactions,
  /// `effectiveDate` for corporate actions). Ties are broken so that
  /// corporate actions adjust lots *before* same-day buys/sells consume
  /// them — this matches how brokers generally process distribution and
  /// trade records: the ex-date split applies to the open position before
  /// any orders execute.
  HoldingReplayResult replay({
    required List<Lot> initialLots,
    required Iterable<Transaction> transactions,
    Iterable<CorporateAction> corporateActions = const [],
  }) {
    var lots = List<Lot>.from(initialLots);
    final realized = <RealizedPnL>[];
    final unfulfilled = <UnfulfilledSell>[];

    final events = <_TimedEvent>[
      for (final tx in transactions)
        if (_isHoldingMutating(tx)) _TimedEvent.transaction(tx),
      for (final ca in corporateActions) _TimedEvent.corporateAction(ca),
    ];
    events.sort(_compareEvents);

    for (final ev in events) {
      final tx = ev.transaction;
      final ca = ev.corporateAction;
      if (ca != null) {
        lots = _applyCorporateAction(ca, lots);
        continue;
      }
      if (tx == null) continue;

      switch (tx.type) {
        case TransactionType.buy:
        case TransactionType.reinvest:
          final lot = engine.applyBuy(_buyEventOf(tx));
          lots = [...lots, lot];
        case TransactionType.sell:
          final result = engine.applySell(_sellEventOf(tx), lots);
          lots = result.updatedLots;
          realized.addAll(result.realizedPnL);
          if (result.unfulfilledQuantity.sign > 0) {
            unfulfilled.add(
              UnfulfilledSell(
                transactionId: tx.id,
                assetId: tx.assetId!,
                accountId: tx.accountId,
                requestedQuantity: tx.quantity,
                unfulfilledQuantity: result.unfulfilledQuantity,
              ),
            );
          }
        // ignore: no_default_cases
        default:
        // Cash-only / informational transactions don't touch lots.
        // Splits, stock dividends and rights issues flow through
        // [corporateActions] so the engine can read the ratio explicitly —
        // a Transaction(type=split) carries no ratio field and is skipped.
      }
    }

    return HoldingReplayResult(
      lots: lots,
      realizedPnL: realized,
      unfulfilledSells: unfulfilled,
    );
  }

  /// Value [lots] at [asOf] using [prices] and [converter], returning a
  /// per-asset snapshot map.
  ///
  /// Closed lots (remainingQuantity == 0) are filtered out of the
  /// aggregation but left untouched in the source list so that incremental
  /// callers don't lose their realized-P&L lineage.
  ///
  /// Assets without a usable price entry surface with `marketValueInBase ==
  /// Decimal.zero` and a `weight` of zero — by design — so the UI can render
  /// "price unavailable" rather than vanish the position. Cost basis is
  /// always populated.
  Map<String, HoldingSnapshot> snapshot({
    required Iterable<Lot> lots,
    required DateTime asOf,
    required HoldingPriceSource prices,
    required CurrencyConverter converter,
    required String baseCurrency,
  }) {
    final base = baseCurrency.trim().toUpperCase();

    // Group open lots by assetId, and aggregate quantity / cost basis.
    final byAsset = <String, _PerAssetAggregate>{};
    for (final l in lots) {
      if (l.isClosed) continue;
      final agg = byAsset.putIfAbsent(
        l.assetId,
        () => _PerAssetAggregate(currency: l.currency),
      );
      if (agg.currency != l.currency) {
        throw StateError(
          'Asset ${l.assetId} has lots in mixed currencies '
          '(${agg.currency} vs ${l.currency}); the holding pipeline requires '
          'an asset to be denominated in a single currency.',
        );
      }
      agg.quantity += l.remainingQuantity;
      agg.costBasis += l.remainingQuantity * l.costPerUnit;
    }

    // First pass: build snapshots without weights, accumulating total MV.
    final result = <String, HoldingSnapshot>{};
    var totalMarketValueInBase = Decimal.zero;

    for (final entry in byAsset.entries) {
      final assetId = entry.key;
      final agg = entry.value;
      final assetCurrency = agg.currency;

      final priceObs = prices.priceFor(assetId, asOf: asOf);
      final marketValueInAsset = priceObs == null
          ? Decimal.zero
          : agg.quantity * priceObs.price;
      final marketValueAssetCurrency = priceObs?.currency ?? assetCurrency;

      // Convert market value to base.
      final marketValueInBase = priceObs == null
          ? Decimal.zero
          : converter
                .convert(
                  Money(marketValueInAsset, marketValueAssetCurrency),
                  base,
                  on: asOf,
                )
                .amount;

      final costBasisInBase = converter
          .convert(Money(agg.costBasis, assetCurrency), base, on: asOf)
          .amount;

      final unrealizedPnlInBase = marketValueInBase - costBasisInBase;

      result[assetId] = HoldingSnapshot(
        assetId: assetId,
        quantity: agg.quantity,
        costBasisInAssetCurrency: agg.costBasis,
        marketValueInAssetCurrency: marketValueInAsset,
        assetCurrency: assetCurrency,
        costBasisInBase: costBasisInBase,
        marketValueInBase: marketValueInBase,
        unrealizedPnlInBase: unrealizedPnlInBase,
        // Weight filled in below.
        weight: Decimal.zero,
        baseCurrency: base,
        asOf: asOf,
      );

      totalMarketValueInBase += marketValueInBase;
    }

    // Second pass: fill in weights. When the portfolio's MV is zero (e.g.
    // all prices missing), every weight stays at zero — the alternative
    // (NaN / divide-by-zero) breaks downstream chart and report code.
    if (totalMarketValueInBase.sign <= 0) return result;

    final weighted = <String, HoldingSnapshot>{};
    for (final entry in result.entries) {
      final s = entry.value;
      final weight = (s.marketValueInBase / totalMarketValueInBase).toDecimal(
        scaleOnInfinitePrecision: 8,
      );
      weighted[entry.key] = s.copyWith(weight: weight);
    }
    return weighted;
  }

  static bool _isHoldingMutating(Transaction tx) {
    if (tx.assetId == null) return false;
    switch (tx.type) {
      case TransactionType.buy:
      case TransactionType.sell:
      case TransactionType.reinvest:
        return true;
      case TransactionType.dividend:
      case TransactionType.interest:
      case TransactionType.deposit:
      case TransactionType.withdraw:
      case TransactionType.transferIn:
      case TransactionType.transferOut:
      case TransactionType.fee:
      case TransactionType.tax:
      case TransactionType.valuationAdjust:
      case TransactionType.split:
        return false;
    }
  }

  static int _compareEvents(_TimedEvent a, _TimedEvent b) {
    final byDate = a.date.compareTo(b.date);
    if (byDate != 0) return byDate;
    // Same-date tiebreak: corporate actions before transactions, then
    // sort transactions by id so the order is deterministic across replays.
    if (a.isCorporateAction != b.isCorporateAction) {
      return a.isCorporateAction ? -1 : 1;
    }
    return a.tieBreakerId.compareTo(b.tieBreakerId);
  }

  static BuyEvent _buyEventOf(Transaction tx) => BuyEvent(
    transactionId: tx.id,
    accountId: tx.accountId,
    assetId: tx.assetId!,
    currency: tx.currency,
    quantity: tx.quantity,
    pricePerUnit: tx.price,
    fee: tx.fee ?? Decimal.zero,
    tradeDate: tx.tradeDate,
  );

  static SellEvent _sellEventOf(Transaction tx) => SellEvent(
    transactionId: tx.id,
    accountId: tx.accountId,
    assetId: tx.assetId!,
    currency: tx.currency,
    quantity: tx.quantity,
    pricePerUnit: tx.price,
    fee: tx.fee ?? Decimal.zero,
    tradeDate: tx.tradeDate,
  );

  List<Lot> _applyCorporateAction(CorporateAction action, List<Lot> lots) {
    if (action is SplitAction) {
      return engine.applySplit(action, lots);
    }
    if (action is StockDividendAction) {
      return engine.applyStockDividend(action, lots);
    }
    if (action is RightsIssueAction) {
      return [...lots, engine.applyRightsIssue(action)];
    }
    throw UnsupportedError(
      'Unhandled CorporateAction subtype: ${action.runtimeType}',
    );
  }
}

/// Per-asset accumulator used during [HoldingComputer.snapshot].
class _PerAssetAggregate {
  _PerAssetAggregate({required this.currency});

  Decimal quantity = Decimal.zero;
  Decimal costBasis = Decimal.zero;
  final String currency;
}

/// Sortable union of (Transaction, CorporateAction) — internal to
/// [HoldingComputer.replay].
class _TimedEvent {
  _TimedEvent.transaction(Transaction tx)
    : transaction = tx,
      corporateAction = null,
      date = tx.tradeDate,
      tieBreakerId = tx.id,
      isCorporateAction = false;

  _TimedEvent.corporateAction(CorporateAction ca)
    : transaction = null,
      corporateAction = ca,
      date = ca.effectiveDate,
      tieBreakerId = ca.id,
      isCorporateAction = true;

  final Transaction? transaction;
  final CorporateAction? corporateAction;
  final DateTime date;
  final String tieBreakerId;
  final bool isCorporateAction;
}
