import 'package:decimal/decimal.dart';

import '../../../../data/domain/transaction.dart';
import '../../../../domain/services/currency_converter.dart';
import '../../../../domain/values/money.dart';
import '../holding_price_source.dart';
import '../models/lot.dart';
import 'cash_flow_extractor.dart';
import 'xirr_engine.dart';

/// Loader for transactions inside a date window. Mirrors the shape of
/// `HoldingTransactionsRepository.transactionsInRange` so production wiring
/// can hand the same Drift-backed implementation to both services.
abstract class ReturnsTransactionsRepository {
  Future<List<Transaction>> transactionsInRange({
    required String ownerUserId,
    required DateTime from,
    required DateTime to,
  });
}

/// Loader for the per-asset lot inventory at a point in time. The returns
/// service uses this twice per call — once at [DateRange.from] for the
/// initial bookend and once at [DateRange.to] for the terminal bookend — so
/// implementations should cache aggressively. In production this is just
/// `HoldingService.computeAt` followed by a flatten back to lots; the
/// abstraction here keeps the returns service decoupled from the Drift /
/// daily-snapshot machinery.
abstract class ReturnsLotsSource {
  /// All open lots owned by [ownerUserId] at [asOf]. Closed lots may be
  /// included or filtered — the returns service only sums `remainingQuantity`
  /// so closed lots contribute zero either way.
  Future<List<Lot>> lotsAt({
    required String ownerUserId,
    required DateTime asOf,
  });
}

/// Optional projector for "bucket → asset IDs". Wires single-asset XIRR up
/// into category / industry / account roll-ups.
///
/// Implementations are usually backed by `Asset.industry`,
/// `Asset.metadataJson` or a category join — the returns service stays
/// agnostic and just receives a `Map<bucket, Set<assetId>>` snapshot.
class XirrBucketing {
  const XirrBucketing(this.bucketsToAssets);

  /// Bucket identifier → asset IDs that fall in the bucket. Stable string
  /// keys so the result map round-trips back to UI labels deterministically.
  final Map<String, Set<String>> bucketsToAssets;
}

/// Outcome carrier: the solver result plus the dimensions that produced it.
///
/// The wrapping serves two purposes — it keeps the (very common) "give me
/// XIRR for asset X" call returning a single object that preserves the
/// scope, and it lets the multi-dimension calls return a `Map<bucket,
/// XirrReport>` without losing the bookend / cash-flow context the UI uses
/// for the "show your work" tooltip.
class XirrReport {
  const XirrReport({
    required this.solution,
    required this.flows,
    required this.from,
    required this.to,
    required this.baseCurrency,
    required this.initialValueInBase,
    required this.terminalValueInBase,
    required this.scope,
  });

  final XirrSolution solution;

  /// Every flow that fed the solver, in NPV sign convention. Includes the
  /// initial / terminal bookends so the UI can render them as discrete bars.
  final List<XirrCashFlow> flows;

  final DateTime from;
  final DateTime to;
  final String baseCurrency;

  /// Value of the position(s) at [from] (positive Decimal). The bookend
  /// flow added at [from] is `−initialValueInBase`.
  final Decimal initialValueInBase;

  /// Value of the position(s) at [to] (positive Decimal). The bookend flow
  /// added at [to] is `+terminalValueInBase`.
  final Decimal terminalValueInBase;

  final CashFlowScope scope;
}

/// High-level façade — composes the engine, extractor, lots source and
/// converter into the API the UI consumes.
///
/// All calls are date-range scoped (`1M / 3M / 6M / 1Y / 3Y / 5Y / 全部 /
/// 自定义` resolve to a [DateRange] before getting here). The service does
/// not interpret these labels — picking the right `from` / `to` is a
/// presentation-layer concern.
class ReturnsService {
  ReturnsService({
    required this.ownerUserId,
    required this.baseCurrency,
    required this.transactions,
    required this.lots,
    required this.prices,
    required this.converter,
    XirrEngine? engine,
  }) : _extractor = CashFlowExtractor(
         converter: converter,
         baseCurrency: baseCurrency,
       ),
       _engine = engine ?? const XirrEngine();

  final String ownerUserId;
  final String baseCurrency;
  final ReturnsTransactionsRepository transactions;
  final ReturnsLotsSource lots;
  final HoldingPriceSource prices;
  final CurrencyConverter converter;

  final CashFlowExtractor _extractor;
  final XirrEngine _engine;

  /// Single-asset XIRR.
  ///
  /// Cash-flow set:
  ///   - bookend: position value at [from] in base (negative)
  ///   - for each tx in (from, to] touching [assetId]:
  ///       buy → −, sell → +, dividend → +, fee/tax on asset → −
  ///   - bookend: position value at [to] in base (positive)
  ///
  /// `from` is **exclusive** for in-window flows because the initial bookend
  /// already captures everything at-or-before `from`. Otherwise a buy
  /// executed exactly at `from` would be double-counted.
  Future<XirrReport> assetXirr({
    required String assetId,
    required DateTime from,
    required DateTime to,
  }) {
    return _compute(
      from: from,
      to: to,
      scope: CashFlowScope.position,
      filter: CashFlowFilter(assetIds: {assetId}, ownerUserId: ownerUserId),
      lotPredicate: (l) => l.assetId == assetId,
    );
  }

