import 'package:decimal/decimal.dart';

import '../../data/domain/enums.dart';
import '../../data/domain/transaction.dart';
import '../values/money.dart';
import 'asset_price_source.dart';
import 'currency_converter.dart';
import 'liability_balance_source.dart';

/// Sampling cadence for [NetWorthService.timeSeries].
///
/// - [day]: every UTC calendar day in `[from, to]`.
/// - [week]: every 7 UTC days starting at `from`; the final sample is forced
///   to land on `to` so the chart always ends "today".
/// - [month]: the **last day of each calendar month** that falls in
///   `[from, to]`, plus `from` and `to` as bracket samples. End-of-month
///   anchoring is what users expect on a long-horizon FIRE chart.
enum NetWorthGranularity { day, week, month }

/// One observation on the historical net-worth curve.
///
/// All [Money] fields are denominated in the [NetWorthSeries.baseCurrency]
/// the series was computed in. [netCashFlow] is the **net external** cash
/// flow (deposit − withdraw, FX-converted to base currency at each
/// transaction's trade date) that fell strictly after the previous sample's
/// `asOf` and at-or-before this sample's `asOf`. The first sample carries
/// every flow at-or-before `from`.
class NetWorthSample {
  NetWorthSample({
    required this.asOf,
    required this.assets,
    required this.liabilities,
    required this.netWorth,
    required this.netCashFlow,
  });

  final DateTime asOf;
  final Money assets;
  final Money liabilities;
  final Money netWorth;
  final Money netCashFlow;

  @override
  String toString() =>
      'NetWorthSample(asOf=${asOf.toIso8601String().substring(0, 10)}, '
      'assets=$assets, liabilities=$liabilities, netWorth=$netWorth, '
      'netCashFlow=$netCashFlow)';
}

/// External cash flow tagged for downstream XIRR / time-weighted-return
/// computation. Sign convention: `amount > 0` = capital flowed **into** the
/// portfolio (deposit), `amount < 0` = capital flowed **out** (withdraw).
///
/// Only `deposit` and `withdraw` cross the "money I track" boundary.
/// Internal `transferIn` / `transferOut` between two tracked accounts is
/// excluded — those net to zero across the portfolio. Dividends and
/// interest are returns ON capital, not flows OF capital, and are also
/// excluded.
class NetWorthCashFlow {
  NetWorthCashFlow({
    required this.transactionId,
    required this.date,
    required this.amount,
    required this.type,
  });

  final String transactionId;
  final DateTime date;
  final Money amount;
  final TransactionType type;
}

/// Result returned by [NetWorthService.timeSeries]. Holds the samples,
/// the external cash-flow ledger (pre-FX-converted to base currency), and
/// echoes the inputs for downstream consumers that want to label charts.
class NetWorthSeries {
  NetWorthSeries({
    required this.from,
    required this.to,
    required this.granularity,
    required this.baseCurrency,
    required this.samples,
    required this.cashFlows,
  });

  final DateTime from;
  final DateTime to;
  final NetWorthGranularity granularity;
  final String baseCurrency;
  final List<NetWorthSample> samples;
  final List<NetWorthCashFlow> cashFlows;
}

/// Pure-domain service that computes a historical net-worth curve from a
/// stream of [Transaction]s plus a price book, a liability-balance book,
/// and a currency converter.
///
/// Algorithm — single pass over transactions, one snapshot per sample:
///   1. Sort transactions by `tradeDate` ascending.
///   2. For each sample date `T` in [NetWorthGranularity], replay every
///      transaction with `tradeDate ≤ T` against running per-asset and
///      per-cash positions.
///   3. Value positions at `T` using [AssetPriceSource]; FX-convert to
///      [baseCurrency] using [CurrencyConverter] at `T`.
///   4. Subtract liability outstanding from [LiabilityBalanceSource].
///   5. Bucket external cash flows (deposit / withdraw) into the sample
///      they fall before, and surface them on [NetWorthSeries.cashFlows]
///      verbatim for XIRR.
///
/// Cache: a per-instance [NetWorthCache] memoises results keyed by
/// `(from, to, granularity, baseCurrency, txFingerprint)`. The
/// `txFingerprint` is `(count, lastTradeDate)` — sufficient when
/// transactions only append (the actual usage pattern in this app's
/// OpLog-backed sync). For mid-stream edits, callers must call
/// [invalidate].
class NetWorthService {
  NetWorthService({
    required this.priceSource,
    required this.liabilitySource,
    required this.converter,
    NetWorthCache? cache,
  }) : _cache = cache ?? NetWorthCache();

  final AssetPriceSource priceSource;
  final LiabilityBalanceSource liabilitySource;
  final CurrencyConverter converter;
  final NetWorthCache _cache;

