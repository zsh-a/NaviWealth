import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/theme/app_theme.dart';
import 'package:naviwealth/features/execution/agents/providers.dart'
    as execution_agent_providers;
import 'package:naviwealth/features/execution/data/execution_daily_focus.dart';
import 'package:naviwealth/features/execution/data/execution_repository.dart';
import 'package:naviwealth/features/execution/data/providers.dart';
import 'package:naviwealth/features/execution/domain/execution_models.dart';
import 'package:naviwealth/features/execution/ui/execution_action_card_controller.dart';
import 'package:naviwealth/features/execution/ui/execution_action_sheet.dart';
import 'package:naviwealth/features/execution/ui/execution_commitments_page.dart';
import 'package:naviwealth/features/execution/ui/execution_create_sheet.dart';
import 'package:naviwealth/features/execution/ui/execution_lifecycle_card_controller.dart';
import 'package:naviwealth/features/execution/ui/execution_today_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../../core/persistence/test_database.dart';
import '../../finance/data/repositories/_stub_stamper.dart';

void main() {
  testWidgets('Today keeps review reachable and offers focused capture', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(
        const ExecutionTodayPage(),
        textScaler: const TextScaler.linear(2),
        overrides: _executionOverrides(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Review'), findsWidgets);
    expect(find.text('New Action'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, isNotNull);
    expect(tester.takeException(), isNull);
    // Focusing the greeting-header action starts its FTooltip show timer;
    // flush it so no timer is left pending at teardown (same pattern as
    // shell_chrome_test's tooltip flush).
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  });

  testWidgets('Today keeps unscheduled backlog out of the daily workspace', (
    tester,
  ) async {
    final backlog = _action(id: 'backlog', title: 'Plan the next release');
    await tester.pumpWidget(
      _wrap(
        const ExecutionTodayPage(),
        overrides: _executionOverrides(
          todayActions: const [],
          openActions: [backlog],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Backlog 1'), findsNothing);
    expect(find.text('Plan the next release'), findsNothing);

    expect(find.text('Today 0'), findsOneWidget);
    expect(find.textContaining('Backlog'), findsNothing);
  });

  testWidgets('Today asks before adopting review Top 3 recommendations', (
    tester,
  ) async {
    final first = _action(id: 'first', title: 'Resolve the launch blocker');
    final second = _action(id: 'second', title: 'Confirm the launch scope');
    await tester.pumpWidget(
      _wrap(
        const ExecutionTodayPage(),
        overrides: [
          ..._executionOverrides(
            todayActions: [first, second],
            openActions: [first, second],
          ),
          execution_agent_providers.latestExecutionReviewArtifactProvider
              .overrideWith(
                (ref) async => AgentArtifact(
                  id: 'review-focus',
                  ownerUserId: 'user',
                  agentId: 'execution_review',
                  domain: 'execution',
                  kind: AgentArtifactKind.review,
                  severity: AgentArtifactSeverity.info,
                  title: 'Execution Review',
                  summary: 'Suggested focus',
                  insights: const [
                    AgentInsight(
                      id: 'today_focus',
                      title: 'Today focus',
                      body: 'Start here.',
                      payload: {
                        'recommended_focus_ids': ['first', 'second'],
                      },
                    ),
                  ],
                  createdAt: DateTime.utc(2026, 7, 24),
                ),
              ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ExecutionTodayPage)),
    );
    expect(container.read(executionDailyFocusProvider), isEmpty);
    expect(find.text('Use these'), findsOneWidget);
    expect(find.text('Resolve the launch blocker'), findsOneWidget);
    expect(find.text('Confirm the launch scope'), findsOneWidget);

    await tester.tap(find.text('Use these'));
    await tester.pumpAndSettle();

    expect(container.read(executionDailyFocusProvider), ['first', 'second']);
    expect(find.text('Use these'), findsNothing);
    expect(find.text('Resolve the launch blocker'), findsOneWidget);
    expect(find.text('Confirm the launch scope'), findsOneWidget);
    expect(find.text('Next actions'), findsNothing);
  });

  testWidgets('Commitments renders open actions without a container', (
    tester,
  ) async {
    final action = _action(id: 'open', title: 'Capture standalone follow-up');
    await tester.pumpWidget(
      _wrap(
        const ExecutionCommitmentsPage(),
        overrides: _executionOverrides(openActions: [action]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Inbox'), findsOneWidget);
    expect(find.text('Capture standalone follow-up'), findsOneWidget);
    expect(find.text('No active work'), findsNothing);
  });

  testWidgets(
    'new action capture starts compact and reveals details on demand',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => FButton(
              onPress: () => showExecutionActionSheet(context: context),
              child: const Text('Open capture'),
            ),
          ),
          overrides: _executionOverrides(),
        ),
      );

      await tester.tap(find.text('Open capture'));
      await tester.pumpAndSettle();

      expect(find.text('When'), findsOneWidget);
      expect(find.text('Inbox'), findsOneWidget);
      expect(find.text('Tomorrow'), findsOneWidget);
      expect(find.text('More details'), findsOneWidget);
      expect(find.text('Priority'), findsNothing);
      expect(find.text('Scheduled'), findsNothing);
      expect(find.text('Due'), findsNothing);

      await tester.tap(find.text('More details'));
      await tester.pumpAndSettle();

      expect(find.text('Priority'), findsOneWidget);
      expect(find.text('Scheduled'), findsOneWidget);
      expect(find.text('Due'), findsOneWidget);
      expect(find.text('Belongs to'), findsOneWidget);
      expect(find.text('Plan'), findsNothing);
      expect(find.text('Commitment'), findsNothing);
      expect(find.text('Fewer details'), findsOneWidget);
    },
  );

  testWidgets('action uses one relation picker and inherits a plan', (
    tester,
  ) async {
    final project = ExecutionProject(
      id: 'project',
      title: 'Launch plan',
      createdAt: DateTime.utc(2026, 7, 24),
      sync: _sync(),
    );
    final commitment = ExecutionCommitment(
      id: 'commitment',
      projectId: project.id,
      title: 'Ship the launch',
      createdAt: DateTime.utc(2026, 7, 24),
      sync: _sync(),
    );
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => FButton(
            onPress: () => showExecutionActionSheet(context: context),
            child: const Text('Open capture'),
          ),
        ),
        overrides: _executionOverrides(
          projects: [project],
          commitments: [commitment],
        ),
      ),
    );

    await tester.tap(find.text('Open capture'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('More details'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Belongs to'));
    await tester.pumpAndSettle();

    expect(find.text('Launch plan'), findsOneWidget);
    expect(find.text('Ship the launch'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Ship the launch')).dx,
      greaterThan(tester.getTopLeft(find.text('Launch plan')).dx),
    );

    await tester.tap(find.text('Ship the launch'));
    await tester.pumpAndSettle();
    expect(find.text('Ship the launch'), findsOneWidget);
    expect(find.text('Belongs to'), findsOneWidget);
  });

  testWidgets('action details remain usable on a small phone with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => FButton(
            onPress: () => showExecutionActionSheet(context: context),
            child: const Text('Open capture'),
          ),
        ),
        overrides: _executionOverrides(),
      ),
    );
    await tester.tap(find.text('Open capture'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('More details'));
    await tester.pumpAndSettle();

    expect(find.text('Belongs to'), findsOneWidget);
    expect(find.text('Scheduled'), findsOneWidget);
    expect(find.text('Due'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Plans demotes closed work to an archive entry', (tester) async {
    final active = ExecutionProject(
      id: 'active',
      title: 'Active launch',
      createdAt: DateTime.utc(2026, 7, 24),
      sync: _sync(),
    );
    final closed = ExecutionProject(
      id: 'closed',
      title: 'Closed launch',
      status: ExecutionProjectStatus.completed,
      createdAt: DateTime.utc(2026, 7, 24),
      sync: _sync(),
    );
    await tester.pumpWidget(
      _wrap(
        const ExecutionCommitmentsPage(),
        overrides: _executionOverrides(
          projects: [active],
          closedProjects: [closed],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Active launch'), findsOneWidget);
    expect(find.text('Closed launch'), findsNothing);
    expect(find.text('Closed work'), findsOneWidget);

    await tester.tap(find.text('Closed work'));
    await tester.pumpAndSettle();

    expect(find.text('Active launch'), findsNothing);
    expect(find.text('Closed launch'), findsOneWidget);
    expect(find.text('Back to active work'), findsOneWidget);
  });

  testWidgets('shared Add entry exposes only action and plan', (tester) async {
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => FButton(
            onPress: () => showExecutionCreateSheet(context),
            child: const Text('Open add'),
          ),
        ),
        overrides: _executionOverrides(),
      ),
    );

    await tester.tap(find.text('Open add'));
    await tester.pumpAndSettle();

    expect(find.text('New Action'), findsOneWidget);
    expect(find.text('New Plan'), findsOneWidget);
    expect(find.text('New Commitment'), findsNothing);
  });

  testWidgets('manual action status changes can be restored', (tester) async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final repository = ExecutionRepository(
      db: db,
      outbox: InMemoryOutboxStore(),
    );
    final action = _action(id: 'undo-action', title: 'Finish the handoff');
    await repository.upsertAction(action);
    ExecutionActionStatusUndo? undo;

    await tester.pumpWidget(
      _wrap(
        Consumer(
          builder: (context, ref, child) => FButton(
            onPress: () async {
              undo = await updateExecutionActionStatus(
                ref: ref,
                action: action,
                status: ExecutionActionStatus.done,
                progressNote: 'Finished the handoff.',
              );
            },
            child: const Text('Complete'),
          ),
        ),
        overrides: [
          executionRepositoryProvider.overrideWith((_) async => repository),
          mutationStamperProvider.overrideWith(
            (_) async => makeStubStamper(userId: 'user'),
          ),
        ],
      ),
    );

    await tester.tap(find.text('Complete'));
    await tester.pumpAndSettle();

    final completed = await repository.findAction(
      ownerUserId: 'user',
      id: action.id,
    );
    final progress = await repository.listRecentProgress(ownerUserId: 'user');
    expect(completed?.status, ExecutionActionStatus.done);
    expect(progress.single.note, 'Finished the handoff.');
    expect(undo, isNotNull);

    await undo!.restore();

    final restored = await repository.findAction(
      ownerUserId: 'user',
      id: action.id,
    );
    final removedProgress = await repository.findProgress(
      ownerUserId: 'user',
      id: progress.single.id,
    );
    expect(restored?.status, ExecutionActionStatus.todo);
    expect(restored?.completedAt, isNull);
    expect(removedProgress?.sync.deletedAt, isNotNull);
  });

  testWidgets('blocking an action requires and records a reason', (
    tester,
  ) async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final repository = ExecutionRepository(
      db: db,
      outbox: InMemoryOutboxStore(),
    );
    final action = _action(id: 'blocked-action', title: 'Publish the release');
    await repository.upsertAction(action);

    await tester.pumpWidget(
      _wrap(
        ExecutionActionCardController(
          action: action,
          onEdit: () {},
          onRecordProgress: () {},
          doneProgressNote: 'Done.',
          droppedProgressNote: 'Dropped.',
        ),
        overrides: [
          executionRepositoryProvider.overrideWith((_) async => repository),
          mutationStamperProvider.overrideWith(
            (_) async => makeStubStamper(userId: 'user'),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(FLucideIcons.ellipsis));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Block'));
    await tester.pumpAndSettle();

    expect(find.text('What is blocking this action?'), findsOneWidget);
    final blockButton = find.widgetWithText(FButton, 'Block');
    expect(tester.widget<FButton>(blockButton).onPress, isNull);

    await tester.enterText(
      find.byType(FTextField),
      'Waiting for App Store approval',
    );
    await tester.pump();
    expect(tester.widget<FButton>(blockButton).onPress, isNotNull);
    await tester.tap(blockButton);
    await tester.pump(const Duration(milliseconds: 400));

    final blocked = await repository.findAction(
      ownerUserId: 'user',
      id: action.id,
    );
    final progress = await repository.listRecentProgress(ownerUserId: 'user');
    expect(blocked?.status, ExecutionActionStatus.blocked);
    expect(progress.single.kind, ExecutionProgressKind.blocker);
    expect(progress.single.note, 'Waiting for App Store approval');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('archiving open project confirms and records progress', (
    tester,
  ) async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final repository = ExecutionRepository(
      db: db,
      outbox: InMemoryOutboxStore(),
    );
    final project = ExecutionProject(
      id: 'archive-project',
      title: 'Archive project',
      createdAt: DateTime.utc(2026, 7, 1),
      sync: _sync(),
    );
    await repository.upsertProject(project);

    await tester.pumpWidget(
      _wrap(
        ExecutionProjectCardController(
          project: project,
          openActionCount: 1,
          onCreateAction: () {},
          onEdit: () {},
          onRecordProgress: () {},
        ),
        overrides: [
          executionRepositoryProvider.overrideWith((_) async => repository),
          mutationStamperProvider.overrideWith(
            (_) async => makeStubStamper(userId: 'u-test'),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(FLucideIcons.ellipsis));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();

    expect(find.text('Archive with open actions?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FButton, 'Archive').last);
    await tester.pumpAndSettle();

    final archived = await repository.findProject(
      ownerUserId: 'u-test',
      id: project.id,
    );
    final progress = await repository.listRecentProgress(ownerUserId: 'u-test');
    expect(archived?.status, ExecutionProjectStatus.archived);
    expect(progress.single.note, 'Project archived.');
  });
}

List<Override> _executionOverrides({
  List<ExecutionAction> todayActions = const [],
  List<ExecutionAction> openActions = const [],
  List<ExecutionAction> closedActions = const [],
  List<ExecutionProject> projects = const [],
  List<ExecutionProject> closedProjects = const [],
  List<ExecutionCommitment> commitments = const [],
  List<ExecutionCommitment> closedCommitments = const [],
}) {
  return [
    executionTodayActionsProvider.overrideWith(
      (ref) => Stream.value(todayActions),
    ),
    executionOpenActionsProvider.overrideWith(
      (ref) => Stream.value(openActions),
    ),
    executionProjectsProvider.overrideWith((ref) => Stream.value(projects)),
    executionClosedProjectsProvider.overrideWith(
      (ref) => Stream.value(closedProjects),
    ),
    executionCommitmentsProvider.overrideWith(
      (ref) => Stream.value(commitments),
    ),
    executionClosedCommitmentsProvider.overrideWith(
      (ref) => Stream.value(closedCommitments),
    ),
    executionClosedActionsProvider.overrideWith(
      (ref) => Stream.value(closedActions),
    ),
    executionRecentProgressProvider.overrideWith(
      (ref) => Stream.value(const <ExecutionProgressEntry>[]),
    ),
    executionActionRelationsProvider.overrideWith(
      (ref) async => ExecutionRelations(
        actions: {for (final action in openActions) action.id: action},
        projects: {for (final project in projects) project.id: project},
        commitments: {
          for (final commitment in commitments) commitment.id: commitment,
        },
      ),
    ),
  ];
}

Widget _wrap(
  Widget child, {
  required List<Override> overrides,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en', 'US'),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: FTheme(data: FTheme.neutral.light.desktop, child: child),
        ),
      ),
    ),
  );
}

ExecutionAction _action({required String id, required String title}) {
  return ExecutionAction(
    id: id,
    title: title,
    createdAt: DateTime.utc(2026, 7, 24),
    sync: _sync(ownerUserId: 'user'),
  );
}

SyncMeta _sync({String ownerUserId = 'u-test'}) {
  final now = DateTime.utc(2026, 7, 24);
  return SyncMeta(
    ownerUserId: ownerUserId,
    updatedAt: now,
    updatedByDevice: 'device',
    hlc: Hlc(
      wallMillis: now.millisecondsSinceEpoch,
      counter: 0,
      nodeId: 'device',
    ),
  );
}
