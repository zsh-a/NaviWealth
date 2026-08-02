import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_run_store.dart';
import 'package:naviwealth/core/ai/agents/providers.dart' as agent_providers;
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/theme/app_theme.dart';
import 'package:naviwealth/features/execution/agents/providers.dart'
    as execution_agent_providers;
import 'package:naviwealth/features/execution/agents/review_agent.dart';
import 'package:naviwealth/features/execution/data/execution_repository.dart';
import 'package:naviwealth/features/execution/data/providers.dart';
import 'package:naviwealth/features/execution/domain/execution_models.dart';
import 'package:naviwealth/features/execution/ui/execution_review_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../../core/persistence/test_database.dart';
import '../../finance/data/repositories/_stub_stamper.dart';

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

    expect(
      tester.getTopLeft(find.text('Needs attention')).dy,
      lessThan(tester.getTopLeft(find.text('This week')).dy),
    );
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

  testWidgets('review page stays focused on the current week', (tester) async {
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

    expect(find.text('Generate'), findsOneWidget);
    expect(find.text('Recent activity · 1'), findsOneWidget);
    expect(find.text('Recent execution progress'), findsNothing);
    expect(find.text('Old execution blocker'), findsNothing);
    expect(find.text('New progress'), findsNothing);

    await tester.tap(find.text('Recent activity · 1'));
    await tester.pumpAndSettle();

    expect(find.text('Recent execution progress'), findsOneWidget);
    expect(find.text('Old execution blocker'), findsNothing);
  });

  testWidgets('review creates only selected missing next actions', (
    tester,
  ) async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final repository = ExecutionRepository(
      db: db,
      outbox: InMemoryOutboxStore(),
    );
    final project = ExecutionProject(
      id: 'project-missing',
      title: 'Launch project',
      createdAt: DateTime.utc(2026, 7, 1),
      sync: _sync(DateTime.utc(2026, 7, 1)),
    );
    final commitment = ExecutionCommitment(
      id: 'commitment-missing',
      title: 'Weekly planning',
      createdAt: DateTime.utc(2026, 7, 1),
      sync: _sync(DateTime.utc(2026, 7, 1)),
    );
    await repository.upsertProject(project);
    await repository.upsertCommitment(commitment);
    final artifact = _artifactWithMissingNextActions(project.id, commitment.id);

    await tester.pumpWidget(
      _wrap(
        const ExecutionReviewPage(),
        overrides: [
          execution_agent_providers.latestExecutionReviewResultsProvider
              .overrideWith(
                (ref) async => agent_providers.AgentResultBundle(
                  artifacts: [artifact],
                  latestRuns: const <AgentRunRecord>[],
                ),
              ),
          executionRepositoryProvider.overrideWith((_) async => repository),
          executionOwnerUserIdProvider.overrideWith((_) async => 'user-1'),
          mutationStamperProvider.overrideWith(
            (_) async => makeStubStamper(userId: 'user-1'),
          ),
          executionRecentProgressProvider.overrideWith(
            (ref) => Stream.value(const <ExecutionProgressEntry>[]),
          ),
          executionClosedActionsProvider.overrideWith(
            (ref) => Stream.value(const <ExecutionAction>[]),
          ),
          executionReviewRelationsProvider.overrideWith(
            (ref) async => ExecutionReviewRelations(
              actions: const <String, ExecutionAction>{},
              projects: {project.id: project},
              commitments: {commitment.id: commitment},
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Review 2 missing next actions'));
    await tester.pumpAndSettle();

    expect(find.text('Launch project'), findsOneWidget);
    expect(find.text('Weekly planning'), findsOneWidget);
    expect(find.text('Create 2 next actions'), findsOneWidget);

    await tester.tap(find.text('Weekly planning'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create 1 next actions'));
    await tester.pumpAndSettle();

    final actions = await repository.listOpenActions(ownerUserId: 'user-1');
    expect(actions, hasLength(1));
    expect(actions.single.projectId, project.id);
    expect(actions.single.commitmentId, isNull);
    expect(actions.single.priority, ExecutionPriority.high);
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

AgentArtifact _artifactWithMissingNextActions(
  String projectId,
  String commitmentId,
) {
  return AgentArtifact(
    id: 'execution-review-batch',
    ownerUserId: 'user-1',
    agentId: kExecutionReviewAgentId,
    domain: 'execution',
    kind: AgentArtifactKind.review,
    severity: AgentArtifactSeverity.attention,
    title: 'Execution Review',
    summary: '2 plans need a next action',
    actions: [
      AgentAction(
        kind: 'proposal',
        label: 'Create next actions',
        payload: {
          'projects_without_next_action': [projectId],
          'commitments_without_next_action': [commitmentId],
        },
      ),
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