  /// Compute (or return cached) net-worth time series in [baseCurrency]
  /// across `[from, to]` at [granularity].
  NetWorthSeries timeSeries({
    required Iterable<Transaction> transactions,
    required DateTime from,
    required DateTime to,
    required NetWorthGranularity granularity,
    required String baseCurrency,
  }) {
    final fromDay = _floorToDay(from);
    final toDay = _floorToDay(to);
    if (toDay.isBefore(fromDay)) {
      throw ArgumentError(
        'to (${to.toIso8601String()}) is before from '
        '(${from.toIso8601String()}).',
      );
    }
    final base = _normalizeCurrency(baseCurrency);

    final txs = transactions.toList()
      ..sort((a, b) => a.tradeDate.compareTo(b.tradeDate));

    final fingerprint = _fingerprint(txs);
    final key = _CacheKey(fromDay, toDay, granularity, base, fingerprint);
    final cached = _cache.get(key);
    if (cached != null) return cached;

    final sampleDates = _generateSampleDates(fromDay, toDay, granularity);
    final positions = <_PositionKey, Decimal>{};
    final cashBalances = <_CashKey, Decimal>{};
    final cashFlows = <NetWorthCashFlow>[];
    final samples = <NetWorthSample>[];

    var txIdx = 0;
    var bucketFlow = Money.zero(base);

    for (final date in sampleDates) {
      while (txIdx < txs.length &&
          !_floorToDay(txs[txIdx].tradeDate).isAfter(date)) {
        final tx = txs[txIdx];
        _applyTransaction(tx, positions, cashBalances);
        final external = _externalCashFlow(tx);
        if (external != null) {
          final converted = converter.convert(external, base, on: tx.tradeDate);
          bucketFlow = bucketFlow + converted;
          cashFlows.add(
            NetWorthCashFlow(
              transactionId: tx.id,
              date: tx.tradeDate,
              amount: converted,
              type: tx.type,
            ),
          );
        }
        txIdx++;
      }

      final assets = _valueAssets(date, positions, cashBalances, base);
      final liabilities = _valueLiabilities(date, base);
      samples.add(
        NetWorthSample(
          asOf: date,
          assets: assets,
          liabilities: liabilities,
          netWorth: assets - liabilities,
          netCashFlow: bucketFlow,
        ),
      );
      bucketFlow = Money.zero(base);
    }

    final series = NetWorthSeries(
      from: fromDay,
      to: toDay,
      granularity: granularity,
      baseCurrency: base,
      samples: samples,
      cashFlows: cashFlows,
    );
    _cache.put(key, series);
    return series;
  }

  /// Drop all memoised series. Call after persistent state mutates in a
  /// way the fingerprint cannot detect (mid-stream transaction edits,
  /// price-book changes, FX-rate corrections).
  void invalidate() => _cache.invalidate();

  Money _valueAssets(
    DateTime date,
    Map<_PositionKey, Decimal> positions,
    Map<_CashKey, Decimal> cashBalances,
    String base,
  ) {
    var total = Money.zero(base);
    positions.forEach((key, qty) {
      if (qty.sign == 0) return;
      final price = priceSource.priceOn(key.assetId, date);
      if (price == null) return;
      final ccy = priceSource.currencyOf(key.assetId);
      if (ccy == null) return;
      final native = Money(qty * price, ccy);
      total = total + converter.convert(native, base, on: date);
    });
    cashBalances.forEach((key, balance) {
      if (balance.sign == 0) return;
      final native = Money(balance, key.currency);
      total = total + converter.convert(native, base, on: date);
    });
    return total;
  }

  Money _valueLiabilities(DateTime date, String base) {
    var total = Money.zero(base);
    for (final lb in liabilitySource.balancesOn(date)) {
      total = total + converter.convert(lb.outstanding, base, on: date);
    }
    return total;
  }

  void _applyTransaction(
    Transaction tx,
    Map<_PositionKey, Decimal> positions,
    Map<_CashKey, Decimal> cashBalances,
  ) {
    final fee = tx.fee ?? Decimal.zero;
    final tax = tx.tax ?? Decimal.zero;
    final qty = tx.quantity;
    final notional = qty * tx.price;
    final cashKey = _CashKey(tx.accountId, _normalizeCurrency(tx.currency));

    void addPosition(Decimal delta) {
      if (tx.assetId == null) return;
      final key = _PositionKey(tx.accountId, tx.assetId!);
      positions[key] = (positions[key] ?? Decimal.zero) + delta;
    }

    void addCash(Decimal delta) {
      cashBalances[cashKey] = (cashBalances[cashKey] ?? Decimal.zero) + delta;
    }

    switch (tx.type) {
      case TransactionType.buy:
        addPosition(qty);
        addCash(-(notional + fee + tax));
      case TransactionType.sell:
        addPosition(-qty);
        addCash(notional - fee - tax);
      case TransactionType.dividend:
      case TransactionType.interest:
      case TransactionType.deposit:
      case TransactionType.transferIn:
        addCash(notional);
      case TransactionType.withdraw:
      case TransactionType.transferOut:
      case TransactionType.fee:
      case TransactionType.tax:
        addCash(-notional);
      case TransactionType.reinvest:
        // Cash dividend immediately purchases new shares: net cash impact
        // is zero, share count grows.
        addPosition(qty);
      case TransactionType.split:
        // Stock split / bonus shares: only the share count moves.
        addPosition(qty);
      case TransactionType.valuationAdjust:
        // Mark-to-market for non-quoted assets (real estate, vehicles).
        // The new valuation is fed in via the AssetPriceSource — the
        // transaction itself does not move the position quantity.
        break;
    }
  }

