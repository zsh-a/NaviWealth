/// Heuristic Natural-Language → [FinanceQueryPlan] parser.
///
/// Pattern-matching only: detects common Chinese + English query
/// shapes and returns a typed plan. Never emits raw SQL. Returns
/// `null` when the query doesn't match any pattern — the caller can
/// then escalate (Phase 5: device LLM; Phase 2-A: forward to cloud
/// chat with a 'no local match' hint).
///
/// Coverage is intentionally narrow:
///   * Time windows: 上月/本月/今年/去年, 近 N 天 / last N days,
///     this/last week|month|year.
///   * Categories: 咖啡 / 外卖 / 订阅 / 出行 / 日用 / 购物 / 工具
///     and English equivalents — drawn from the same alias space as
///     [classifyTransaction].
///   * Intents: 花了多少 / 支出 / 消费 (spending), 订阅 (subscription),
///     退款 (refund), 净资产 / 趋势 (net worth trend), 交易 / 明细
///     (generic filter).
library;

import '../../contracts/contracts.dart' show DateRange;
import 'finance_query_plan.dart';

/// Returns a typed plan, or `null` if the query is too open-ended for
/// the local rules to handle. [now] anchors relative time references;
/// tests pass a frozen value.
FinanceQueryPlan? parseNlQuery(String query, {required DateTime now}) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return null;

  final range = _extractDateRange(normalized, now);
  final categoryHints = _extractCategoryHints(normalized);

  // Highest-specificity intents go first so an ambiguous query like
  // '上月订阅花了多少' lands on SpendingByCategory rather than
  // SubscriptionList.
  if (_hasSpendingIntent(normalized) &&
      (categoryHints != null || range != null)) {
    return SpendingByCategoryPlan(
      range: range ?? _currentMonth(now),
      categoryHints: categoryHints,
    );
  }
  if (_hasSubscriptionIntent(normalized)) {
    return SubscriptionListPlan(range: range);
  }
  if (_hasRefundIntent(normalized)) {
    return RefundMatchingPlan(range: range ?? _last90Days(now));
  }
  if (_hasNetWorthTrendIntent(normalized)) {
    return NetWorthTrendPlan(range: range ?? _last12Months(now));
  }
  if (_hasTransactionsIntent(normalized) && range != null) {
    return TransactionsFilterPlan(range: range);
  }
  return null;
}

// ── intent detection ──────────────────────────────────────────────

bool _hasSpendingIntent(String q) =>
    q.contains('花了') ||
    q.contains('支出') ||
    q.contains('消费') ||
    q.contains('spent') ||
    q.contains('spending') ||
    q.contains('how much');

bool _hasSubscriptionIntent(String q) =>
    q.contains('订阅') || q.contains('subscription');

bool _hasRefundIntent(String q) => q.contains('退款') || q.contains('refund');

bool _hasNetWorthTrendIntent(String q) =>
    q.contains('净资产') ||
    q.contains('net worth') ||
    q.contains('财富') ||
    (q.contains('趋势') && (q.contains('资产') || q.contains('worth')));

bool _hasTransactionsIntent(String q) =>
    q.contains('交易') ||
    q.contains('明细') ||
    q.contains('账单') ||
    q.contains('transactions');

// ── category extraction ───────────────────────────────────────────

const Map<String, String> _categoryKeywords = <String, String>{
  '咖啡': 'coffee',
  'coffee': 'coffee',
  '外卖': 'food_delivery',
  'delivery': 'food_delivery',
  '订阅': 'subscription',
  'subscription': 'subscription',
  '日用': 'grocery',
  '生鲜': 'grocery',
  'grocery': 'grocery',
  '打车': 'transport',
  '出行': 'transport',
  'uber': 'transport',
  'lyft': 'transport',
  '购物': 'shopping',
  'shopping': 'shopping',
  '水电': 'utilities',
  'utilities': 'utilities',
};

List<String>? _extractCategoryHints(String q) {
  final hits = <String>{};
  for (final entry in _categoryKeywords.entries) {
    if (q.contains(entry.key)) hits.add(entry.value);
  }
  return hits.isEmpty ? null : hits.toList(growable: false);
}

// ── time-window extraction ────────────────────────────────────────

DateRange? _extractDateRange(String q, DateTime now) {
  if (q.contains('上月') || q.contains('上个月') || q.contains('last month')) {
    return _previousMonth(now);
  }
  if (q.contains('本月') ||
      q.contains('这个月') ||
      q.contains('当月') ||
      q.contains('this month')) {
    return _currentMonth(now);
  }
  if (q.contains('今年') || q.contains('this year')) {
    return _currentYear(now);
  }
  if (q.contains('去年') || q.contains('last year')) {
    return _previousYear(now);
  }
  if (q.contains('上周') || q.contains('last week')) {
    return _previousWeek(now);
  }
  if (q.contains('本周') || q.contains('这周') || q.contains('this week')) {
    return _currentWeek(now);
  }
  // 'last N days' / '近 N 天' / '过去 N 天'
  final m = RegExp(
    r'近\s*(\d+)\s*天|过去\s*(\d+)\s*天|last\s*(\d+)\s*days?',
  ).firstMatch(q);
  if (m != null) {
    final n = int.tryParse(m.group(1) ?? m.group(2) ?? m.group(3) ?? '0') ?? 0;
    if (n > 0) return _lastNDays(now, n);
  }
  return null;
}

DateRange _previousMonth(DateTime now) {
  final start = DateTime.utc(now.year, now.month - 1);
  final end = DateTime.utc(now.year, now.month);
  return _range(start, end);
}

DateRange _currentMonth(DateTime now) {
  final start = DateTime.utc(now.year, now.month);
  final end = DateTime.utc(now.year, now.month + 1);
  return _range(start, end);
}

DateRange _currentYear(DateTime now) =>
    _range(DateTime.utc(now.year), DateTime.utc(now.year + 1));

DateRange _previousYear(DateTime now) =>
    _range(DateTime.utc(now.year - 1), DateTime.utc(now.year));

DateRange _previousWeek(DateTime now) {
  // ISO week: Monday-start. Compute the start of the *current* week,
  // then subtract 7 days for last week's start.
  final dayOfWeek = now.toUtc().weekday; // 1=Mon..7=Sun
  final startOfThisWeek = DateTime.utc(
    now.year,
    now.month,
    now.day - (dayOfWeek - 1),
  );
  final start = startOfThisWeek.subtract(const Duration(days: 7));
  return _range(start, startOfThisWeek);
}

DateRange _currentWeek(DateTime now) {
  final dayOfWeek = now.toUtc().weekday;
  final start = DateTime.utc(now.year, now.month, now.day - (dayOfWeek - 1));
  final end = start.add(const Duration(days: 7));
  return _range(start, end);
}

DateRange _lastNDays(DateTime now, int n) {
  final endExclusive = DateTime.utc(now.year, now.month, now.day + 1);
  final start = endExclusive.subtract(Duration(days: n));
  return _range(start, endExclusive);
}

DateRange _last90Days(DateTime now) => _lastNDays(now, 90);

DateRange _last12Months(DateTime now) {
  final start = DateTime.utc(now.year - 1, now.month, 1);
  final end = DateTime.utc(now.year, now.month, 1);
  return _range(start, end);
}

DateRange _range(DateTime startInclusive, DateTime endExclusive) => DateRange(
  fromInclusive: startInclusive.toIso8601String(),
  toExclusive: endExclusive.toIso8601String(),
);
