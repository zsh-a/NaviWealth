import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_run_store.dart';
import 'package:naviwealth/core/ai/agents/providers.dart' as agent_providers;
import 'package:naviwealth/design_system/theme/app_theme.dart';
import 'package:naviwealth/features/execution/agents/providers.dart'
    as execution_agent_providers;
import 'package:naviwealth/features/execution/agents/review_agent.dart';
import 'package:naviwealth/features/execution/data/providers.dart';
import 'package:naviwealth/features/execution/domain/execution_models.dart';
import 'package:naviwealth/features/execution/ui/execution_review_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  testWidgets('review page renders latest agent artifact card first', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const ExecutionReviewPage(),
        overrides: [
          execution_agent_providers.latestExecutionReviewResultsProvider
              .overrideWith(
                (ref) async => agent_providers.AgentResultBundle(
                  artifacts: [_artifact()],
                  latestRuns: const <AgentRunRecord>[],
                ),
              ),
          executionRecentProgressProvider.overrideWith(
            (ref) => Stream<List<ExecutionProgressEntry>>.value(
              const <ExecutionProgressEntry>[],
            ),
          ),
          executionClosedActionsProvider.overrideWith(
            (ref) =>
                Stream<List<ExecutionAction>>.value(const <ExecutionAction>[]),
          ),
          executionReviewRelationsProvider.overrideWith(
            (ref) async => const ExecutionReviewRelations(
              actions: <String, ExecutionAction>{},
              projects: <String, ExecutionProject>{},
              commitments: <String, ExecutionCommitment>{},
            ),
          ),
        ],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Execution Review'), findsWidgets);
    expect(find.text('3 actions need attention'), findsOneWidget);
    expect(find.text('Today focus'), findsOneWidget);
    expect(find.textContaining('07-05'), findsOneWidget);
    expect(find.text('Review'), findsWidgets);
  });

  testWidgets('review page renders newer failed run before older artifact', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const ExecutionReviewPage(),
        overrides: [
          execution_agent_providers.latestExecutionReviewResultsProvider
              .overrideWith(
                (ref) async => agent_providers.AgentResultBundle(
                  artifacts: [_artifact()],
                  latestRuns: [
                    AgentRunRecord(
                      id: 'run-1',
                      ownerUserId: 'user-1',
                      agentId: kExecutionReviewAgentId,
                      agentName: 'Execution Review',
                      status: AgentRunLifecycleStatus.failed,
                      trigger: AgentRunTrigger.manual,
                      startedAt: DateTime.utc(2026, 7, 6, 8),
                      finishedAt: DateTime.utc(2026, 7, 6, 8, 1),
                      error: 'Runtime unavailable',
                    ),
                  ],
                ),
              ),
          executionRecentProgressProvider.overrideWith(
            (ref) => Stream<List<ExecutionProgressEntry>>.value(
              const <ExecutionProgressEntry>[],
            ),
          ),
          executionClosedActionsProvider.overrideWith(
            (ref) =>
                Stream<List<ExecutionAction>>.value(const <ExecutionAction>[]),
          ),
          executionReviewRelationsProvider.overrideWith(
            (ref) async => const ExecutionReviewRelations(
              actions: <String, ExecutionAction>{},
              projects: <String, ExecutionProject>{},
              commitments: <String, ExecutionCommitment>{},
            ),
          ),
        ],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Execution Review'), findsWidgets);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('Runtime unavailable'), findsOneWidget);
    expect(find.text('Today focus'), findsNothing);
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

AgentArtifact _artifact() {
  return AgentArtifact(
    id: 'execution-review-1',
    ownerUserId: 'user-1',
    agentId: kExecutionReviewAgentId,
    domain: 'execution',
    kind: AgentArtifactKind.review,
    severity: AgentArtifactSeverity.attention,
    title: 'Execution Review',
    summary: '3 actions need attention',
    insights: const <AgentInsight>[
      AgentInsight(title: 'Today focus', body: 'Start with the blocked item.'),
    ],
    evidence: const <AgentEvidenceRef>[
      AgentEvidenceRef(type: 'execution_action', id: 'action-1'),
    ],
    createdAt: DateTime.utc(2026, 7, 5, 8),
  );
}
