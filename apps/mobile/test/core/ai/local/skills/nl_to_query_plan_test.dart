import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/local/skills/skills.dart';

void main() {
  // Frozen "now" for deterministic relative-time tests. 2026-05-10
  // is a Sunday in UTC; weekday=7.
  final now = DateTime.utc(2026, 5, 10, 12);

  group('parseNlQuery — spending', () {
    test('上月咖啡 → spending plan with last-month range + coffee hint', () {
      final plan = parseNlQuery('上月咖啡花了多少？', now: now);
      expect(plan, isA<SpendingByCategoryPlan>());
      final p = plan! as SpendingByCategoryPlan;
      expect(p.categoryHints, <String>['coffee']);
      expect(p.range.fromInclusive, '2026-04-01T00:00:00.000Z');
      expect(p.range.toExclusive, '2026-05-01T00:00:00.000Z');
    });

    test('this-month spending in English', () {
      final plan = parseNlQuery(
        'how much did I spend on coffee this month',
        now: now,
      );
      expect(plan, isA<SpendingByCategoryPlan>());
      final p = plan! as SpendingByCategoryPlan;
      expect(p.categoryHints, <String>['coffee']);
      expect(p.range.fromInclusive, '2026-05-01T00:00:00.000Z');
    });

    test('spending without explicit category falls back to all categories', () {
      final plan = parseNlQuery('上月支出', now: now);
      expect(plan, isA<SpendingByCategoryPlan>());
      final p = plan! as SpendingByCategoryPlan;
      expect(p.categoryHints, isNull);
    });

    test('multiple categories detected', () {
      final plan = parseNlQuery('本月咖啡和外卖花了多少', now: now);
      expect(plan, isA<SpendingByCategoryPlan>());
      final p = plan! as SpendingByCategoryPlan;
      expect(p.categoryHints, containsAll(<String>['coffee', 'food_delivery']));
    });
  });

  group('parseNlQuery — subscriptions / refunds / net worth', () {
    test('我的订阅 → SubscriptionListPlan', () {
      final plan = parseNlQuery('我的订阅都有哪些', now: now);
      expect(plan, isA<SubscriptionListPlan>());
    });

    test('subscription list with date window', () {
      final plan = parseNlQuery('近30天的订阅', now: now);
      expect(plan, isA<SubscriptionListPlan>());
      final p = plan! as SubscriptionListPlan;
      expect(p.range, isNotNull);
    });

    test('退款匹配 → RefundMatchingPlan with default 90-day window', () {
      final plan = parseNlQuery('帮我看下退款', now: now);
      expect(plan, isA<RefundMatchingPlan>());
    });

    test('净资产趋势 → NetWorthTrendPlan with default 12-month window', () {
      final plan = parseNlQuery('净资产趋势是怎样的', now: now);
      expect(plan, isA<NetWorthTrendPlan>());
      final p = plan! as NetWorthTrendPlan;
      expect(p.range.fromInclusive, '2025-05-01T00:00:00.000Z');
    });
  });

  group('parseNlQuery — transactions filter', () {
    test('近30天的交易 → TransactionsFilterPlan with last-30-days range', () {
      final plan = parseNlQuery('近30天的交易明细', now: now);
      expect(plan, isA<TransactionsFilterPlan>());
      final p = plan! as TransactionsFilterPlan;
      expect(p.range.toExclusive, '2026-05-11T00:00:00.000Z');
      expect(
        DateTime.parse(p.range.fromInclusive),
        DateTime.utc(2026, 4, 11),
      );
    });

    test('交易 without a window returns null (would otherwise be unbounded)', () {
      final plan = parseNlQuery('我的所有交易', now: now);
      expect(plan, isNull);
    });
  });

  group('parseNlQuery — date windows', () {
    test('上周 → previous ISO week', () {
      final plan = parseNlQuery('上周咖啡花了多少', now: now);
      expect(plan, isA<SpendingByCategoryPlan>());
      final p = plan! as SpendingByCategoryPlan;
      // 2026-05-10 is a Sunday (weekday=7); previous week starts
      // 2026-04-27 (Mon) and ends 2026-05-04 exclusive.
      expect(p.range.fromInclusive, '2026-04-27T00:00:00.000Z');
      expect(p.range.toExclusive, '2026-05-04T00:00:00.000Z');
    });

    test('"过去 14 天" parses N-day window', () {
      final plan = parseNlQuery('过去 14 天的交易', now: now);
      expect(plan, isA<TransactionsFilterPlan>());
      final p = plan! as TransactionsFilterPlan;
      expect(
        DateTime.parse(p.range.fromInclusive),
        DateTime.utc(2026, 4, 27),
      );
    });

    test('today / tomorrow / unsupported windows fall through', () {
      // No supported time window → plan is null because the
      // TransactionsFilter intent demands a range.
      final plan = parseNlQuery('今天的交易', now: now);
      expect(plan, isNull);
    });
  });

  group('parseNlQuery — empty / unknown', () {
    test('empty string → null', () {
      expect(parseNlQuery('', now: now), isNull);
      expect(parseNlQuery('   ', now: now), isNull);
    });

    test('open-ended question with no recognised pattern → null', () {
      final plan = parseNlQuery('帮我做一个理财计划', now: now);
      expect(plan, isNull);
    });
  });
}
