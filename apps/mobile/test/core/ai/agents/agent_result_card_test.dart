import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact_store.dart';
import 'package:naviwealth/core/ai/agents/agent_intents.dart';
import 'package:naviwealth/core/ai/agents/agent_run_store.dart';
import 'package:naviwealth/core/ai/agents/providers.dart';
import 'package:naviwealth/core/ai/agents/ui/agent_result_card.dart';
import 'package:naviwealth/core/ai/composition/ask_ai.dart';
import 'package:naviwealth/core/ai/intent/ai_intent_invocation.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

Widget _wrap(Widget child, {List<Override> overrides = const <Override>[]}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: FTheme(
        data: FThemes.slate.light.desktop,
        child: FScaffold(childPad: false, child: Center(child: child)),
      ),
    ),
  );
}

AgentArtifact _artifact() {
  return AgentArtifact(
    id: 'artifact-1',
    ownerUserId: 'user-1',
    agentId: 'agent-1',
    domain: 'health',
    kind: AgentArtifactKind.briefing,
    severity: AgentArtifactSeverity.attention,
    title: 'Morning Briefing',
    summary: 'Sleep debt is elevated; keep the first block light.',
    insights: const [
      AgentInsight(title: 'Sleep', body: '6h 12m, below your recent baseline.'),
      AgentInsight(title: 'HRV', body: 'HRV is stable enough for light work.'),
    ],
    evidence: const [
      AgentEvidenceRef(type: 'metric', id: 'sleep-1', label: 'Sleep session'),
    ],
    actions: const [
      AgentAction(kind: 'review', label: 'Review plan', intent: 'open_plan'),
    ],
    traceId: 'trace-1',
    createdAt: DateTime.utc(2026, 7, 5, 8),
  );
}

