import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_run_store.dart';
import 'package:naviwealth/core/ai/agents/providers.dart' as agent_providers;
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/theme/app_theme.dart';
import 'package:naviwealth/features/execution/agents/providers.dart'
    as execution_agent_providers;
import 'package:naviwealth/features/execution/agents/review_agent.dart';
import 'package:naviwealth/features/execution/data/providers.dart';
import 'package:naviwealth/features/execution/domain/execution_models.dart';
import 'package:naviwealth/features/execution/ui/execution_review_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  testWidgets('review page renders latest agent artifact', (tester) async {
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
    expect(find.text('Today focus'), findsNothing);
    expect(find.textContaining('07-05'), findsOneWidget);
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
    // Result-first: failed run overlays the prior artifact with error text.
    expect(find.text('Runtime unavailable'), findsOneWidget);
    expect(find.text('3 actions need attention'), findsOneWidget);
    expect(find.text('Today focus'), findsNothing);
  });

  testWidgets('review page filters history and exposes an empty-agent CTA', (
    tester,
  ) async {
    final now = DateTime.now();
    final recent = ExecutionProgressEntry(
      id: 'recent',
      kind: ExecutionProgressKind.checkin,
      note: 'Recent execution progress',
      createdAt: now.subtract(const Duration(days: 2)),
      sync: _sync(now),
    );
    final old = ExecutionProgressEntry(
      id: 'old',
      kind: ExecutionProgressKind.blocker,
      note: 'Old execution blocker',
      createdAt: now.subtract(const Duration(days: 60)),
      sync: _sync(now),
    );
    await tester.pumpWidget(
      _wrap(
        const ExecutionReviewPage(),
        overrides: [
          execution_agent_providers.latestExecutionReviewResultsProvider
              .overrideWith(
                (ref) async => agent_providers.AgentResultBundle.empty,
              ),
          executionRecentProgressProvider.overrideWith(
            (ref) => Stream.value([recent, old]),
          ),
          executionClosedActionsProvider.overrideWith(
            (ref) => Stream.value(const <ExecutionAction>[]),
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
    await tester.pumpAndSettle();

    expect(find.text('Generate review'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('All')).dy,
      lessThan(tester.getTopLeft(find.text('Generate review')).dy),
    );
    expect(find.text('Recent execution progress'), findsOneWidget);
    expect(find.text('Old execution blocker'), findsNothing);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();

    expect(find.text('Old execution blocker'), findsOneWidget);
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

SyncMeta _sync(DateTime now) {
  return SyncMeta(
    ownerUserId: 'user-1',
    updatedAt: now,
    updatedByDevice: 'device-1',
    hlc: Hlc(
      wallMillis: now.millisecondsSinceEpoch,
      counter: 0,
      nodeId: 'device-1',
    ),
  );
}
