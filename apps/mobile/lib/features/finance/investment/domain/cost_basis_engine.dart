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

part 'cost_basis_engine_corporate_actions.dart';
part 'cost_basis_engine_helpers.dart';
part 'cost_basis_engine_results.dart';
part 'cost_basis_engine_trades.dart';

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
  Lot applyBuy(BuyEvent event) => _applyBuy(this, event);

  /// Apply a sell: pick lots via [strategy], emit a [RealizedPnL] per consumed
  /// lot, and return the updated lot list. Sell-side fees are allocated to
  /// each [RealizedPnL] proportionally to its consumed quantity. Lots not
  /// matching the sell's asset/account are returned unchanged.
  SellResult applySell(SellEvent event, List<Lot> openLots) =>
      _applySell(this, event, openLots);

  /// Apply a forward or reverse split. ratio > 1 multiplies share count
  /// (e.g. 2-for-1 → ratio 2), ratio < 1 reduces it (e.g. 1-for-10 reverse
  /// split → ratio 0.1). [Lot.costPerUnit] is divided by the same ratio so
  /// the total cost of each lot is preserved exactly.
  ///
  /// Lots whose [Lot.assetId] does not match are returned unchanged.
  List<Lot> applySplit(SplitAction action, Iterable<Lot> lots) =>
      _applySplit(this, action, lots);

  /// Apply a stock dividend (送股 / 红股 / bonus shares). Each open lot of
  /// the affected asset receives [StockDividendAction.bonusRatio] new shares
  /// per held share at zero marginal cost. Quantity is scaled by
  /// `1 + bonusRatio` and [Lot.costPerUnit] is scaled inversely so total
  /// cost is preserved.
  List<Lot> applyStockDividend(
    StockDividendAction action,
    Iterable<Lot> lots,
  ) => _applyStockDividend(this, action, lots);

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
  ) => _applyCashDividend(this, action, lots);

  /// Apply a DRIP (dividend reinvestment plan): the dividend due on the
  /// holding is paid as additional shares at [DripAction.pricePerUnit].
  /// Computes net dividend (gross minus tax), then opens a new [Lot] whose
  /// total cost equals `net` and whose quantity is `(net - fee) / price`
  /// (rounded at the configured scale). Existing lots are unchanged; the
  /// new lot is appended to [DripResult.updatedLots].
  ///
  /// Throws [ArgumentError] if there are no eligible shares to reinvest
  /// against — DRIP requires an existing position.
  DripResult applyDrip(DripAction action, Iterable<Lot> lots) =>
      _applyDrip(this, action, lots);

  /// Apply a rights issue (配股): the shareholder subscribes new shares at a
  /// (typically discounted) price. Creates a fresh [Lot] dated at
  /// [RightsIssueAction.effectiveDate]; existing lots are unchanged.
  Lot applyRightsIssue(RightsIssueAction action) =>
      _applyRightsIssue(this, action);
}
