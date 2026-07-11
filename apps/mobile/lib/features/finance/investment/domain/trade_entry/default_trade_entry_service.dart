import 'package:decimal/decimal.dart';
import 'package:naviwealth/features/finance/domain/fx/currency_converter.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart'
    show AssetType;
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/historical_bar.dart';
import 'package:naviwealth/features/finance/market/domain/market_data_service.dart';
import 'package:uuid/uuid.dart';

import '../cost_basis/fifo_strategy.dart';
import '../cost_basis_engine.dart';
import '../models/lot.dart';
import '../models/trade_events.dart';
import 'decimal_precision.dart';
import 'trade_draft.dart';
import 'trade_entry_errors.dart';
import 'trade_entry_plan.dart';
import 'trade_entry_service.dart';

/// Default [TradeEntryService] implementation. Pure orchestration on top of
/// the domain primitives; no I/O beyond the injected market-data service
/// and optional market price backfill.
class DefaultTradeEntryService implements TradeEntryService {
  DefaultTradeEntryService({
    MarketDataService? market,
    Future<MarketDataService> Function()? marketLoader,
    required CurrencyConverter fx,
    CostBasisEngine? engine,
    String Function()? idGenerator,
    this.permissiveSells = false,
    this.marketLookupTimeout = const Duration(seconds: 12),
    int decimalScale = 16,
  }) : assert(
         (market == null) != (marketLoader == null),
         'Provide exactly one of market or marketLoader.',
       ),
       _marketLoader = marketLoader ?? (() async => market!),
       _fx = fx,
       _engine = engine ?? CostBasisEngine(strategy: const FifoStrategy()),
       _idGenerator = idGenerator ?? _defaultId,
       _decimalScale = decimalScale;

  static const Uuid _uuid = Uuid();
  static String _defaultId() => _uuid.v4();

  final Future<MarketDataService> Function() _marketLoader;
  final CurrencyConverter _fx;
  final CostBasisEngine _engine;
  final String Function() _idGenerator;
  final int _decimalScale;

  /// When `true`, sells that exceed available lots succeed and surface the
  /// shortfall in [TradeEntryPlan.unfulfilledQuantity]. The default
  /// `false` is strict — the service throws so the UI can prompt the user
  /// to fix the entry instead of silently writing a negative position.
  final bool permissiveSells;

  /// Total deadline for resolving the market service and fetching historical
  /// bars. This covers provider initialization, cache reads, rate limiting,
  /// retries, and HTTP so an interactive form can never wait indefinitely.
  final Duration marketLookupTimeout;

  @override
  Future<TradeEntryPlan> buildPlan(
    TradeDraft draft, {
    required List<Lot> openLots,
  }) async {
    _validate(draft);

    final priceResult = draft.price != null
        ? _ResolvedPrice(
            price: draft.price!,
            provenance: PriceProvenance.userSupplied,
          )
        : await _backfillPrice(draft);

    final trade = PlannedTrade(
      id: draft.transactionId ?? _idGenerator(),
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
    );

    switch (draft.type) {
      case TradeType.buy:
        return _planOpening(draft, trade, priceResult.provenance);
      case TradeType.sell:
        return _planClosing(
          draft,
          trade,
          priceResult.provenance,
          openLots: openLots,
        );
      case TradeType.valuationAdjust:
        // Valuation adjusts write a price observation and a balancing
        // journal entry; they do not open or close lots.
        return TradeEntryPlan(trade: trade, pricing: priceResult.provenance);
    }
  }

  // ────────────────────────── internals ──────────────────────────

  void _validate(TradeDraft draft) {
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
    if (draft.type != TradeType.valuationAdjust) {
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
      final resp = await _marketLoader()
          .then(
            (market) => market.getHistorical(
              draft.asset.symbol,
              from: from,
              to: to,
              market: assetMarket,
            ),
          )
          .timeout(marketLookupTimeout);
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
    var provenance = PriceProvenance.backfilled(source: source, asOf: barAsOf);

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
    PlannedTrade trade,
    PriceProvenance pricing,
  ) {
    final lot = _engine.applyBuy(
      BuyEvent(
        transactionId: trade.id,
        accountId: draft.accountId,
        assetId: draft.asset.id,
        currency: draft.currency,
        quantity: draft.quantity,
        pricePerUnit: trade.price,
        fee: draft.feeOrZero,
        tradeDate: draft.tradeDate,
      ),
    );
    return TradeEntryPlan(trade: trade, createdLot: lot, pricing: pricing);
  }

  TradeEntryPlan _planClosing(
    TradeDraft draft,
    PlannedTrade trade,
    PriceProvenance pricing, {
    required List<Lot> openLots,
  }) {
    final result = _engine.applySell(
      SellEvent(
        transactionId: trade.id,
        accountId: draft.accountId,
        assetId: draft.asset.id,
        currency: draft.currency,
        quantity: draft.quantity,
        pricePerUnit: trade.price,
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

    return TradeEntryPlan(
      trade: trade,
      updatedLots: _onlyChanged(openLots, result.updatedLots),
      realizedPnL: result.realizedPnL,
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
