import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_finding_store.dart';
import 'package:naviwealth/core/ai/agents/agent_run_store.dart';
import 'package:naviwealth/core/ai/agents/providers.dart' as agent_providers;
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/design_system/theme/app_theme.dart';
import 'package:naviwealth/features/knowledge/data/inbox_triage_repository.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_repository.dart';
import 'package:naviwealth/features/knowledge/data/providers.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';
import 'package:naviwealth/features/knowledge/ui/knowledge_review_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('review page shows one calm domain queue when all clear', (
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

    expect(find.text('All clear'), findsOneWidget);
    expect(find.text('Browse library'), findsOneWidget);
    expect(find.textContaining('Agent'), findsNothing);
  });

  testWidgets('review page shows findings without a duplicate agent card', (
    tester,
  ) async {
    final at = DateTime.utc(2026, 6, 1, 9);
    final snapshot = KnowledgeReviewSnapshot(
      ownerUserId: 'user-1',
      dueDecisions: const <KnowledgeDecision>[],
      pendingSuggestions: const <InboxTriageRecord>[],
      suggestionNotes: const <String, KnowledgeNote?>{},
      agentResults: agent_providers.AgentResultBundle(
        artifacts: [
          AgentArtifact(
            id: 'artifact-1',
            ownerUserId: 'user-1',
            agentId: 'knowledge-review',
            domain: 'knowledge',
            kind: AgentArtifactKind.review,
            severity: AgentArtifactSeverity.warning,
            title: 'Agent conflict signal',
            summary: 'A review requires attention.',
            createdAt: at,
          ),
        ],
        latestRuns: const <AgentRunRecord>[],
      ),
      findings: [
        StoredAgentFinding(
          id: 'finding-1',
          agentId: 'knowledge-contradiction',
          domain: 'knowledge',
          kind: 'contradiction',
          severity: AgentArtifactSeverity.warning,
          confidence: 0.92,
          payload: const <String, Object?>{
            'subject_kind': 'concept',
            'subject_id': 'concept-1',
            'subject_label': 'Conflicting concept',
            'detail': 'Evidence changed',
          },
          firstSeenAt: at,
          lastSeenAt: at,
        ),
      ],
    );

    await tester.pumpWidget(
      _wrap(
        const KnowledgeReviewPage(),
        overrides: [
          knowledgeReviewSnapshotProvider.overrideWith((ref) async => snapshot),
        ],
      ),
    );
    await tester.pump();

    expect(find.text('Agent conflict signal'), findsNothing);
    expect(find.text('Conflicting concept'), findsOneWidget);
    expect(find.text('Evidence changed'), findsOneWidget);
    expect(find.text('All clear'), findsNothing);
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
      home: FTheme(data: FTheme.neutral.light.desktop, child: child),
    ),
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
