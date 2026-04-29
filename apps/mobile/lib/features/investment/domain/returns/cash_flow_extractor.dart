import 'package:decimal/decimal.dart';

import '../../../../data/domain/enums.dart';
import '../../../../data/domain/transaction.dart';
import '../../../../domain/services/currency_converter.dart';
import '../../../../domain/values/money.dart';
import 'xirr_engine.dart';

/// Scope of the cash-flow extraction. Determines which transaction types and
/// which transaction-vs-position fields qualify as a flow.
///
/// Two distinct mental models are at play:
///
/// - [position] — "from the asset's perspective". Buys are outflows
///   (capital deployed), sells are inflows (capital recovered), dividends
///   are inflows. External cash flows (deposit/withdraw) are *not*
///   relevant — they happen at the account, not the asset. Used for
///   single-asset XIRR and for category / industry roll-ups (which are
///   sums of position flows).
///
/// - [account] — "from the user's perspective on this account / portfolio".
///   Internal trades (buy/sell/dividend) are NOT cash flows because they
///   stay inside the account; what crosses the boundary is deposits and
///   withdrawals. The terminal value of the entire account closes out the
///   IRR window. Used for portfolio XIRR and for per-account XIRR.
enum CashFlowScope { position, account }

/// Inclusive date filter. The extractor selects transactions where
/// `from <= tradeDate <= to`. Bookend valuations (initial / terminal) are
/// the caller's responsibility — see `returns_service.dart`.
class DateRange {
  const DateRange({required this.from, required this.to});

  final DateTime from;
  final DateTime to;

  bool contains(DateTime t) => !t.isBefore(from) && !t.isAfter(to);
}

/// Per-transaction filter applied before sign extraction. Pass `null` for
/// the field to skip the corresponding filter.
class CashFlowFilter {
  const CashFlowFilter({this.assetIds, this.accountIds, this.ownerUserId});

  /// If non-null, only transactions whose `assetId` is in this set match.
  /// Used by single-asset and by category/industry extraction (the caller
  /// resolves "category X" → set of asset IDs first).
  final Set<String>? assetIds;

  /// If non-null, only transactions whose `accountId` is in this set match.
  final Set<String>? accountIds;

  /// If non-null, only transactions whose `sync.ownerUserId` matches this
  /// value. Always set this in production — leaking flows across users would
  /// silently inflate one user's IRR using another's trades.
  final String? ownerUserId;

  bool matches(Transaction tx) {
    if (ownerUserId != null && tx.sync.ownerUserId != ownerUserId) return false;
    if (tx.sync.deletedAt != null) return false;
    if (accountIds != null && !accountIds!.contains(tx.accountId)) return false;
    if (assetIds != null) {
      final id = tx.assetId;
      if (id == null || !assetIds!.contains(id)) return false;
    }
    return true;
  }
}

/// Pure domain extractor: transactions → XIRR cash flows in **base currency**.
///
/// Extraction is deterministic and side-effect-free. Two collaborators come
/// in from the boundary:
///
/// - [CurrencyConverter] — converts each native cash flow at its trade date
///   FX. This is the "multi-currency unification" requirement: a USD
///   dividend, a CNY buy and a HKD sell all land on the same NPV curve.
///
/// - The caller supplies the [Transaction]s already filtered to a window /
///   owner — that filter is normally a Drift query in production but a flat
///   list in tests. The extractor doesn't read the filesystem.
class CashFlowExtractor {
  const CashFlowExtractor({
    required this.converter,
    required this.baseCurrency,
  });

  final CurrencyConverter converter;
  final String baseCurrency;

