import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/activity/data/activity_feed_query.dart';
import 'package:naviwealth/features/finance/cashflow/domain/cash_flow_aggregator.dart';
import 'package:naviwealth/features/finance/cashflow/ui/cashflow_page.dart';

void main() {
  test('monthly drill-down opens the matching Activity date range', () {
    final uri = Uri.parse(
      cashFlowActivityRoute(
        period: CashFlowPeriod.month,
        anchor: DateTime.utc(2026, 7, 12),
        kinds: const {ActivityKind.expense},
        accountIds: const {'expense:dining'},
      ),
    );

    expect(uri.path, '/activity');
    expect(uri.queryParameters['from'], '2026-07-01');
    expect(uri.queryParameters['to'], '2026-08-01');
    expect(uri.queryParameters['kinds'], 'expense');
    expect(uri.queryParameters['accounts'], 'expense:dining');
  });

  test('quarterly drill-down uses calendar-quarter boundaries', () {
    final uri = Uri.parse(
      cashFlowActivityRoute(
        period: CashFlowPeriod.quarter,
        anchor: DateTime.utc(2026, 7, 12),
      ),
    );

    expect(uri.queryParameters['from'], '2026-07-01');
    expect(uri.queryParameters['to'], '2026-10-01');
    expect(uri.queryParameters, isNot(contains('kinds')));
  });
}
