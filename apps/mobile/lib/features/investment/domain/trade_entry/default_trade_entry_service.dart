import 'package:decimal/decimal.dart';
import 'package:uuid/uuid.dart';

import '../../../../data/domain/asset.dart';
import '../../../../data/domain/enums.dart';
import '../../../../data/domain/hlc.dart';
import '../../../../data/domain/sync_meta.dart';
import '../../../../data/domain/transaction.dart';
import '../../../../domain/entities/historical_bar.dart';
import '../../../../domain/services/currency_converter.dart';
import '../../../../domain/services/market_data_service.dart';
import '../../../../domain/values/asset_market.dart';
import '../../../../domain/values/money.dart';
import '../cost_basis/fifo_strategy.dart';
import '../cost_basis_engine.dart';
import '../models/lot.dart';
import '../models/trade_events.dart';
import 'decimal_precision.dart';
import 'trade_draft.dart';
import 'trade_entry_errors.dart';
import 'trade_entry_plan.dart';
import 'trade_entry_service.dart';

/// Async supplier for the next HLC tick. Keeps the service decoupled from
/// SyncEngine — tests pass a counter-based stub, prod wires
/// `syncEngine.stampHlc`.
typedef HlcStamper = Future<Hlc> Function();

/// Wall-clock supplier (`now`) — same role as the one used by the market
/// data layer. Indirected here so tests can fix the clock for deterministic
/// `updatedAt` and tradeDate comparisons.
typedef NowProvider = DateTime Function();

/// Default [TradeEntryService] implementation. Pure orchestration on top of
/// the domain primitives; no I/O beyond the injected market-data service
/// and HLC stamper.
class DefaultTradeEntryService implements TradeEntryService {
  DefaultTradeEntryService({
    required MarketDataService market,
    required CurrencyConverter fx,
    required HlcStamper stampHlc,
    required this.ownerUserId,
    required this.deviceId,
    CostBasisEngine? engine,
    String Function()? idGenerator,
    NowProvider? now,
    this.permissiveSells = false,
    int decimalScale = 16,
  })  : _market = market,
        _fx = fx,
        _stampHlc = stampHlc,
        _engine = engine ?? CostBasisEngine(strategy: const FifoStrategy()),
        _idGenerator = idGenerator ?? _defaultId,
        _now = now ?? DateTime.now,
        _decimalScale = decimalScale;

  static const Uuid _uuid = Uuid();
  static String _defaultId() => _uuid.v4();

  final MarketDataService _market;
  final CurrencyConverter _fx;
  final HlcStamper _stampHlc;
  final CostBasisEngine _engine;
  final String Function() _idGenerator;
  final NowProvider _now;
  final int _decimalScale;
  final String ownerUserId;
  final String deviceId;

  /// When `true`, sells that exceed available lots succeed and surface the
  /// shortfall in [TradeEntryPlan.unfulfilledQuantity]. The default
  /// `false` is strict — the service throws so the UI can prompt the user
  /// to fix the entry instead of silently writing a negative position.
  final bool permissiveSells;

  @override
  Future<TradeEntryPlan> buildPlan(
    TradeDraft draft, {
    required List<Lot> openLots,
  }) async {
    _validate(draft);

    final priceResult = draft.price != null
        ? _ResolvedPrice(price: draft.price!, provenance: PriceProvenance.userSupplied)
        : await _backfillPrice(draft);

    final transactionId = draft.transactionId ?? _idGenerator();
    final hlc = await _stampHlc();
    final tx = Transaction(
      id: transactionId,
      accountId: draft.accountId,
      assetId: draft.asset.id,
      type: draft.type,
      quantity: draft.quantity,
      price: priceResult.price,
      currency: draft.currency,
      tradeDate: draft.tradeDate,
      settleDate: draft.settleDate,
      fee: draft.fee,
      tax: draft.tax,
      counterAccountId: draft.counterAccountId,
      note: draft.note,
      lotId: null,
      sync: SyncMeta(
        ownerUserId: ownerUserId,
        updatedAt: _now(),
        updatedByDevice: deviceId,
        hlc: hlc,
      ),
    );

    switch (draft.type) {
      case TransactionType.buy:
      case TransactionType.transferIn:
        return _planOpening(draft, tx, priceResult.provenance);
      case TransactionType.sell:
      case TransactionType.transferOut:
        return _planClosing(
          draft,
          tx,
          priceResult.provenance,
          openLots: openLots,
          realize: draft.type == TransactionType.sell,
        );
      case TransactionType.valuationAdjust:
        // Valuation adjusts are fact-table notes only — they update the
        // asset's last price (handled by the caller's repo), no Lot
        // implication.
        return TradeEntryPlan(
          transaction: tx,
          pricing: priceResult.provenance,
        );
      default:
        // Defensive: validation rejects everything else upstream.
        throw TradeEntryException(
          TradeEntryErrorCode.fieldRequired,
          'Unsupported transaction type for trade-entry: ${draft.type.name}',
          field: 'type',
        );
    }
  }

