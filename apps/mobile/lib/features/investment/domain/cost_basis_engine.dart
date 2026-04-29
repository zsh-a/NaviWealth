import 'package:decimal/decimal.dart';
import 'package:uuid/uuid.dart';

import 'cost_basis/average_cost_strategy.dart';
import 'cost_basis/cost_basis_method.dart';
import 'cost_basis/cost_basis_strategy.dart';
import 'cost_basis/fifo_strategy.dart';
import 'cost_basis/lifo_strategy.dart';
import 'models/cash_dividend.dart';
import 'models/corporate_actions.dart';
import 'models/lot.dart';
import 'models/realized_pnl.dart';
import 'models/trade_events.dart';

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

/// Pure domain engine for lot-based cost-basis accounting.
///
/// Holds no state — all open-lot state is supplied per call. This makes the
/// engine trivially safe to share, and lets the persistence layer (Drift)
/// own how lots are loaded and stored.
class CostBasisEngine {
  CostBasisEngine({
    required this.strategy,
    String Function()? idGenerator,
    int decimalScale = 16,
  }) : _idGenerator = idGenerator ?? _defaultIdGenerator,
       _scale = decimalScale;

  /// Convenience constructor that picks a strategy by [CostBasisMethod].
  factory CostBasisEngine.forMethod(
    CostBasisMethod method, {
    String Function()? idGenerator,
    int decimalScale = 16,
  }) {
    final CostBasisStrategy strategy;
    switch (method) {
      case CostBasisMethod.fifo:
        strategy = const FifoStrategy();
      case CostBasisMethod.lifo:
        strategy = const LifoStrategy();
      case CostBasisMethod.average:
        strategy = AverageCostStrategy(decimalScale: decimalScale);
    }
    return CostBasisEngine(
      strategy: strategy,
      idGenerator: idGenerator,
      decimalScale: decimalScale,
    );
  }

  static const Uuid _defaultUuid = Uuid();
  static String _defaultIdGenerator() => _defaultUuid.v4();

  final CostBasisStrategy strategy;
  final String Function() _idGenerator;
  final int _scale;

