/// Sealed hierarchy of typed query plans the device executes against
/// the local ledger.
///
/// Plans are *the only* output of [parseNlQuery]; the parser never
/// emits raw SQL or string templates. The executor switches on the
/// concrete subtype and uses a typed Drift query builder (or the
/// in-memory test executor in this directory) to produce a
/// [QueryResult].
///
/// Adding a new query category is a deliberate code change: add a
/// subtype here, a branch in the parser, and a branch in the
/// executor. The sealed `switch` makes a missed branch a compile
/// error — that is the point.
library;

import '../../contracts/contracts.dart' show DateRange;

sealed class FinanceQueryPlan {
  const FinanceQueryPlan();

  /// Stable wire string for telemetry. Mirrors the subtype name.
  String get kind;
}

/// "上月咖啡花了多少", "本月外卖支出".
final class SpendingByCategoryPlan extends FinanceQueryPlan {
  const SpendingByCategoryPlan({required this.range, this.categoryHints});

  final DateRange range;

  /// Canonical expense category slugs (for example
  /// `coffee`, `dining`, `subscriptions`). `null` means
  /// 'all categories' (the executor returns the full breakdown).
  final List<String>? categoryHints;

  @override
  String get kind => 'spending_by_category';
}

/// "近30天的交易", "最近一周的支出明细".
final class TransactionsFilterPlan extends FinanceQueryPlan {
  const TransactionsFilterPlan({
    required this.range,
    this.merchantSubstring,
    this.minAmountMinor,
    this.maxAmountMinor,
    this.currency,
  });

  final DateRange range;
  final String? merchantSubstring;
  final int? minAmountMinor;
  final int? maxAmountMinor;
  final String? currency;

  @override
  String get kind => 'transactions_filter';
}

/// "净资产趋势", "今年财富变化". Phase 3 leaves the executor branch
/// as a stub — the real implementation needs the dashboard's
/// net-worth time series, which is a separate Phase 3-D adapter.
final class NetWorthTrendPlan extends FinanceQueryPlan {
  const NetWorthTrendPlan({required this.range, this.granularity = 'month'});

  final DateRange range;

  /// 'day' | 'week' | 'month'. Free-form for now to avoid a third
  /// enum that crosses no module boundary.
  final String granularity;

  @override
  String get kind => 'net_worth_trend';
}

/// "我的订阅", "subscription list". Powered by the recurring detector.
final class SubscriptionListPlan extends FinanceQueryPlan {
  const SubscriptionListPlan({this.range});

  /// Optional window to restrict the lookback. `null` = the
  /// recurring detector's default (caller-provided transactions
  /// span).
  final DateRange? range;

  @override
  String get kind => 'subscription_list';
}

/// "本月退款匹配", "退款". Powered by the refund matcher.
final class RefundMatchingPlan extends FinanceQueryPlan {
  const RefundMatchingPlan({required this.range});

  final DateRange range;

  @override
  String get kind => 'refund_matching';
}
