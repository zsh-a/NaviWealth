import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/application/planning_hub_status.dart';
import 'package:naviwealth/features/finance/cashflow/domain/budget_signal.dart';
import 'package:naviwealth/features/finance/home/ai_tools/get_finance_brief_tool.dart';
import 'package:naviwealth/features/finance/inbox/domain/financial_inbox.dart';

void main() {
  test('brief closes high-frequency planning and inbox signals', () {
    final now = DateTime.utc(2026, 7, 31);
    final payload = buildFinanceBriefPayload(
      planning: PlanningHubStatus(
        runway: PlanningRunwayStatus.watch,
        pendingLifeEventReviews: 2,
        rebalance: PlanningRebalanceStatus.attention,
        rebalanceDriftPct: 0.08,
        budgetCount: 4,
        budgetSignal: BudgetSignal.strained,
        budgetProgress: 0.82,
        dcaPlanCount: 3,
        dcaNextDueAt: now,
        dcaDue: true,
        wheelCycleCount: 2,
        wheelOpenPositionCount: 1,
        isLoading: false,
        hasError: false,
      ),
      inbox: [
        FinancialInboxItem(
          id: 'signal-1',
          sourceKey: 'runway',
          kind: FinancialInboxKind.runwayRisk,
          priority: FinancialInboxPriority.important,
          count: 2,
          route: '/finance/plan/runway',
          evidence: const {'months': 2},
          firstDetectedAt: now,
          lastDetectedAt: now,
        ),
      ],
    );

    expect(payload['status'], 'complete');
    expect(payload['runway'], 'watch');
    expect((payload['dca'] as Map)['due'], isTrue);
    expect((payload['wheel'] as Map)['open_position_count'], 1);
    expect((payload['inbox'] as Map)['important_count'], 2);
    expect(((payload['inbox'] as Map)['kinds'] as Map)['runwayRisk'], 2);
  });

  test('brief identifies partial source state', () {
    final payload = buildFinanceBriefPayload(
      planning: const PlanningHubStatus.loading(),
      inbox: const [],
      inboxError: 'offline',
    );

    expect(payload['status'], 'partial');
    expect(payload['planning_loading'], isTrue);
    expect(payload['inbox_error'], 'offline');
  });
}
