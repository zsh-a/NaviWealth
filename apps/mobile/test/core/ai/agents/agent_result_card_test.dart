import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact_store.dart';
import 'package:naviwealth/core/ai/agents/agent_evidence_navigation_store.dart';
import 'package:naviwealth/core/ai/agents/agent_finding_store.dart';
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

import '../../persistence/test_database.dart';

Widget _wrap(Widget child, {List<Override> overrides = const <Override>[]}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: FTheme(
        data: FTheme.neutral.light.desktop,
        child: FScaffold(childPad: false, child: Center(child: child)),
      ),
    ),
  );
}

Widget _wrapWithRouter(
  GoRouter router, {
  List<Override> overrides = const <Override>[],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}

AgentArtifact _artifact({
  String id = 'artifact-1',
  String agentId = 'agent-1',
  String title = 'Daily Navigator',
  List<AgentEvidenceRef> evidence = const [
    AgentEvidenceRef(
      type: 'metric',
      id: 'sleep-1',
      label: 'Sleep session',
      description: 'Recorded sleep session from the local health store.',
      route: '/evidence',
      details: [AgentMetric(label: 'Duration', value: '6h 12m')],
    ),
  ],
  List<AgentAction> actions = const [
    AgentAction(kind: 'open_route', label: 'Review plan', route: '/plan'),
  ],
}) {
  return AgentArtifact(
    id: id,
    ownerUserId: 'user-1',
    agentId: agentId,
    domain: 'health',
    kind: AgentArtifactKind.briefing,
    severity: AgentArtifactSeverity.attention,
    title: title,
    summary: 'Sleep debt is elevated; keep the first block light.',
    metrics: const [
      AgentMetric(label: 'Sleep', value: '6h 12m', context: 'Target 8h'),
      AgentMetric(label: 'HRV', value: 'Stable'),
    ],
    insights: const [
      AgentInsight(
        id: 'sleep',
        title: 'Sleep',
        body: '6h 12m, below your recent baseline.',
        details: [AgentMetric(label: 'Recent baseline', value: '7h 24m')],
        evidenceIds: ['sleep-1'],
      ),
      AgentInsight(title: 'HRV', body: 'HRV is stable enough for light work.'),
    ],
    evidence: evidence,
    actions: actions,
    methodology: const AgentMethodology(
      title: 'On-device analysis',
      body: 'Calculated from local health data.',
    ),
    traceId: 'trace-1',
    createdAt: DateTime.utc(2026, 7, 5, 8),
  );
}

Future<void> _pumpArtifactDetail(
  WidgetTester tester, {
  AgentArtifact? artifact,
  List<Override> overrides = const <Override>[],
}) async {
  final resolvedArtifact = artifact ?? _artifact();
  await tester.pumpWidget(
    _wrap(_artifactDetailContent(resolvedArtifact), overrides: overrides),
  );
  await tester.pumpAndSettle();
}

Widget _artifactDetailContent(AgentArtifact artifact) => ListView(
  children: [
    AgentArtifactDetailBody(artifact: artifact),
    AgentArtifactDetailFooter(artifact: artifact),
  ],
);

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

    expect(find.text('Daily Navigator'), findsOneWidget);
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

  testWidgets('summary layout keeps one calm action surface', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      _wrap(
        AgentResultCard(
          artifact: _artifact(),
          metaLabel: 'Updated just now',
          onOpen: () => opened = true,
          layout: AgentResultCardLayout.summary,
        ),
      ),
    );

    expect(
      find.text('Sleep debt is elevated; keep the first block light.'),
      findsOneWidget,
    );
    expect(find.text('Sleep'), findsNothing);
    expect(find.text('Review'), findsNothing);
    expect(find.byIcon(FLucideIcons.chevronRight), findsOneWidget);

    await tester.tap(find.text('Daily Navigator'));
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

    expect(find.text('Daily Navigator'), findsOneWidget);
    expect(find.text('Updated just now'), findsOneWidget);
    expect(find.text('Attention'), findsOneWidget);
    expect(
      find.text('Sleep debt is elevated; keep the first block light.'),
      findsNothing,
    );

    await tester.tap(find.text('Daily Navigator'));
    await tester.pump(const Duration(milliseconds: 120));

    expect(opened, isTrue);
  });

  testWidgets('multiple agent results swipe through one layered stack', (
    tester,
  ) async {
    final first = _artifact();
    final second = _artifact(
      id: 'artifact-2',
      agentId: 'agent-2',
      title: 'Recovery Alert',
    );
    await tester.pumpWidget(
      _wrap(
        AgentResultsSection(
          bundle: AgentResultBundle(
            artifacts: <AgentArtifact>[first, second],
            latestRuns: const <AgentRunRecord>[],
          ),
          metaLabelBuilder: (_) => 'Updated just now',
          onOpen: (_) {},
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('agent-result-stack')),
      findsOneWidget,
    );
    expect(find.byType(AgentResultCard), findsOneWidget);
    expect(find.byType(AgentCompactResultRow), findsNothing);
    expect(find.text('Daily Navigator'), findsOneWidget);
    expect(find.text('Recovery Alert'), findsNothing);

    await tester.drag(
      find.byKey(const ValueKey<String>('agent-result-front-card')),
      const Offset(-240, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('Daily Navigator'), findsNothing);
    expect(find.text('Recovery Alert'), findsOneWidget);
  });

  testWidgets('a single agent result does not add stack decoration', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        AgentResultsSection(
          bundle: AgentResultBundle(
            artifacts: <AgentArtifact>[_artifact()],
            latestRuns: const <AgentRunRecord>[],
          ),
          metaLabelBuilder: (_) => 'Updated just now',
          onOpen: (_) {},
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('agent-result-stack')),
      findsNothing,
    );
    expect(find.byType(AgentResultCard), findsOneWidget);
  });

  testWidgets('a short stack drag follows the finger and eases back', (
    tester,
  ) async {
    final first = _artifact();
    final second = _artifact(
      id: 'artifact-2',
      agentId: 'agent-2',
      title: 'Recovery Alert',
    );
    await tester.pumpWidget(
      _wrap(
        AgentResultsSection(
          bundle: AgentResultBundle(
            artifacts: <AgentArtifact>[first, second],
            latestRuns: const <AgentRunRecord>[],
          ),
          metaLabelBuilder: (_) => 'Updated just now',
          onOpen: (_) {},
        ),
      ),
    );

    final card = find.byType(AgentResultCard);
    final initialLeft = tester.getTopLeft(card).dx;
    final gesture = await tester.startGesture(tester.getCenter(card));
    await gesture.moveBy(const Offset(-20, 0));
    await gesture.moveBy(const Offset(-24, 0));
    await tester.pump();
    expect(tester.getTopLeft(card).dx, lessThan(initialLeft));

    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(card).dx, closeTo(initialLeft, 0.5));
    expect(find.text('Daily Navigator'), findsOneWidget);
    expect(find.text('Recovery Alert'), findsNothing);
  });

  testWidgets('detail body progressively reveals insight and evidence detail', (
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
    expect(find.text('6h 12m'), findsWidgets);
    expect(find.text('Evidence & method'), findsOneWidget);
    expect(find.textContaining('trace-1'), findsNothing);
    expect(find.text('Ask Agent'), findsNothing);
    expect(find.text('Snooze'), findsOneWidget);
    expect(find.text('Dismiss'), findsOneWidget);

    await tester.tap(find.text('Sleep').last);
    await tester.pumpAndSettle();
    expect(find.text('Recent baseline'), findsOneWidget);
    expect(find.text('Supported by 1 sources'), findsOneWidget);

    await tester.tap(find.text('Evidence & method'));
    await tester.pumpAndSettle();
    expect(find.text('Sleep session'), findsOneWidget);
    expect(find.text('On-device analysis'), findsOneWidget);
    expect(find.text('Technical details'), findsOneWidget);
    expect(find.textContaining('trace-1'), findsNothing);
  });

  testWidgets('artifact detail constrains body on a compact viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpArtifactDetail(tester);

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
            title: 'Extremely long agent status title that should not overflow the row',
            message: 'A very long status message should stay inside the available width and use ellipsis when the panel is compact.',
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
    await _pumpArtifactDetail(
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

    await tester.tap(find.text('Ask Agent'));
    await tester.pump(const Duration(milliseconds: 120));

    expect(capturedInvocation?.intent, kAgentExplainResultIntent);
    expect(capturedInvocation?.object?.type, kAgentArtifactObjectType);
    expect(capturedInvocation?.object?.id, 'artifact-1');
    expect(capturedInvocation?.context['agent_id'], 'agent-1');
    expect(capturedInvocation?.context['trace_id'], 'trace-1');
    expect(capturedObjectLabel, 'Daily Navigator');
  });

  testWidgets('detail follow-up ignores repeat taps while pending', (
    tester,
  ) async {
    final pending = Completer<void>();
    var calls = 0;
    await _pumpArtifactDetail(
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

    await tester.tap(find.text('Ask Agent'));
    await tester.pump(const Duration(milliseconds: 120));

    expect(calls, 1);
    expect(find.byType(FCircularProgress), findsOneWidget);

    await tester.tap(find.text('Ask Agent'));
    await tester.pump(const Duration(milliseconds: 120));

    expect(calls, 1);

    pending.complete();
    await tester.pumpAndSettle();

    expect(find.byType(FCircularProgress), findsNothing);
  });

  testWidgets('detail evidence opens its registered domain route', (
    tester,
  ) async {
    final navigationStore = _RecordingNavigationStore();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => FTheme(
            data: FTheme.neutral.light.desktop,
            child: FScaffold(
              childPad: false,
              child: _artifactDetailContent(_artifact()),
            ),
          ),
        ),
        GoRoute(
          path: '/evidence',
          builder: (_, _) => FTheme(
            data: FTheme.neutral.light.desktop,
            child: const FScaffold(
              childPad: false,
              child: Text('evidence detail'),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _wrapWithRouter(
        router,
        overrides: [
          agentEvidenceNavigationStoreProvider.overrideWith(
            (ref) async => navigationStore,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final evidenceSection = find.text('Evidence & method');
    await tester.ensureVisible(evidenceSection);
    await tester.tap(evidenceSection);
    await tester.pumpAndSettle();
    final evidence = find.text('Sleep session');
    await tester.ensureVisible(evidence);
    await tester.tap(evidence);
    await tester.pumpAndSettle();

    expect(find.text('evidence detail'), findsOneWidget);
    expect(navigationStore.outcomes, <bool>[true]);
  });

  testWidgets('detail primary action opens its registered domain route', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => FTheme(
            data: FTheme.neutral.light.desktop,
            child: FScaffold(
              childPad: false,
              child: _artifactDetailContent(_artifact()),
            ),
          ),
        ),
        GoRoute(
          path: '/plan',
          builder: (_, _) => FTheme(
            data: FTheme.neutral.light.desktop,
            child: const FScaffold(childPad: false, child: Text('plan detail')),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(_wrapWithRouter(router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review plan'));
    await tester.pumpAndSettle();

    expect(find.text('plan detail'), findsOneWidget);
  });

  testWidgets('detail custom action opens its intent with object and payload', (
    tester,
  ) async {
    AiIntentInvocation? capturedInvocation;
    String? capturedObjectLabel;
    await _pumpArtifactDetail(
      tester,
      artifact: _artifact(
        actions: const [
          AgentAction(
            kind: 'review',
            label: 'Review plan',
            intent: 'open_plan',
            objectType: 'execution_action',
            objectId: 'action-1',
            payload: <String, Object?>{'proposal_kind': 'action_plan'},
          ),
        ],
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
    expect(capturedObjectLabel, 'Daily Navigator');
  });

  testWidgets('detail trace action opens transparency detail route', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => FTheme(
            data: FTheme.neutral.light.desktop,
            child: FScaffold(
              childPad: false,
              child: _artifactDetailContent(_artifact()),
            ),
          ),
        ),
        GoRoute(
          path: '${SettingsRoutes.aiTransparency}/:requestId',
          builder: (_, state) => FTheme(
            data: FTheme.neutral.light.desktop,
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

    await tester.pumpAndSettle();

    final evidenceSection = find.text('Evidence & method');
    await tester.ensureVisible(evidenceSection);
    await tester.tap(evidenceSection);
    await tester.pumpAndSettle();

    final openTrace = find.text('Technical details');
    await tester.ensureVisible(openTrace);
    await tester.tap(openTrace);
    await tester.pumpAndSettle();

    expect(find.text('trace detail trace-1'), findsOneWidget);
  });

  testWidgets('detail local actions snooze and dismiss artifact', (
    tester,
  ) async {
    final store = _FakeArtifactStore();
    final db = makeTestDatabase();
    addTearDown(db.close);
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
          agentFindingStoreProvider.overrideWith(
            (ref) async => SqliteAgentFindingStore(db: db),
          ),
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

  testWidgets('run status retry ignores repeat taps while pending', (
    tester,
  ) async {
    final pending = Completer<void>();
    var retryCount = 0;
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
          onRetry: () async {
            retryCount += 1;
            await pending.future;
          },
        ),
      ),
    );

    await tester.tap(find.text('Retry'));
    await tester.pump(const Duration(milliseconds: 120));

    expect(retryCount, 1);
    expect(find.byType(FCircularProgress), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump(const Duration(milliseconds: 120));

    expect(retryCount, 1);

    pending.complete();
    await tester.pumpAndSettle();

    expect(find.byType(FCircularProgress), findsNothing);
  });
}

class _RecordingNavigationStore implements AgentEvidenceNavigationStore {
  final List<bool> outcomes = <bool>[];

  @override
  Future<void> record({
    required DateTime occurredAt,
    required bool succeeded,
  }) async {
    outcomes.add(succeeded);
  }

  @override
  Future<AgentEvidenceNavigationSummary> summarize({
    required DateTime since,
  }) async => AgentEvidenceNavigationSummary(
    attempts: outcomes.length,
    successes: outcomes.where((value) => value).length,
  );
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