  @override
  TransactionDeletePlan buildDeletePlan({
    required String transactionId,
    required List<String> createdLotIds,
  }) {
    if (transactionId.isEmpty) {
      throw TradeEntryException(
        TradeEntryErrorCode.fieldRequired,
        'transactionId is required',
        field: 'transactionId',
      );
    }
    return TransactionDeletePlan(
      transactionId: transactionId,
      releaseLotIds: List.unmodifiable(createdLotIds),
    );
  }

  // ────────────────────────── internals ──────────────────────────

  void _validate(TradeDraft draft) {
    if (!draft.isSecurityTrade) {
      throw TradeEntryException(
        TradeEntryErrorCode.fieldRequired,
        'Trade-entry only handles security trades; got ${draft.type.name}',
        field: 'type',
      );
    }
    if (draft.accountId.isEmpty) {
      throw TradeEntryException(
        TradeEntryErrorCode.fieldRequired,
        'accountId is required',
        field: 'accountId',
      );
    }
    if (draft.asset.id.isEmpty) {
      throw TradeEntryException(
        TradeEntryErrorCode.fieldRequired,
        'asset.id is required',
        field: 'asset.id',
      );
    }
    if (draft.currency.trim().isEmpty) {
      throw TradeEntryException(
        TradeEntryErrorCode.fieldRequired,
        'currency is required',
        field: 'currency',
      );
    }

    // valuationAdjust is allowed to have zero quantity (it's a price-only
    // event); everything else must be a positive movement.
    if (draft.type != TransactionType.valuationAdjust) {
      if (draft.quantity.sign <= 0) {
        throw TradeEntryException(
          TradeEntryErrorCode.quantityNotPositive,
          'quantity must be > 0 for ${draft.type.name}',
          field: 'quantity',
        );
      }
    }

    final qScale = DecimalPrecisionRules.fractionalDigits(draft.quantity);
    final maxQ = DecimalPrecisionRules.maxQuantityScale(draft.asset.type);
    if (qScale > maxQ) {
      throw TradeEntryException(
        TradeEntryErrorCode.quantityScaleExceeded,
        'quantity scale $qScale exceeds max $maxQ for ${draft.asset.type.name}',
        field: 'quantity',
      );
    }

    if (draft.feeOrZero.sign < 0) {
      throw TradeEntryException(
        TradeEntryErrorCode.amountNegative,
        'fee must be >= 0',
        field: 'fee',
      );
    }
    if (draft.taxOrZero.sign < 0) {
      throw TradeEntryException(
        TradeEntryErrorCode.amountNegative,
        'tax must be >= 0',
        field: 'tax',
      );
    }

    final isTransfer = draft.type == TransactionType.transferIn ||
        draft.type == TransactionType.transferOut;
    if (isTransfer &&
        (draft.counterAccountId == null || draft.counterAccountId!.isEmpty)) {
      throw TradeEntryException(
        TradeEntryErrorCode.transferMissingCounterAccount,
        '${draft.type.name} requires counterAccountId',
        field: 'counterAccountId',
      );
    }
  }

  Future<_ResolvedPrice> _backfillPrice(TradeDraft draft) async {
    // valuationAdjust without a price reduces to "use today's quote" — we
    // could push that responsibility upstream, but it lines up with the
    // historical-bar path so the service handles it uniformly.
    final assetMarket = _routeMarket(draft.asset);
    final from = draft.tradeDate.subtract(const Duration(days: 7));
    final to = draft.tradeDate.add(const Duration(days: 1));

    late final List<HistoricalBar> bars;
    late final String source;
    DateTime? barAsOf;
    try {
      final resp = await _market.getHistorical(
        draft.asset.symbol,
        from: from,
        to: to,
        market: assetMarket,
      );
      bars = resp.data;
      source = resp.source;
    } catch (e) {
      throw TradeEntryException(
        TradeEntryErrorCode.priceUnavailable,
        'No historical bars for ${draft.asset.symbol} near '
        '${draft.tradeDate.toIso8601String().substring(0, 10)}',
        field: 'price',
        cause: e,
      );
    }

    final bar = _pickBar(bars, draft.tradeDate);
    if (bar == null) {
      throw TradeEntryException(
        TradeEntryErrorCode.priceUnavailable,
        'No bar at or before trade date for ${draft.asset.symbol}',
        field: 'price',
      );
    }
    barAsOf = bar.asOf;

    Decimal priceInTradeCurrency = bar.close;
    var provenance = PriceProvenance.backfilled(
      source: source,
      asOf: barAsOf,
    );

    final assetCurrency = draft.asset.currency;
    if (assetCurrency.toUpperCase() != draft.currency.toUpperCase()) {
      // Convert via the FX layer. We pin the conversion to the trade date
      // so the recorded price is reproducible from the raw inputs.
      try {
        final converted = _fx.convert(
          Money(bar.close, assetCurrency),
          draft.currency,
          on: draft.tradeDate,
        );
        priceInTradeCurrency = converted.amount;
        // Recompute the rate for audit. (close * rate = converted)
        Decimal? rate;
        if (bar.close.sign != 0) {
          rate = (converted.amount / bar.close).toDecimal(
            scaleOnInfinitePrecision: _decimalScale,
          );
        }
        provenance = PriceProvenance(
          wasBackfilled: true,
          marketSource: source,
          barAsOf: barAsOf,
          fxConverted: true,
          fxFromCurrency: assetCurrency.toUpperCase(),
          fxRate: rate,
          fxOn: draft.tradeDate,
        );
      } on FxRateNotFoundError catch (e) {
        throw TradeEntryException(
          TradeEntryErrorCode.currencyMismatch,
          'No FX rate for ${assetCurrency.toUpperCase()}→'
          '${draft.currency.toUpperCase()} on '
          '${draft.tradeDate.toIso8601String().substring(0, 10)}',
          field: 'currency',
          cause: e,
        );
      }
    }

    return _ResolvedPrice(price: priceInTradeCurrency, provenance: provenance);
  }