  /// Portfolio-level XIRR. External cash flows (deposits, withdrawals)
  /// drive the IRR — internal trades are absorbed into the terminal value.
  Future<XirrReport> portfolioXirr({
    required DateTime from,
    required DateTime to,
  }) {
    return _compute(
      from: from,
      to: to,
      scope: CashFlowScope.account,
      filter: CashFlowFilter(ownerUserId: ownerUserId),
      lotPredicate: (_) => true,
    );
  }

  /// Per-account XIRR. One [XirrReport] per [accountIds]; accounts without
  /// any matching transactions still get an entry with an empty flow list
  /// and a [XirrFallbackAbsolute] solution, so callers can render an
  /// exhaustive table without juggling missing keys.
  Future<Map<String, XirrReport>> byAccountXirr({
    required Iterable<String> accountIds,
    required DateTime from,
    required DateTime to,
  }) async {
    final out = <String, XirrReport>{};
    for (final accountId in accountIds) {
      out[accountId] = await _compute(
        from: from,
        to: to,
        scope: CashFlowScope.account,
        filter: CashFlowFilter(
          accountIds: {accountId},
          ownerUserId: ownerUserId,
        ),
        lotPredicate: (l) => l.accountId == accountId,
        // Account XIRR uses external cash flows only; bookends still come
        // from the asset positions held in this account.
      );
    }
    return out;
  }

  /// XIRR per category / industry / arbitrary asset bucket.
  ///
  /// Each bucket is treated as a "virtual asset": the cash flows are the
  /// position-scope flows of every asset in the bucket, the bookends are the
  /// summed position values at `from` and `to`. This is the same math as a
  /// single-asset XIRR with multiple `assetIds` allowed in the filter.
  Future<Map<String, XirrReport>> byBucketXirr({
    required XirrBucketing bucketing,
    required DateTime from,
    required DateTime to,
  }) async {
    final out = <String, XirrReport>{};
    for (final entry in bucketing.bucketsToAssets.entries) {
      final ids = entry.value;
      out[entry.key] = await _compute(
        from: from,
        to: to,
        scope: CashFlowScope.position,
        filter: CashFlowFilter(assetIds: ids, ownerUserId: ownerUserId),
        lotPredicate: (l) => ids.contains(l.assetId),
      );
    }
    return out;
  }

  Future<XirrReport> _compute({
    required DateTime from,
    required DateTime to,
    required CashFlowScope scope,
    required CashFlowFilter filter,
    required bool Function(Lot) lotPredicate,
  }) async {
    if (!to.isAfter(from)) {
      throw ArgumentError('XIRR window requires to > from (got $from .. $to).');
    }

    final txns = await transactions.transactionsInRange(
      ownerUserId: ownerUserId,
      from: from,
      to: to,
    );

    // In-window flows are half-open `(from, to]`: the initial bookend at
    // `from` already captures everything at or before `from`, so a buy
    // executed exactly at `from` would be double-counted if we re-included
    // it here. The upper bound stays inclusive — a buy on `to` is offset by
    // its share of the terminal bookend.
    final flows = _extractor.extract(
      transactions: txns.where((t) => t.tradeDate.isAfter(from)),
      scope: scope,
      range: DateRange(from: from, to: to),
      filter: filter,
    );

    // Bookend valuations.
    final initialLots = await lots.lotsAt(ownerUserId: ownerUserId, asOf: from);
    final terminalLots = await lots.lotsAt(ownerUserId: ownerUserId, asOf: to);

    final initialValue = _valuePositions(
      lots: initialLots.where(lotPredicate),
      asOf: from,
    );
    final terminalValue = _valuePositions(
      lots: terminalLots.where(lotPredicate),
      asOf: to,
    );

    final allFlows = <XirrCashFlow>[
      if (initialValue.sign > 0)
        XirrCashFlow(date: from, amount: -initialValue.toDouble()),
      ...flows,
      if (terminalValue.sign > 0)
        XirrCashFlow(date: to, amount: terminalValue.toDouble()),
    ];

    final solution = _engine.compute(allFlows);
    return XirrReport(
      solution: solution,
      flows: allFlows,
      from: from,
      to: to,
      baseCurrency: baseCurrency,
      initialValueInBase: initialValue,
      terminalValueInBase: terminalValue,
      scope: scope,
    );
  }

  /// Sum `remainingQuantity * price(asOf)` across [lots], converting each
  /// asset's market value at the [asOf]-day FX rate. Lots whose asset has no
  /// price observed at or before [asOf] contribute zero — the same fallback
  /// rule as `HoldingComputer.snapshot`.
  Decimal _valuePositions({
    required Iterable<Lot> lots,
    required DateTime asOf,
  }) {
    // Group by (assetId, currency) so we hit the price source once per
    // asset rather than once per lot.
    final byAsset = <String, _AggregateAt>{};
    for (final l in lots) {
      if (l.isClosed) continue;
      final agg = byAsset.putIfAbsent(
        l.assetId,
        () => _AggregateAt(currency: l.currency),
      );
      agg.quantity += l.remainingQuantity;
    }
    var total = Decimal.zero;
    for (final entry in byAsset.entries) {
      final agg = entry.value;
      final priceObs = prices.priceFor(entry.key, asOf: asOf);
      if (priceObs == null) continue;
      final mvAsset = agg.quantity * priceObs.price;
      final mvBase = converter
          .convert(Money(mvAsset, priceObs.currency), baseCurrency, on: asOf)
          .amount;
      total += mvBase;
    }
    return total;
  }
}

class _AggregateAt {
  _AggregateAt({required this.currency});
  Decimal quantity = Decimal.zero;
  final String currency;
}
