import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_run_store.dart';
import 'package:naviwealth/core/ai/agents/providers.dart' as agent_providers;
import 'package:naviwealth/core/ai/agents/ui/agent_result_card.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/design_system/theme/app_theme.dart';
import 'package:naviwealth/features/knowledge/agents/providers.dart'
    as knowledge_agent_providers;
import 'package:naviwealth/features/knowledge/agents/review_agent.dart';
import 'package:naviwealth/features/knowledge/data/inbox_triage_repository.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_repository.dart';
import 'package:naviwealth/features/knowledge/data/providers.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';
import 'package:naviwealth/features/knowledge/ui/knowledge_review_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  KnowledgeRoutine routine({
    required DateTime nextDueAt,
    DateTime? lastDoneAt,
    int intervalDays = 7,
    RoutineStatus status = RoutineStatus.active,
  }) {
    final created = DateTime.utc(2026, 1, 1);
    return KnowledgeRoutine(
      id: 'routine',
      statement: '每周对账',
      intervalDays: intervalDays,
      nextDueAt: nextDueAt,
      lastDoneAt: lastDoneAt,
      scope: '*',
      status: status,
      createdAt: created,
      sync: SyncMeta(
        ownerUserId: 'u-test',
        updatedAt: created,
        updatedByDevice: 'dev-test',
        hlc: Hlc.zero('dev-test'),
      ),
    );
  }

  group('shouldShowRoutineInReview', () {
    test('shows active routines due within the lookahead window', () {
      final now = DateTime.utc(2026, 5, 30, 10);

      expect(
        shouldShowRoutineInReview(
          routine(nextDueAt: DateTime.utc(2026, 6, 2)),
          now,
        ),
        isTrue,
      );
    });

    test(
      'hides routines completed today even if the next run is this week',
      () {
        final now = DateTime.utc(2026, 5, 30, 10);

        expect(
          shouldShowRoutineInReview(
            routine(
              nextDueAt: DateTime.utc(2026, 6, 6, 10),
              lastDoneAt: DateTime.utc(2026, 5, 30, 9),
            ),
            now,
          ),
          isFalse,
        );
      },
    );

    test('hides inactive or outside-window routines', () {
      final now = DateTime.utc(2026, 5, 30, 10);

      expect(
        shouldShowRoutineInReview(
          routine(
            nextDueAt: DateTime.utc(2026, 6, 1),
            status: RoutineStatus.paused,
          ),
          now,
        ),
        isFalse,
      );
      expect(
        shouldShowRoutineInReview(
          routine(nextDueAt: DateTime.utc(2026, 6, 8)),
          now,
        ),
        isFalse,
      );
    });
  });

  testWidgets('review page renders latest agent artifact cards first', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      _wrap(
        const KnowledgeReviewPage(),
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentUserIdProvider.overrideWithValue(() async => 'user-1'),
          knowledge_agent_providers.latestKnowledgeReviewResultsProvider
              .overrideWith(
                (ref) async => agent_providers.AgentResultBundle(
                  artifacts: <AgentArtifact>[
                    _artifact(),
                    _artifact(
                      id: 'knowledge-routine-1',
                      agentId: 'knowledge_routine_due',
                      title: 'Routine Due',
                      summary: 'A weekly review routine is due.',
                      createdAt: DateTime.utc(2026, 7, 4, 9),
                    ),
                  ],
                  latestRuns: const <AgentRunRecord>[],
                ),
              ),
          knowledgeRepositoryProvider.overrideWith(
            (ref) async => _FakeKnowledgeRepository(),
          ),
          inboxTriageRepositoryProvider.overrideWith(
            (ref) async => _FakeInboxTriageRepository(),
          ),
        ],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Knowledge Review'), findsOneWidget);
    expect(find.text('Review due decisions and assumptions.'), findsOneWidget);
    expect(find.text('Routine Due'), findsNothing);
    expect(find.text('A weekly review routine is due.'), findsNothing);
    expect(find.byType(AgentResultCard), findsOneWidget);
    expect(find.byType(AgentCompactResultRow), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('agent-result-stack')),
      findsOneWidget,
    );
    expect(find.text('Decisions due'), findsNothing);
    expect(
      tester.widget<AgentResultCard>(find.byType(AgentResultCard)).layout,
      AgentResultCardLayout.summary,
    );
  });

  testWidgets('review page keeps older artifact while newer run overlays', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      _wrap(
        const KnowledgeReviewPage(),
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentUserIdProvider.overrideWithValue(() async => 'user-1'),
          knowledge_agent_providers.latestKnowledgeReviewResultsProvider
              .overrideWith(
                (ref) async => agent_providers.AgentResultBundle(
                  artifacts: <AgentArtifact>[
                    _artifact(
                      title: 'Old Knowledge Review',
                      createdAt: DateTime.utc(2026, 7, 5, 9),
                    ),
                  ],
                  latestRuns: [
                    AgentRunRecord(
                      id: 'run-1',
                      ownerUserId: 'user-1',
                      agentId: kKnowledgeReviewAgentId,
                      agentName: 'Knowledge Review',
                      status: AgentRunLifecycleStatus.running,
                      trigger: AgentRunTrigger.manual,
                      startedAt: DateTime.utc(2026, 7, 6, 9),
                      summary: 'Review in progress.',
                    ),
                  ],
                ),
              ),
          knowledgeRepositoryProvider.overrideWith(
            (ref) async => _FakeKnowledgeRepository(),
          ),
          inboxTriageRepositoryProvider.overrideWith(
            (ref) async => _FakeInboxTriageRepository(),
          ),
        ],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Result-first: previous artifact stays; run is a banner overlay.
    expect(find.text('Old Knowledge Review'), findsOneWidget);
    expect(find.text('Review in progress.'), findsOneWidget);
    expect(find.byType(AgentRunStatusCard), findsNothing);
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
  String id = 'knowledge-review-1',
  String agentId = kKnowledgeReviewAgentId,
  String title = 'Knowledge Review',
  String summary = 'Review due decisions and assumptions.',
  DateTime? createdAt,
}) {
  return AgentArtifact(
    id: id,
    ownerUserId: 'user-1',
    agentId: agentId,
    domain: 'knowledge',
    kind: AgentArtifactKind.review,
    severity: AgentArtifactSeverity.attention,
    title: title,
    summary: summary,
    insights: const <AgentInsight>[
      AgentInsight(title: 'Decisions due', body: 'One decision is due.'),
    ],
    evidence: const <AgentEvidenceRef>[
      AgentEvidenceRef(type: 'knowledge_decision', id: 'decision-1'),
    ],
    createdAt: createdAt ?? DateTime.utc(2026, 7, 5, 9),
  );
}

