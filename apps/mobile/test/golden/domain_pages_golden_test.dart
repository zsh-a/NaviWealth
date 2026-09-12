import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/auth/domain_opt_in_store.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/features/execution/data/providers.dart';
import 'package:naviwealth/features/execution/domain/execution_models.dart';
import 'package:naviwealth/features/execution/ui/execution_today_page.dart';
import 'package:naviwealth/features/health/agents/providers.dart'
    as health_agent_providers;
import 'package:naviwealth/features/health/data/garmin/garmin_sync_controller.dart';
import 'package:naviwealth/features/health/data/health_metric_repository.dart';
import 'package:naviwealth/features/health/data/health_metric_write_service.dart';
import 'package:naviwealth/features/health/data/providers.dart' as health_data;
import 'package:naviwealth/features/health/domain/health_metric_kind.dart';
import 'package:naviwealth/features/health/ui/health_today_page.dart';
import 'package:naviwealth/features/health/ui/health_today_providers.dart';
import 'package:naviwealth/features/knowledge/data/providers.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';
import 'package:naviwealth/features/knowledge/ui/knowledge_inbox_page.dart';

import '../core/persistence/test_database.dart';
import '../features/finance/data/repositories/_stub_stamper.dart';
import '_golden_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  runAllVariants('health_manual_today_page', (tester, variant) async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    await DomainOptInStore(db).write(DomainOptIns(const {DomainScope.health}));
    final repository = HealthMetricRepository(
      db: db,
      outbox: InMemoryOutboxStore(),
    );
    final writer = HealthMetricWriteService(
      repository: repository,
      stamper: makeStubStamper(userId: 'golden-user'),
    );
    final at = DateTime.now().toUtc().subtract(const Duration(minutes: 20));
    await writer.recordBodyMeasurement(
      kind: HealthMetricKind.weight,
      value: 72.5,
      capturedAt: at,
    );
    await writer.recordBodyMeasurement(
      kind: HealthMetricKind.bodyFat,
      value: 18.5,
      capturedAt: at,
    );
    await pumpAndSnapshotMobile(
      tester,
      name: 'health_manual_today_page',
      routePath: '/health',
      variant: variant,
      child: const HealthTodayPage(),
      overrides: [
        appDatabaseProvider.overrideWith((_) async => db),
        currentUserIdProvider.overrideWithValue(() async => 'golden-user'),
        health_data.healthMetricRepositoryProvider.overrideWith(
          (_) async => repository,
        ),
        health_data.garminSyncControllerProvider.overrideWithBuild(
          (_, _) => const GarminInitial(),
        ),
        health_data.healthSyncStatusProvider.overrideWithValue(null),
        health_data.healthPlatformStatusProvider.overrideWith(
          (_) async => const health_data.HealthPlatformStatus(
            available: false,
            permissionsGranted: false,
          ),
        ),
      ],
    );
    expect(find.text('72.5'), findsOneWidget);
    expect(find.text('18.5'), findsOneWidget);
    expect(find.text('Connect your health data'), findsNothing);
  });

  runAllVariants('health_today_page', (tester, variant) async {
    final db = makeTestDatabase();
    addTearDown(db.close);

    await pumpAndSnapshotMobile(
      tester,
      name: 'health_today_page',
      routePath: '/health',
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
      routePath: '/knowledge',
      variant: variant,
      child: const KnowledgeInboxPage(),
      overrides: [
        knowledgeDueReviewsProvider.overrideWith(
          (_) => Stream.value(const <KnowledgeDecision>[]),
        ),
        knowledgeNotesProvider.overrideWith(
          (_) => Stream<List<KnowledgeNote>>.value(const <KnowledgeNote>[]),
        ),
      ],
    );
    expect(find.text('Inbox'), findsOneWidget);
  });

  runAllVariants('execution_today_page', (tester, variant) async {
    await pumpAndSnapshotMobile(
      tester,
      name: 'execution_today_page',
      routePath: '/execution',
      variant: variant,
      child: const ExecutionTodayPage(),
      overrides: _emptyExecutionOverrides(),
    );
    expect(find.text('Today’s actions'), findsOneWidget);
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