  /// Pick the bar matching [tradeDate] — same calendar day, or the most
  /// recent prior bar (markets are closed on weekends/holidays). Returns
  /// null when nothing in [bars] is at or before [tradeDate].
  HistoricalBar? _pickBar(List<HistoricalBar> bars, DateTime tradeDate) {
    if (bars.isEmpty) return null;
    final cutoff = DateTime.utc(tradeDate.year, tradeDate.month, tradeDate.day);
    HistoricalBar? best;
    for (final b in bars) {
      final bDate = DateTime.utc(b.asOf.year, b.asOf.month, b.asOf.day);
      if (bDate.isAfter(cutoff)) continue;
      if (best == null || bDate.isAfter(_truncate(best.asOf))) {
        best = b;
      }
    }
    return best;
  }

  DateTime _truncate(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  AssetMarket? _routeMarket(Asset asset) {
    switch (asset.type) {
      case AssetType.crypto:
        return AssetMarket.crypto;
      case AssetType.stock:
      case AssetType.etf:
      case AssetType.mutualFund:
        // The asset's market field is a free-form string; we route by it
        // when it matches a known token. Otherwise return null and let the
        // composite service fall through every provider.
        switch (asset.market?.toLowerCase()) {
          case 'cn':
          case 'cn-a':
          case 'cna':
          case 'sse':
          case 'szse':
            return AssetMarket.cnA;
          case 'hk':
          case 'hkex':
            return AssetMarket.hkStock;
          case 'us':
          case 'nyse':
          case 'nasdaq':
            return AssetMarket.usStock;
        }
        return null;
      default:
        return null;
    }
  }

  TradeEntryPlan _planOpening(
    TradeDraft draft,
    Transaction tx,
    PriceProvenance pricing,
  ) {
    final lot = _engine.applyBuy(
      BuyEvent(
        transactionId: tx.id,
        accountId: draft.accountId,
        assetId: draft.asset.id,
        currency: draft.currency,
        quantity: draft.quantity,
        pricePerUnit: tx.price,
        fee: draft.feeOrZero,
        tradeDate: draft.tradeDate,
      ),
    );
    return TradeEntryPlan(
      transaction: tx,
      createdLot: lot,
      pricing: pricing,
    );
  }

  TradeEntryPlan _planClosing(
    TradeDraft draft,
    Transaction tx,
    PriceProvenance pricing, {
    required List<Lot> openLots,
    required bool realize,
  }) {
    final result = _engine.applySell(
      SellEvent(
        transactionId: tx.id,
        accountId: draft.accountId,
        assetId: draft.asset.id,
        currency: draft.currency,
        quantity: draft.quantity,
        pricePerUnit: tx.price,
        fee: draft.feeOrZero,
        tradeDate: draft.tradeDate,
      ),
      openLots,
    );

    if (!permissiveSells && result.unfulfilledQuantity.sign > 0) {
      throw TradeEntryException(
        TradeEntryErrorCode.insufficientHoldings,
        'sell of ${draft.quantity} ${draft.asset.symbol} exceeds open lots '
        '(short by ${result.unfulfilledQuantity})',
        field: 'quantity',
      );
    }

    // For transferOut we drop the realized P&L records: a transfer between
    // two accounts owned by the same user isn't a tax event. Updated lot
    // state still flows through so quantities stay consistent.
    return TradeEntryPlan(
      transaction: tx,
      updatedLots: _onlyChanged(openLots, result.updatedLots),
      realizedPnL: realize ? result.realizedPnL : const [],
      unfulfilledQuantity: result.unfulfilledQuantity,
      pricing: pricing,
    );
  }

  List<Lot> _onlyChanged(List<Lot> before, List<Lot> after) {
    final beforeById = {for (final l in before) l.id: l};
    final changed = <Lot>[];
    for (final l in after) {
      final original = beforeById[l.id];
      if (original == null) continue;
      if (original.remainingQuantity != l.remainingQuantity ||
          original.originalQuantity != l.originalQuantity ||
          original.costPerUnit != l.costPerUnit) {
        changed.add(l);
      }
    }
    return changed;
  }
}

class _ResolvedPrice {
  const _ResolvedPrice({required this.price, required this.provenance});
  final Decimal price;
  final PriceProvenance provenance;
}