  Money? _externalCashFlow(Transaction tx) {
    final notional = tx.quantity * tx.price;
    final ccy = _normalizeCurrency(tx.currency);
    switch (tx.type) {
      case TransactionType.deposit:
        return Money(notional, ccy);
      case TransactionType.withdraw:
        return Money(-notional, ccy);
      // Internal-to-portfolio movements and returns are not cash flows for
      // XIRR purposes.
      case TransactionType.buy:
      case TransactionType.sell:
      case TransactionType.dividend:
      case TransactionType.interest:
      case TransactionType.reinvest:
      case TransactionType.transferIn:
      case TransactionType.transferOut:
      case TransactionType.fee:
      case TransactionType.tax:
      case TransactionType.valuationAdjust:
      case TransactionType.split:
        return null;
    }
  }

  static _Fingerprint _fingerprint(List<Transaction> sortedTxs) {
    if (sortedTxs.isEmpty) return const _Fingerprint(0, null);
    return _Fingerprint(sortedTxs.length, sortedTxs.last.tradeDate);
  }
}

/// Memoisation store for [NetWorthService.timeSeries] results. Exposed so
/// callers can share a single cache across multiple service instances or
/// inject a clock-bound LRU in production.
class NetWorthCache {
  final Map<_CacheKey, NetWorthSeries> _store = {};

  NetWorthSeries? get(Object key) => _store[key];
  void put(Object key, NetWorthSeries series) {
    _store[key as _CacheKey] = series;
  }

  void invalidate() => _store.clear();
  int get size => _store.length;
}

DateTime _floorToDay(DateTime d) =>
    d.isUtc ? DateTime.utc(d.year, d.month, d.day) : DateTime.utc(d.toUtc().year, d.toUtc().month, d.toUtc().day);

String _normalizeCurrency(String code) {
  final trimmed = code.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(code, 'currency', 'must not be empty');
  }
  return trimmed.toUpperCase();
}

List<DateTime> _generateSampleDates(
  DateTime fromDay,
  DateTime toDay,
  NetWorthGranularity granularity,
) {
  switch (granularity) {
    case NetWorthGranularity.day:
      final days = toDay.difference(fromDay).inDays;
      return [for (var i = 0; i <= days; i++) fromDay.add(Duration(days: i))];
    case NetWorthGranularity.week:
      final dates = <DateTime>[];
      var cursor = fromDay;
      while (!cursor.isAfter(toDay)) {
        dates.add(cursor);
        cursor = cursor.add(const Duration(days: 7));
      }
      if (dates.isEmpty || dates.last != toDay) dates.add(toDay);
      return dates;
    case NetWorthGranularity.month:
      final dates = <DateTime>[fromDay];
      // Walk month-end boundaries that lie strictly after fromDay.
      var year = fromDay.year;
      var month = fromDay.month;
      while (true) {
        final monthEnd = DateTime.utc(year, month + 1, 0);
        if (monthEnd.isAfter(toDay)) break;
        if (monthEnd.isAfter(fromDay)) dates.add(monthEnd);
        if (month == 12) {
          year += 1;
          month = 1;
        } else {
          month += 1;
        }
      }
      if (dates.last != toDay) dates.add(toDay);
      return dates;
  }
}

class _PositionKey {
  const _PositionKey(this.accountId, this.assetId);
  final String accountId;
  final String assetId;

  @override
  bool operator ==(Object other) =>
      other is _PositionKey &&
      other.accountId == accountId &&
      other.assetId == assetId;

  @override
  int get hashCode => Object.hash(accountId, assetId);
}

class _CashKey {
  const _CashKey(this.accountId, this.currency);
  final String accountId;
  final String currency;

  @override
  bool operator ==(Object other) =>
      other is _CashKey &&
      other.accountId == accountId &&
      other.currency == currency;

  @override
  int get hashCode => Object.hash(accountId, currency);
}

class _CacheKey {
  const _CacheKey(
    this.from,
    this.to,
    this.granularity,
    this.baseCurrency,
    this.fingerprint,
  );

  final DateTime from;
  final DateTime to;
  final NetWorthGranularity granularity;
  final String baseCurrency;
  final _Fingerprint fingerprint;

  @override
  bool operator ==(Object other) =>
      other is _CacheKey &&
      other.from == from &&
      other.to == to &&
      other.granularity == granularity &&
      other.baseCurrency == baseCurrency &&
      other.fingerprint == fingerprint;

  @override
  int get hashCode =>
      Object.hash(from, to, granularity, baseCurrency, fingerprint);
}

class _Fingerprint {
  const _Fingerprint(this.count, this.lastTradeDate);
  final int count;
  final DateTime? lastTradeDate;

  @override
  bool operator ==(Object other) =>
      other is _Fingerprint &&
      other.count == count &&
      other.lastTradeDate == lastTradeDate;

  @override
  int get hashCode => Object.hash(count, lastTradeDate);
}
