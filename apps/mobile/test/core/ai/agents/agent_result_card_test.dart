import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact_store.dart';
import 'package:naviwealth/core/ai/agents/agent_intents.dart';
import 'package:naviwealth/core/ai/agents/agent_run_store.dart';
import 'package:naviwealth/core/ai/agents/providers.dart';
import 'package:naviwealth/core/ai/agents/ui/agent_result_card.dart';
import 'package:naviwealth/core/ai/composition/ask_ai.dart';
import 'package:naviwealth/core/ai/intent/ai_intent_invocation.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/shell/settings_route_paths.dart';
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

Widget _wrapWithRouter(GoRouter router) {
  return ProviderScope(
    child: MaterialApp.router(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}

AgentArtifact _artifact({
  List<AgentEvidenceRef> evidence = const [
    AgentEvidenceRef(type: 'metric', id: 'sleep-1', label: 'Sleep session'),
  ],
  List<AgentAction> actions = const [
    AgentAction(
      kind: 'review',
      label: 'Review plan',
      intent: 'open_plan',
      objectType: 'execution_action',
      objectId: 'action-1',
      payload: <String, Object?>{'proposal_kind': 'action_plan'},
    ),
  ],
}) {
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
    evidence: evidence,
    actions: actions,
    traceId: 'trace-1',
    createdAt: DateTime.utc(2026, 7, 5, 8),
  );
}

Future<void> _openArtifactSheet(
  WidgetTester tester, {
  AgentArtifact? artifact,
  List<Override> overrides = const <Override>[],
}) async {
  await tester.pumpWidget(
    _wrap(
      Builder(
        builder: (context) => FButton(
          onPress: () => unawaited(
            showAgentArtifactSheet(
              context: context,
              artifact: artifact ?? _artifact(),
            ),
          ),
          child: const Text('Open artifact'),
        ),
      ),
      overrides: overrides,
    ),
  );

  await tester.tap(find.text('Open artifact'));
  await tester.pumpAndSettle();
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

  testWidgets('compact result row renders light metadata and opens detail', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      _wrap(
        AgentCompactResultRow(
          artifact: _artifact(),
          metaLabel: 'Updated just now',
          onOpen: () => opened = true,
        ),
      ),
    );

    expect(find.text('Morning Briefing'), findsOneWidget);
    expect(find.text('Updated just now'), findsOneWidget);
    expect(find.text('Attention'), findsOneWidget);
    expect(
      find.text('Sleep debt is elevated; keep the first block light.'),
      findsNothing,
    );

    await tester.tap(find.text('Morning Briefing'));
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
    expect(find.textContaining('trace-1'), findsOneWidget);
    expect(find.text('Actions'), findsOneWidget);
    expect(find.text('Ask follow-up'), findsNothing);
    expect(find.text('Show evidence'), findsNothing);
    expect(find.text('Create plan'), findsNothing);
    expect(find.text('Snooze'), findsOneWidget);
    expect(find.text('Dismiss'), findsOneWidget);
    expect(find.text('Review plan'), findsOneWidget);
  });

  testWidgets('artifact sheet constrains detail body on a compact viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openArtifactSheet(tester);

    expect(find.text('Morning Briefing'), findsOneWidget);
    expect(find.text('Briefing'), findsOneWidget);
    expect(find.byType(AgentArtifactDetailBody), findsOneWidget);
    expect(
      find.text('Sleep debt is elevated; keep the first block light.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
  });

  testWidgets('panel state card constrains long copy on a compact viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(
        const SizedBox(
          width: 220,
          child: AgentResultPanelStateCard(
            icon: Icons.auto_awesome,
            title:
                'Extremely long agent status title that should not overflow the row',
            message:
                'A very long status message should stay inside the available width and use ellipsis when the panel is compact.',
          ),
        ),
      ),
    );

    expect(find.byType(AgentResultPanelStateCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detail follow-up opens askAi invocation for artifact', (
    tester,
  ) async {
    AiIntentInvocation? capturedInvocation;
    String? capturedObjectLabel;
    await _openArtifactSheet(
      tester,
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
    );

    await tester.tap(find.text('Ask follow-up'));
    await tester.pump(const Duration(milliseconds: 120));

    expect(capturedInvocation?.intent, kAgentExplainResultIntent);
    expect(capturedInvocation?.object?.type, kAgentArtifactObjectType);
    expect(capturedInvocation?.object?.id, 'artifact-1');
    expect(capturedInvocation?.context['agent_id'], 'agent-1');
    expect(capturedInvocation?.context['trace_id'], 'trace-1');
    expect(capturedObjectLabel, 'Morning Briefing');
  });

  testWidgets('detail follow-up ignores repeat taps while pending', (
    tester,
  ) async {
    final pending = Completer<void>();
    var calls = 0;
    await _openArtifactSheet(
      tester,
      overrides: [
        askAiSurfaceProvider.overrideWithValue((
          context, {
          invocation,
          objectLabel,
          prefill,
        }) async {
          calls += 1;
          await pending.future;
        }),
      ],
    );

    await tester.tap(find.text('Ask follow-up'));
    await tester.pump(const Duration(milliseconds: 120));

    expect(calls, 1);
    expect(find.byType(FCircularProgress), findsOneWidget);

    await tester.tap(find.text('Ask follow-up'));
    await tester.pump(const Duration(milliseconds: 120));

    expect(calls, 1);

    pending.complete();
    await tester.pumpAndSettle();

    expect(find.byType(FCircularProgress), findsNothing);
  });

  testWidgets('detail evidence action opens registered evidence intent', (
    tester,
  ) async {
    AiIntentInvocation? capturedInvocation;
    await _openArtifactSheet(
      tester,
      artifact: _artifact(actions: const <AgentAction>[]),
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
    );

    await tester.tap(find.text('Show evidence'));
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
    await _openArtifactSheet(
      tester,
      artifact: _artifact(evidence: const [], actions: const <AgentAction>[]),
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
    );

    await tester.tap(find.text('Create plan'));
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

  testWidgets('detail custom action opens its intent with object and payload', (
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

    final customAction = find.text('Review plan');
    await tester.ensureVisible(customAction);
    await tester.tap(customAction);
    await tester.pump(const Duration(milliseconds: 120));

    expect(capturedInvocation?.intent, 'open_plan');
    expect(capturedInvocation?.object?.type, 'execution_action');
    expect(capturedInvocation?.object?.id, 'action-1');
    expect(capturedInvocation?.context['action_kind'], 'review');
    expect(capturedInvocation?.context['action_label'], 'Review plan');
    expect(capturedInvocation?.context['proposal_kind'], 'action_plan');
    expect(capturedInvocation?.context['artifact_id'], 'artifact-1');
    expect(capturedObjectLabel, 'Morning Briefing');
  });

  testWidgets('detail trace action opens transparency detail route', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => FTheme(
            data: FThemes.slate.light.desktop,
            child: FScaffold(
              childPad: false,
              child: Center(
                child: FButton(
                  onPress: () => unawaited(
                    showAgentArtifactSheet(
                      context: context,
                      artifact: _artifact(),
                    ),
                  ),
                  child: const Text('Open artifact'),
                ),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '${SettingsRoutes.aiTransparency}/:requestId',
          builder: (_, state) => FTheme(
            data: FThemes.slate.light.desktop,
            child: FScaffold(
              childPad: false,
              child: Text('trace detail ${state.pathParameters['requestId']}'),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(_wrapWithRouter(router));

    await tester.tap(find.text('Open artifact'));
    await tester.pumpAndSettle();

    final openTrace = find.text('Runtime trace');
    await tester.ensureVisible(openTrace);
    await tester.tap(openTrace);
    await tester.pumpAndSettle();

    expect(find.text('trace detail trace-1'), findsOneWidget);
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

  for (final entry in <({AgentRunLifecycleStatus status, String label})>[
    (status: AgentRunLifecycleStatus.running, label: 'Running'),
    (status: AgentRunLifecycleStatus.noFinding, label: 'No finding'),
    (status: AgentRunLifecycleStatus.ready, label: 'Ready'),
  ]) {
    testWidgets('run status card renders ${entry.label} status', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          AgentRunStatusCard(
            record: AgentRunRecord(
              id: 'run-${entry.status.name}',
              ownerUserId: 'user-1',
              agentId: 'agent-1',
              agentName: 'Weekly Review',
              status: entry.status,
              trigger: AgentRunTrigger.schedule,
              startedAt: DateTime.utc(2026, 7, 5, 8),
              finishedAt: entry.status == AgentRunLifecycleStatus.running
                  ? null
                  : DateTime.utc(2026, 7, 5, 8, 1),
              summary: entry.status == AgentRunLifecycleStatus.ready
                  ? 'Review ready'
                  : null,
            ),
            metaLabel: 'Updated just now',
          ),
        ),
      );

      expect(find.text('Weekly Review'), findsOneWidget);
      expect(find.text(entry.label), findsWidgets);
      expect(find.text('Updated just now'), findsOneWidget);
      if (entry.status == AgentRunLifecycleStatus.running) {
        expect(find.byType(FCircularProgress), findsOneWidget);
      }
      if (entry.status == AgentRunLifecycleStatus.ready) {
        expect(find.text('Review ready'), findsOneWidget);
      }
    });
  }

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
  Future<Map<String, AgentArtifact>> latestForAgents({
    required String ownerUserId,
    required Iterable<String> agentIds,
    DateTime? visibleAt,
  }) async => const <String, AgentArtifact>{};

  @override
  Future<List<AgentArtifact>> latestForDomain({
    required String ownerUserId,
    required String domain,
    int limit = 20,
    DateTime? visibleAt,
  }) async => const <AgentArtifact>[];
}