class _FakeKnowledgeRepository implements KnowledgeRepository {
  @override
  Stream<List<KnowledgeRoutine>> watchRoutines({required String ownerUserId}) =>
      Stream<List<KnowledgeRoutine>>.value(const <KnowledgeRoutine>[]);

  @override
  Stream<List<KnowledgeDecision>> watchDecisions({
    required String ownerUserId,
    int? limit,
  }) => Stream<List<KnowledgeDecision>>.value(const <KnowledgeDecision>[]);

  @override
  Stream<List<KnowledgeAssumption>> watchAssumptions({
    required String ownerUserId,
  }) => Stream<List<KnowledgeAssumption>>.value(const <KnowledgeAssumption>[]);

  @override
  Future<List<KnowledgeRoutine>> listDueRoutines({
    required String ownerUserId,
    required DateTime asOf,
    DateTime? excludeDoneSince,
    int limit = 50,
  }) async => const <KnowledgeRoutine>[];

  @override
  Future<List<KnowledgeDecision>> listDueReviews({
    required String ownerUserId,
    required DateTime asOf,
    int limit = 100,
  }) async => const <KnowledgeDecision>[];

  @override
  Future<List<KnowledgeAssumption>> listOpenAssumptions({
    required String ownerUserId,
    double? confidenceMax,
  }) async => const <KnowledgeAssumption>[];

  @override
  Future<KnowledgeNote?> findNote({
    required String ownerUserId,
    required String id,
  }) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

class _FakeInboxTriageRepository implements InboxTriageRepository {
  @override
  Future<List<InboxTriageRecord>> listPending({
    required String ownerUserId,
    int limit = 20,
  }) async => const <InboxTriageRecord>[];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}
