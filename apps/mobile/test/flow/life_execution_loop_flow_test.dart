import 'package:flutter_riverpod/flutter_riverpod.dart'
    show AsyncValue, ProviderScope;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/features/finance/cashflow/domain/budget_signal.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/health/ui/health_today_providers.dart';

import 'support/app_harness.dart';
import 'support/page_objects.dart';

void main() {
  testWidgets(
    'Task: Act on Life signal user reviews evidence, creates an action, and closes the loop',
    (tester) async {
      var recovery = <String, Object?>{
        'score': 42,
        'verdict': 'strained',
        'inputs': const <String, Object?>{},
      };
      final data = await FlowDataHarness.create();
      addTearDown(data.dispose);
      await data.enableDomains(const <DomainScope>[
        DomainScope.health,
        DomainScope.execution,
      ]);

      await bootApp(
        tester,
        liveData: data,
        initialLocation: '/life',
        extraOverrides: <Override>[
          recoverySignalProvider.overrideWith((ref) async => recovery),
        ],
      );

      final life = LifePageObject(tester);
      life.expectSignal('Recovery needs attention');
      await life.openSignalAction(signalTitle: 'Recovery needs attention');
      life.expectEvidence('Recovery score: 42');
      await life.createAction('Protect recovery today');
      await life.openExecution();

      final execution = ExecutionTodayPageObject(tester);
      execution.expectAction('Protect recovery today');
      await execution.completeAction('Protect recovery today');

      await execution.openReview();
      final review = ExecutionReviewPageObject(tester);
      await review.expectCompletedAction('Protect recovery today');
      review.expectOutcome('Health: signal still detected');

      recovery = <String, Object?>{
        'score': 78,
        'verdict': 'balanced',
        'inputs': const <String, Object?>{},
      };
      final outcomeContext = tester.element(
        find.text('Health: signal still detected'),
      );
      ProviderScope.containerOf(outcomeContext)
          .invalidate(recoverySignalProvider);
      await tester.pumpAndSettle();
      review.expectOutcome('Health: signal no longer detected');
      await closeApp(tester);
    },
    tags: 'flow',
  );

  testWidgets(
    'Task: Improve budget posture user creates an action and sees a later observation',
    (tester) async {
      var budgetSignal = BudgetSignal.overBudget;
      final data = await FlowDataHarness.create();
      addTearDown(data.dispose);
      await data.enableDomains(const <DomainScope>[DomainScope.execution]);

      await bootApp(
        tester,
        liveData: data,
        initialLocation: '/life',
        extraOverrides: <Override>[
          monthlyBudgetSignalProvider.overrideWith((ref, periodMonth) {
            return AsyncValue.data(budgetSignal);
          }),
        ],
      );

      final life = LifePageObject(tester);
      life.expectSignal('Monthly budget exceeded');
      await life.openSignalAction(signalTitle: 'Monthly budget exceeded');
      life.expectEvidence('${_periodMonth(DateTime.now())} budget usage');
      await life.createAction("View this month's budget");
      await life.openExecution();

      final execution = ExecutionTodayPageObject(tester);
      execution.expectAction("View this month's budget");
      await execution.completeAction("View this month's budget");

      await execution.openReview();
      final review = ExecutionReviewPageObject(tester);
      await review.expectCompletedAction("View this month's budget");
      review.expectOutcome('Finance: signal still detected');

      budgetSignal = BudgetSignal.comfortable;
      final outcomeContext = tester.element(
        find.text('Finance: signal still detected'),
      );
      ProviderScope.containerOf(
        outcomeContext,
      ).invalidate(monthlyBudgetSignalProvider(_periodMonth(DateTime.now())));
      await tester.pumpAndSettle();
      review.expectOutcome('Finance: signal no longer detected');
      await closeApp(tester);
    },
    tags: 'flow',
  );
}

String _periodMonth(DateTime value) {
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}';
}