  /// Convert [transactions] (already loaded; may be in any order) into a
  /// list of [XirrCashFlow]s in [baseCurrency], applying [filter] and
  /// honoring [scope].
  ///
  /// Returns an unsorted list — [XirrEngine.compute] sorts internally, so
  /// avoiding a sort here keeps the hot path tight.
  List<XirrCashFlow> extract({
    required Iterable<Transaction> transactions,
    required CashFlowScope scope,
    required DateRange range,
    CashFlowFilter? filter,
  }) {
    final flows = <XirrCashFlow>[];
    for (final tx in transactions) {
      if (!range.contains(tx.tradeDate)) continue;
      if (filter != null && !filter.matches(tx)) continue;

      final native = scope == CashFlowScope.position
          ? _positionFlow(tx)
          : _accountFlow(tx);
      if (native == null) continue;

      // Same-currency short-circuits inside the converter, so paying the
      // method-call cost is fine for the common "USD-only" portfolio.
      final converted = converter
          .convert(native, baseCurrency, on: tx.tradeDate)
          .amount;
      // Skip zero-amount flows so the engine doesn't waste an iteration on a
      // term that contributes nothing to NPV.
      if (converted.sign == 0) continue;
      flows.add(XirrCashFlow(date: tx.tradeDate, amount: converted.toDouble()));
    }
    return flows;
  }

  /// Position-scope: the asset is the unit of analysis. Cash flows are the
  /// money that crossed the line between "user's wallet" and "this position".
  ///
  /// Returns `null` for transactions that don't move money against the
  /// position (deposits, transfers, valuation marks, splits — splits adjust
  /// quantity but not P&L, and stand-alone fee/tax rows that don't reference
  /// a specific asset).
  static Money? _positionFlow(Transaction tx) {
    if (tx.assetId == null) return null;
    final qty = tx.quantity;
    final price = tx.price;
    final fee = tx.fee ?? Decimal.zero;
    final tax = tx.tax ?? Decimal.zero;
    final notional = qty * price;
    final ccy = tx.currency;

    switch (tx.type) {
      case TransactionType.buy:
        // Outflow = price + fee + tax (you paid all of it to acquire shares).
        final out = notional + fee + tax;
        return out.sign == 0 ? null : Money(-out, ccy);
      case TransactionType.sell:
        // Inflow = proceeds − fee − tax. Negative net (rare — huge fees on a
        // tiny sell) is allowed; the engine handles the sign.
        return Money(notional - fee - tax, ccy);
      case TransactionType.dividend:
      case TransactionType.interest:
        // Asset-level cash returned to the user. `quantity * price` matches
        // how net_worth_service interprets dividend transactions.
        final net = notional - tax;
        return net.sign == 0 ? null : Money(net, ccy);
      case TransactionType.reinvest:
        // DRIP: the dividend cash that was just received is immediately
        // spent on new shares. Net asset-level flow is zero. We model the
        // outflow leg here so the matching dividend tx (if separately
        // logged) and this row offset to zero. If callers prefer to see the
        // gross dividend, they can split into two transactions.
        final out = notional + fee + tax;
        return out.sign == 0 ? null : Money(-out, ccy);
      case TransactionType.fee:
      case TransactionType.tax:
        // Fee / tax rows that name an asset: outflow charged to the
        // position (typical for management fees on a fund holding).
        return notional.sign == 0 ? null : Money(-notional, ccy);
      case TransactionType.deposit:
      case TransactionType.withdraw:
      case TransactionType.transferIn:
      case TransactionType.transferOut:
      case TransactionType.valuationAdjust:
      case TransactionType.split:
      case TransactionType.liabilityPayment:
        return null;
    }
  }

  /// Account / portfolio scope: only **external** cash flows count. Internal
  /// trades and dividends stay inside the account boundary, so they
  /// shouldn't move the IRR — the terminal portfolio valuation already
  /// reflects them.
  static Money? _accountFlow(Transaction tx) {
    final qty = tx.quantity;
    final notional = qty * tx.price;
    final ccy = tx.currency;
    switch (tx.type) {
      case TransactionType.deposit:
      case TransactionType.transferIn:
        return notional.sign == 0 ? null : Money(-notional, ccy);
      case TransactionType.withdraw:
      case TransactionType.transferOut:
        return notional.sign == 0 ? null : Money(notional, ccy);
      case TransactionType.buy:
      case TransactionType.sell:
      case TransactionType.dividend:
      case TransactionType.interest:
      case TransactionType.reinvest:
      case TransactionType.fee:
      case TransactionType.tax:
      case TransactionType.valuationAdjust:
      case TransactionType.split:
      case TransactionType.liabilityPayment:
        return null;
    }
  }
}
