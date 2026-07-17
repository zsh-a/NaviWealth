import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/features/health/ui/health_today_providers.dart';

import 'support/app_harness.dart';
import 'support/page_objects.dart';

void main() {
  testWidgets(
    'Task: Act on Life signal user reviews evidence, creates an action, and closes the loop',
    (tester) async {
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
          recoverySignalProvider.overrideWith(
            (ref) async => <String, Object?>{
              'score': 42,
              'verdict': 'strained',
              'inputs': const <String, Object?>{},
            },
          ),
        ],
      );

      final life = LifePageObject(tester);
      life.expectSignal('Recovery needs care');
      await life.openSignal('Recovery needs care');
      life.expectEvidence('Recovery score: 42');
      await life.createAction('Protect recovery today');
      await life.openExecution();

      final execution = ExecutionTodayPageObject(tester);
      execution.expectAction('Protect recovery today');
      await execution.completeAction('Protect recovery today');

      await AppShell(tester).openTab('Review');
      ExecutionReviewPageObject(
        tester,
      ).expectCompletedAction('Protect recovery today');
      await closeApp(tester);
    },
    tags: 'flow',
  );
}