void main() {
  testWidgets('renders artifact summary and preview insights', (tester) async {
    await tester.pumpWidget(
      _wrap(
        AgentResultCard(
          artifact: _artifact(),
          metaLabel: 'Updated just now',
          footer: const SizedBox.shrink(),
        ),
      ),
    );

    expect(find.text('Morning Briefing'), findsOneWidget);
    expect(find.text('Updated just now'), findsOneWidget);
    expect(
      find.text('Sleep debt is elevated; keep the first block light.'),
      findsOneWidget,
    );
    expect(find.text('Sleep'), findsOneWidget);
    expect(find.text('Attention'), findsOneWidget);
  });

  testWidgets('invokes open callback when rendered without a footer', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      _wrap(
        AgentResultCard(
          artifact: _artifact(),
          metaLabel: 'Updated just now',
          onOpen: () => opened = true,
        ),
      ),
    );

    await tester.tap(find.text('Review'));
    await tester.pump(const Duration(milliseconds: 120));

    expect(opened, isTrue);
  });

  testWidgets('detail body renders artifact evidence and actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        SingleChildScrollView(
          child: AgentArtifactDetailBody(artifact: _artifact()),
        ),
      ),
    );

    expect(find.text('Insights'), findsOneWidget);
    expect(find.text('Evidence'), findsOneWidget);
    expect(find.text('Sleep session'), findsOneWidget);
    expect(find.text('Trace'), findsOneWidget);
    expect(find.text('Runtime trace'), findsOneWidget);
    expect(find.text('trace-1'), findsOneWidget);
    expect(find.text('Actions'), findsOneWidget);
    expect(find.text('Ask follow-up'), findsOneWidget);
    expect(find.text('Show evidence'), findsOneWidget);
    expect(find.text('Create plan'), findsOneWidget);
    expect(find.text('Snooze'), findsWidgets);
    expect(find.text('Dismiss'), findsWidgets);
    expect(find.text('Review plan'), findsOneWidget);
  });

  testWidgets('detail follow-up opens askAi invocation for artifact', (
    tester,
  ) async {
    AiIntentInvocation? capturedInvocation;
    String? capturedObjectLabel;
    await tester.pumpWidget(
      _wrap(
        SingleChildScrollView(
          child: AgentArtifactDetailBody(artifact: _artifact()),
        ),
        overrides: [
          askAiSurfaceProvider.overrideWithValue((
            context, {
            invocation,
            objectLabel,
            prefill,
          }) async {
            capturedInvocation = invocation;
            capturedObjectLabel = objectLabel;
          }),
        ],
      ),
    );

    await tester.tap(find.text('Ask').first);
    await tester.pump(const Duration(milliseconds: 120));

    expect(capturedInvocation?.intent, kAgentExplainResultIntent);
    expect(capturedInvocation?.object?.type, kAgentArtifactObjectType);
    expect(capturedInvocation?.object?.id, 'artifact-1');
    expect(capturedInvocation?.context['agent_id'], 'agent-1');
    expect(capturedInvocation?.context['trace_id'], 'trace-1');
    expect(capturedObjectLabel, 'Morning Briefing');
  });

  testWidgets('detail evidence action opens registered evidence intent', (
    tester,
  ) async {
    AiIntentInvocation? capturedInvocation;
    await tester.pumpWidget(
      _wrap(
        SingleChildScrollView(
          child: AgentArtifactDetailBody(artifact: _artifact()),
        ),
        overrides: [
          askAiSurfaceProvider.overrideWithValue((
            context, {
            invocation,
            objectLabel,
            prefill,
          }) async {
            capturedInvocation = invocation;
          }),
        ],
      ),
    );

    await tester.tap(find.text('Ask').at(1));
    await tester.pump(const Duration(milliseconds: 120));

    expect(capturedInvocation?.intent, kAgentShowEvidenceIntent);
    expect(capturedInvocation?.object?.type, kAgentArtifactObjectType);
    expect(capturedInvocation?.object?.id, 'artifact-1');
    expect(capturedInvocation?.context['follow_up_focus'], 'evidence');
    expect(capturedInvocation?.context['evidence_refs'], isNotEmpty);
  });

  testWidgets('detail plan action opens registered plan intent', (
    tester,
  ) async {
    AiIntentInvocation? capturedInvocation;
    await tester.pumpWidget(
      _wrap(
        SingleChildScrollView(
          child: AgentArtifactDetailBody(artifact: _artifact()),
        ),
        overrides: [
          askAiSurfaceProvider.overrideWithValue((
            context, {
            invocation,
            objectLabel,
            prefill,
          }) async {
            capturedInvocation = invocation;
          }),
        ],
      ),
    );

    final planAsk = find.text('Ask').at(2);
    await tester.ensureVisible(planAsk);
    await tester.tap(planAsk);
    await tester.pump(const Duration(milliseconds: 120));

    expect(capturedInvocation?.intent, kAgentCreatePlanFromResultIntent);
    expect(capturedInvocation?.object?.type, kAgentArtifactObjectType);
    expect(capturedInvocation?.object?.id, 'artifact-1');
    expect(capturedInvocation?.context['follow_up_focus'], 'plan');
    expect(
      capturedInvocation?.capabilities,
      containsAll(<AiCapability>{AiCapability.chat, AiCapability.proposal}),
    );
  });

  testWidgets('detail local actions snooze and dismiss artifact', (
    tester,
  ) async {
    final store = _FakeArtifactStore();
    var visibilityChanges = 0;
    await tester.pumpWidget(
      _wrap(
        SingleChildScrollView(
          child: AgentArtifactDetailBody(
            artifact: _artifact(),
            onVisibilityChanged: () => visibilityChanges += 1,
          ),
        ),
        overrides: [
          currentUserIdProvider.overrideWithValue(() async => 'user-1'),
          agentArtifactStoreProvider.overrideWith((ref) async => store),
        ],
      ),
    );

    final snooze = find.text('Snooze').last;
    await tester.ensureVisible(snooze);
    await tester.tap(snooze);
    await tester.pump(const Duration(milliseconds: 120));

    expect(store.snoozedId, 'artifact-1');
    expect(store.snoozedOwnerUserId, 'user-1');
    expect(store.snoozedUntil, isNotNull);
    expect(store.snoozedUntil!.isAfter(DateTime.now().toUtc()), isTrue);
    expect(visibilityChanges, 1);

    final dismiss = find.text('Dismiss').last;
    await tester.ensureVisible(dismiss);
    await tester.tap(dismiss);
    await tester.pump(const Duration(milliseconds: 120));

    expect(store.dismissedId, 'artifact-1');
    expect(store.dismissedOwnerUserId, 'user-1');
    expect(store.dismissedAt, isNotNull);
    expect(visibilityChanges, 2);
  });

  testWidgets('run status card renders failed status and retry action', (
    tester,
  ) async {
    var retried = false;
    await tester.pumpWidget(
      _wrap(
        AgentRunStatusCard(
          record: AgentRunRecord(
            id: 'run-1',
            ownerUserId: 'user-1',
            agentId: 'agent-1',
            agentName: 'Weekly Review',
            status: AgentRunLifecycleStatus.failed,
            trigger: AgentRunTrigger.manual,
            startedAt: DateTime.utc(2026, 7, 5, 8),
            finishedAt: DateTime.utc(2026, 7, 5, 8, 1),
            error: 'Runtime unavailable',
          ),
          metaLabel: 'Updated just now',
          onRetry: () => retried = true,
        ),
      ),
    );

    expect(find.text('Weekly Review'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('Runtime unavailable'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump(const Duration(milliseconds: 120));

    expect(retried, isTrue);
  });
}

class _FakeArtifactStore implements AgentArtifactStore {
  String? dismissedOwnerUserId;
  String? dismissedId;
  DateTime? dismissedAt;
  String? snoozedOwnerUserId;
  String? snoozedId;
  DateTime? snoozedUntil;

  @override
  Future<void> dismiss({
    required String ownerUserId,
    required String id,
    required DateTime dismissedAt,
  }) async {
    dismissedOwnerUserId = ownerUserId;
    dismissedId = id;
    this.dismissedAt = dismissedAt;
  }

  @override
  Future<void> snooze({
    required String ownerUserId,
    required String id,
    required DateTime until,
  }) async {
    snoozedOwnerUserId = ownerUserId;
    snoozedId = id;
    snoozedUntil = until;
  }

  @override
  Future<AgentArtifact?> read(String id) async => null;

  @override
  Future<void> save(AgentArtifact artifact) async {}

  @override
  Future<List<AgentArtifact>> latestForAgent({
    required String ownerUserId,
    required String agentId,
    int limit = 10,
    DateTime? visibleAt,
  }) async => const <AgentArtifact>[];

  @override
  Future<List<AgentArtifact>> latestForDomain({
    required String ownerUserId,
    required String domain,
    int limit = 20,
    DateTime? visibleAt,
  }) async => const <AgentArtifact>[];
}
