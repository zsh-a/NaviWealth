import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/features/execution/data/providers.dart';
import 'package:naviwealth/features/execution/domain/execution_models.dart';
import 'package:naviwealth/features/execution/ui/execution_today_page.dart';
import 'package:naviwealth/features/health/agents/providers.dart'
    as health_agent_providers;
import 'package:naviwealth/features/health/data/garmin/garmin_sync_controller.dart';
import 'package:naviwealth/features/health/data/providers.dart' as health_data;
import 'package:naviwealth/features/health/ui/health_today_page.dart';
import 'package:naviwealth/features/health/ui/health_today_providers.dart';
import 'package:naviwealth/features/knowledge/data/providers.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';
import 'package:naviwealth/features/knowledge/ui/knowledge_inbox_page.dart';

import '../core/persistence/test_database.dart';
import '_golden_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  runAllVariants('health_today_page', (tester, variant) async {
    final db = makeTestDatabase();
    addTearDown(db.close);

    await pumpAndSnapshotMobile(
      tester,
      name: 'health_today_page',
      variant: variant,
      child: const HealthTodayPage(),
      overrides: [
        appDatabaseProvider.overrideWith((_) async => db),
        currentUserIdProvider.overrideWithValue(() async => 'golden-user'),
        health_data.garminSyncControllerProvider.overrideWithBuild(
          (_, _) => const GarminInitial(),
        ),
        healthTodayMetricGridProvider.overrideWith(
          (_) async => HealthTodayMetricGridModel.empty(),
        ),
        recoverySignalProvider.overrideWith(
          (_) async => <String, Object?>{'score': 74, 'verdict': 'steady'},
        ),
        recoverySparklineProvider.overrideWith((_) async => const <double>[]),
        weeklySummaryProvider.overrideWith((_) async => null),
        health_agent_providers.latestRecoveryAlertRunProvider.overrideWith(
          (_) async => null,
        ),
        health_agent_providers.latestRecoveryAlertArtifactProvider.overrideWith(
          (_) async => null,
        ),
        health_agent_providers.latestWeeklySummaryRunProvider.overrideWith(
          (_) async => null,
        ),
        health_agent_providers.latestWeeklySummaryArtifactProvider.overrideWith(
          (_) async => null,
        ),
      ],
    );
  });

  runAllVariants('knowledge_inbox_page', (tester, variant) async {
    await pumpAndSnapshotMobile(
      tester,
      name: 'knowledge_inbox_page',
      variant: variant,
      child: const KnowledgeInboxPage(),
      overrides: [
        knowledgeInboxNotesProvider.overrideWith(
          (_) => Stream<List<KnowledgeNote>>.value(const <KnowledgeNote>[]),
        ),
      ],
    );
  });

  runAllVariants('execution_today_page', (tester, variant) async {
    await pumpAndSnapshotMobile(
      tester,
      name: 'execution_today_page',
      variant: variant,
      child: const ExecutionTodayPage(),
      overrides: _emptyExecutionOverrides(),
    );
  });
}

List<Override> _emptyExecutionOverrides() => [
  executionTodayActionsProvider.overrideWith(
    (_) => Stream.value(const <ExecutionAction>[]),
  ),
  executionOpenActionsProvider.overrideWith(
    (_) => Stream.value(const <ExecutionAction>[]),
  ),
  executionPlansProvider.overrideWith(
    (_) => Stream.value(const <ExecutionPlan>[]),
  ),
  executionClosedPlansProvider.overrideWith(
    (_) => Stream.value(const <ExecutionPlan>[]),
  ),
  executionRecentProgressProvider.overrideWith(
    (_) => Stream.value(const <ExecutionProgressEntry>[]),
  ),
  executionActionRelationsProvider.overrideWith(
    (_) async => const ExecutionRelations(
      actions: <String, ExecutionAction>{},
      plans: <String, ExecutionPlan>{},
    ),
  ),
];