  /// Open a new lot from a buy. Buy-side fees are baked into [Lot.costPerUnit]
  /// so they reduce realized gain at sell time, matching how brokers report
  /// adjusted cost basis on 1099-B forms.
  Lot applyBuy(BuyEvent event) {
    _requirePositive(event.quantity, 'BuyEvent.quantity');
    final totalCost = event.quantity * event.pricePerUnit + event.fee;
    final costPerUnit = (totalCost / event.quantity).toDecimal(
      scaleOnInfinitePrecision: _scale,
    );
    return Lot(
      id: _idGenerator(),
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

  /// Apply a sell: pick lots via [strategy], emit a [RealizedPnL] per consumed
  /// lot, and return the updated lot list. Sell-side fees are allocated to
  /// each [RealizedPnL] proportionally to its consumed quantity. Lots not
  /// matching the sell's asset/account are returned unchanged.
  SellResult applySell(SellEvent event, List<Lot> openLots) {
    _requirePositive(event.quantity, 'SellEvent.quantity');
    final eligible = openLots
        .where(
          (l) => l.assetId == event.assetId && l.accountId == event.accountId,
        )
        .toList();
    final plan = strategy.plan(eligible, event.quantity);

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
              scaleOnInfinitePrecision: _scale,
            );
      realized.add(
        RealizedPnL(
          id: _idGenerator(),
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

  /// Apply a forward or reverse split. ratio > 1 multiplies share count
  /// (e.g. 2-for-1 → ratio 2), ratio < 1 reduces it (e.g. 1-for-10 reverse
  /// split → ratio 0.1). [Lot.costPerUnit] is divided by the same ratio so
  /// the total cost of each lot is preserved exactly.
  ///
  /// Lots whose [Lot.assetId] does not match are returned unchanged.
  List<Lot> applySplit(SplitAction action, Iterable<Lot> lots) {
    if (action.ratio.sign <= 0) {
      throw ArgumentError.value(
        action.ratio,
        'SplitAction.ratio',
        'must be positive',
      );
    }
    return lots.map((l) {
      if (l.assetId != action.assetId) return l;
      return l.copyWith(
        originalQuantity: l.originalQuantity * action.ratio,
        remainingQuantity: l.remainingQuantity * action.ratio,
        costPerUnit: (l.costPerUnit / action.ratio).toDecimal(
          scaleOnInfinitePrecision: _scale,
        ),
      );
    }).toList();
  }

  /// Apply a stock dividend (送股 / 红股 / bonus shares). Each open lot of
  /// the affected asset receives [StockDividendAction.bonusRatio] new shares
  /// per held share at zero marginal cost. Quantity is scaled by
  /// `1 + bonusRatio` and [Lot.costPerUnit] is scaled inversely so total
  /// cost is preserved.
  List<Lot> applyStockDividend(StockDividendAction action, Iterable<Lot> lots) {
    if (action.bonusRatio.sign < 0) {
      throw ArgumentError.value(
        action.bonusRatio,
        'StockDividendAction.bonusRatio',
        'must be non-negative',
      );
    }
    final factor = Decimal.one + action.bonusRatio;
    if (factor.sign <= 0) {
      throw ArgumentError.value(
        action.bonusRatio,
        'StockDividendAction.bonusRatio',
        'produced non-positive scale factor',
      );
    }
    return lots.map((l) {
      if (l.assetId != action.assetId) return l;
      return l.copyWith(
        originalQuantity: l.originalQuantity * factor,
        remainingQuantity: l.remainingQuantity * factor,
        costPerUnit: (l.costPerUnit / factor).toDecimal(
          scaleOnInfinitePrecision: _scale,
        ),
      );
    }).toList();
  }

  /// Apply a cash dividend (现金分红). Sums the eligible open shares as of
  /// [CashDividendAction.effectiveDate] and computes gross / net cash. Open
  /// lots are not modified — the caller is responsible for booking the
  /// resulting cash transaction. Returns `null` if the holder owns zero
  /// shares of [CashDividendAction.assetId] in [CashDividendAction.accountId]
  /// on the effective date (nothing to pay out).
  ///
  /// Lots whose `openedAt` is strictly after [CashDividendAction.effectiveDate]
  /// are excluded (they were not held on record date).
  CashDividend? applyCashDividend(
    CashDividendAction action,
    Iterable<Lot> lots,
  ) {
    if (action.amountPerShare.sign < 0) {
      throw ArgumentError.value(
        action.amountPerShare,
        'CashDividendAction.amountPerShare',
        'must be non-negative',
      );
    }
    if (action.withholdingTax.sign < 0) {
      throw ArgumentError.value(
        action.withholdingTax,
        'CashDividendAction.withholdingTax',
        'must be non-negative',
      );
    }
    final shares = _eligibleShareCount(
      lots: lots,
      accountId: action.accountId,
      assetId: action.assetId,
      asOf: action.effectiveDate,
    );
    if (shares.sign <= 0) return null;
    final gross = shares * action.amountPerShare;
    if (action.withholdingTax > gross) {
      throw ArgumentError.value(
        action.withholdingTax,
        'CashDividendAction.withholdingTax',
        'cannot exceed gross dividend ($gross)',
      );
    }
    final net = gross - action.withholdingTax;
    return CashDividend(
      id: _idGenerator(),
      transactionId: action.transactionId,
      accountId: action.accountId,
      assetId: action.assetId,
      currency: action.currency,
      effectiveDate: action.effectiveDate,
      shareCount: shares,
      amountPerShare: action.amountPerShare,
      grossAmount: gross,
      withholdingTax: action.withholdingTax,
      netAmount: net,
      reinvested: false,
    );
  }

  /// Apply a DRIP (dividend reinvestment plan): the dividend due on the
  /// holding is paid as additional shares at [DripAction.pricePerUnit].
  /// Computes net dividend (gross minus tax), then opens a new [Lot] whose
  /// total cost equals `net` and whose quantity is `(net - fee) / price`
  /// (rounded at the configured scale). Existing lots are unchanged; the
  /// new lot is appended to [DripResult.updatedLots].
  ///
  /// Throws [ArgumentError] if there are no eligible shares to reinvest
  /// against — DRIP requires an existing position.
  DripResult applyDrip(DripAction action, Iterable<Lot> lots) {
    _requirePositive(action.amountPerShare, 'DripAction.amountPerShare');
    _requirePositive(action.pricePerUnit, 'DripAction.pricePerUnit');
    if (action.withholdingTax.sign < 0) {
      throw ArgumentError.value(
        action.withholdingTax,
        'DripAction.withholdingTax',
        'must be non-negative',
      );
    }
    if (action.fee.sign < 0) {
      throw ArgumentError.value(
        action.fee,
        'DripAction.fee',
        'must be non-negative',
      );
    }
    final lotsList = lots.toList();
    final shares = _eligibleShareCount(
      lots: lotsList,
      accountId: action.accountId,
      assetId: action.assetId,
      asOf: action.effectiveDate,
    );
    if (shares.sign <= 0) {
      throw ArgumentError.value(
        shares,
        'DripAction',
        'no eligible shares of ${action.assetId} held in '
            '${action.accountId} on ${action.effectiveDate}',
      );
    }
    final gross = shares * action.amountPerShare;
    if (action.withholdingTax > gross) {
      throw ArgumentError.value(
        action.withholdingTax,
        'DripAction.withholdingTax',
        'cannot exceed gross dividend ($gross)',
      );
    }
    final net = gross - action.withholdingTax;
    final cashAvailable = net - action.fee;
    if (cashAvailable.sign <= 0) {
      throw ArgumentError.value(
        action.fee,
        'DripAction.fee',
        'fee ($action.fee) exceeds net dividend ($net) — nothing to reinvest',
      );
    }
    final newLotQuantity = (cashAvailable / action.pricePerUnit).toDecimal(
      scaleOnInfinitePrecision: _scale,
    );
    if (newLotQuantity.sign <= 0) {
      throw ArgumentError.value(
        newLotQuantity,
        'DripAction',
        'reinvestment produced zero shares at scale $_scale',
      );
    }
    final totalCost = newLotQuantity * action.pricePerUnit + action.fee;
    final costPerUnit = (totalCost / newLotQuantity).toDecimal(
      scaleOnInfinitePrecision: _scale,
    );
    final newLot = Lot(
      id: _idGenerator(),
      openingTransactionId: action.transactionId,
      accountId: action.accountId,
      assetId: action.assetId,
      currency: action.currency,
      originalQuantity: newLotQuantity,
      remainingQuantity: newLotQuantity,
      costPerUnit: costPerUnit,
      openedAt: action.effectiveDate,
    );
    final dividend = CashDividend(
      id: _idGenerator(),
      transactionId: action.transactionId,
      accountId: action.accountId,
      assetId: action.assetId,
      currency: action.currency,
      effectiveDate: action.effectiveDate,
      shareCount: shares,
      amountPerShare: action.amountPerShare,
      grossAmount: gross,
      withholdingTax: action.withholdingTax,
      netAmount: net,
      reinvested: true,
    );
    return DripResult(
      cashDividend: dividend,
      newLot: newLot,
      updatedLots: [...lotsList, newLot],
    );
  }

  /// Sum [Lot.remainingQuantity] across lots matching [accountId] / [assetId]
  /// that were opened on or before [asOf].
  Decimal _eligibleShareCount({
    required Iterable<Lot> lots,
    required String accountId,
    required String assetId,
    required DateTime asOf,
  }) {
    var total = Decimal.zero;
    for (final lot in lots) {
      if (lot.accountId != accountId) continue;
      if (lot.assetId != assetId) continue;
      if (lot.openedAt.isAfter(asOf)) continue;
      total += lot.remainingQuantity;
    }
    return total;
  }

  /// Apply a rights issue (配股): the shareholder subscribes new shares at a
  /// (typically discounted) price. Creates a fresh [Lot] dated at
  /// [RightsIssueAction.effectiveDate]; existing lots are unchanged.
  Lot applyRightsIssue(RightsIssueAction action) {
    _requirePositive(
      action.subscribedQuantity,
      'RightsIssueAction.subscribedQuantity',
    );
    final totalCost =
        action.subscribedQuantity * action.pricePerUnit + action.fee;
    final costPerUnit = (totalCost / action.subscribedQuantity).toDecimal(
      scaleOnInfinitePrecision: _scale,
    );
    return Lot(
      id: _idGenerator(),
      openingTransactionId: action.transactionId,
      accountId: action.accountId,
      assetId: action.assetId,
      currency: action.currency,
      originalQuantity: action.subscribedQuantity,
      remainingQuantity: action.subscribedQuantity,
      costPerUnit: costPerUnit,
      openedAt: action.effectiveDate,
    );
  }

  void _requirePositive(Decimal value, String name) {
    if (value.sign <= 0) {
      throw ArgumentError.value(value, name, 'must be positive');
    }
  }
}
