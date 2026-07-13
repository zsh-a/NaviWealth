import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_run_store.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/auth/domain_opt_in_store.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/design_system/theme/app_theme.dart';
import 'package:naviwealth/features/health/agents/morning_briefing_agent.dart';
import 'package:naviwealth/features/health/agents/providers.dart'
    as health_agent_providers;
import 'package:naviwealth/features/health/agents/recovery_alert_agent.dart';
import 'package:naviwealth/features/health/agents/weekly_summary_agent.dart';
import 'package:naviwealth/features/health/data/garmin/garmin_sync_controller.dart';
import 'package:naviwealth/features/health/data/providers.dart' as health_data;
import 'package:naviwealth/features/health/ui/health_today_page.dart';
import 'package:naviwealth/features/health/ui/health_today_providers.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../../core/persistence/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('today page renders health agent artifacts as result cards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = makeTestDatabase();
    addTearDown(db.close);
    await DomainOptInStore(
      db,
    ).write(DomainOptIns(const <DomainScope>{DomainScope.health}));

    await tester.pumpWidget(
      _wrap(
        const HealthTodayPage(),
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => db),
          currentUserIdProvider.overrideWithValue(() async => 'user-1'),
          health_data.garminSyncControllerProvider.overrideWithBuild(
            (_, _) => const GarminInitial(),
          ),
          healthTodayMetricGridProvider.overrideWith(
            (ref) async => HealthTodayMetricGridModel.empty(),
          ),
          recoverySignalProvider.overrideWith(
            (ref) async => <String, Object?>{'score': 74, 'verdict': 'steady'},
          ),
          recoverySparklineProvider.overrideWith(
            (ref) async => const <double>[],
          ),
          weeklySummaryProvider.overrideWith((ref) async => null),
          health_agent_providers.latestMorningBriefingProvider.overrideWith(
            (ref) async => null,
          ),
          health_agent_providers.latestMorningBriefingArtifactProvider
              .overrideWith(
                (ref) async => _artifact(
                  id: 'morning-1',
                  agentId: kMorningBriefingAgentId,
                  kind: AgentArtifactKind.briefing,
                  severity: AgentArtifactSeverity.info,
                  title: 'Morning Briefing',
                  summary: 'Keep the first block light after short sleep.',
                  insight: 'Sleep debt',
                ),
              ),
          health_agent_providers.latestRecoveryAlertArtifactProvider
              .overrideWith(
                (ref) async => _artifact(
                  id: 'recovery-1',
                  agentId: kRecoveryAlertAgentId,
                  kind: AgentArtifactKind.alert,
                  severity: AgentArtifactSeverity.warning,
                  title: 'Recovery Alert',
                  summary: 'HRV dropped while resting heart rate climbed.',
                  insight: 'Recovery risk',
                ),
              ),
          health_agent_providers.latestWeeklySummaryRunProvider.overrideWith(
            (ref) async => null,
          ),
          health_agent_providers.latestWeeklySummaryArtifactProvider
              .overrideWith(
                (ref) async => _artifact(
                  id: 'weekly-1',
                  agentId: kWeeklySummaryAgentId,
                  kind: AgentArtifactKind.review,
                  severity: AgentArtifactSeverity.attention,
                  title: 'Weekly Summary',
                  summary: 'Training was consistent but sleep lagged.',
                  insight: 'Weekly pattern',
                ),
              ),
        ],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Morning Briefing'), findsOneWidget);
    expect(
      find.text('Keep the first block light after short sleep.'),
      findsOneWidget,
    );
    expect(find.text('Sleep debt'), findsOneWidget);

    expect(find.text('Recovery Alert'), findsOneWidget);
    expect(
      find.text('HRV dropped while resting heart rate climbed.'),
      findsOneWidget,
    );
    expect(find.text('Recovery risk'), findsNothing);

    expect(find.text('Weekly Summary'), findsOneWidget);
    expect(
      find.text('Training was consistent but sleep lagged.'),
      findsOneWidget,
    );
    expect(find.text('Weekly pattern'), findsNothing);
    expect(find.text('Review'), findsNothing);
  });

  testWidgets('today page overlays newer recovery run on the older artifact', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = makeTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      _wrap(
        const HealthTodayPage(),
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => db),
          currentUserIdProvider.overrideWithValue(() async => 'user-1'),
          health_data.garminSyncControllerProvider.overrideWithBuild(
            (_, _) => const GarminInitial(),
          ),
          healthTodayMetricGridProvider.overrideWith(
            (ref) async => HealthTodayMetricGridModel.empty(),
          ),
          recoverySignalProvider.overrideWith(
            (ref) async => <String, Object?>{'score': 58, 'verdict': 'low'},
          ),
          recoverySparklineProvider.overrideWith(
            (ref) async => const <double>[],
          ),
          weeklySummaryProvider.overrideWith((ref) async => null),
          health_agent_providers.latestMorningBriefingProvider.overrideWith(
            (ref) async => null,
          ),
          health_agent_providers.latestMorningBriefingArtifactProvider
              .overrideWith((ref) async => null),
          health_agent_providers.latestRecoveryAlertArtifactProvider
              .overrideWith(
                (ref) async => _artifact(
                  id: 'recovery-1',
                  agentId: kRecoveryAlertAgentId,
                  kind: AgentArtifactKind.alert,
                  severity: AgentArtifactSeverity.warning,
                  title: 'Old Recovery Alert',
                  summary: 'This older alert should stay behind the run state.',
                  insight: 'Recovery risk',
                ),
              ),
          health_agent_providers.latestRecoveryAlertRunProvider.overrideWith(
            (ref) async => AgentRunRecord(
              id: 'run-1',
              ownerUserId: 'user-1',
              agentId: kRecoveryAlertAgentId,
              agentName: 'Recovery Alert',
              status: AgentRunLifecycleStatus.running,
              trigger: AgentRunTrigger.manual,
              startedAt: DateTime.utc(2026, 7, 6, 8),
              summary: 'Recovery check in progress.',
            ),
          ),
          health_agent_providers.latestWeeklySummaryRunProvider.overrideWith(
            (ref) async => null,
          ),
          health_agent_providers.latestWeeklySummaryArtifactProvider
              .overrideWith((ref) async => null),
        ],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Running'), findsNothing);
    expect(find.text('Recovery check in progress.'), findsOneWidget);
    expect(find.text('Old Recovery Alert'), findsOneWidget);
  });
}

Widget _wrap(Widget child, {required List<Override> overrides}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en', 'US'),
      home: FTheme(data: FThemes.slate.light.desktop, child: child),
    ),
  );
}

AgentArtifact _artifact({
  required String id,
  required String agentId,
  required AgentArtifactKind kind,
  required AgentArtifactSeverity severity,
  required String title,
  required String summary,
  required String insight,
}) {
  return AgentArtifact(
    id: id,
    ownerUserId: 'user-1',
    agentId: agentId,
    domain: 'health',
    kind: kind,
    severity: severity,
    title: title,
    summary: summary,
    insights: <AgentInsight>[
      AgentInsight(title: insight, body: '$insight needs attention.'),
    ],
    evidence: const <AgentEvidenceRef>[
      AgentEvidenceRef(type: 'health_metric', id: 'metric-1'),
    ],
    createdAt: DateTime.utc(2026, 7, 5, 8),
  );
}
