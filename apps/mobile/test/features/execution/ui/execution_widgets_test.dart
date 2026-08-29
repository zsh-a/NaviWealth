import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/lifeos/action_outcome.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/theme/app_theme.dart';
import 'package:naviwealth/features/execution/data/providers.dart';
import 'package:naviwealth/features/execution/domain/execution_models.dart';
import 'package:naviwealth/features/execution/ui/execution_detail_page.dart';
import 'package:naviwealth/features/execution/ui/execution_widgets.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  test('overview snapshot counts execution pressure', () {
    final now = DateTime.utc(2026, 6, 8, 9);
    final blocked = _action(
      id: 'blocked',
      status: ExecutionActionStatus.blocked,
    );
    final high = _action(
      id: 'high',
      priority: ExecutionPriority.high,
      dueAt: now.add(const Duration(days: 2)),
    );
    final due = _action(
      id: 'due',
      dueAt: now.subtract(const Duration(days: 1)),
    );
    final backlog = _action(id: 'backlog');
    final done = _action(id: 'done', status: ExecutionActionStatus.done);

    final snapshot = ExecutionOverviewSnapshot.fromLists(
      todayActions: [blocked, due],
      openActions: [blocked, high, due, backlog, done],
      plans: [
        ExecutionPlan(
          id: 'proj-1',
          title: 'Plan',
          createdAt: now,
          sync: _sync(),
        ),
      ],
      recentProgress: [
        ExecutionProgressEntry(
          id: 'p1',
          note: 'Recent',
          kind: ExecutionProgressKind.checkin,
          createdAt: now.subtract(const Duration(days: 3)),
          sync: _sync(),
        ),
        ExecutionProgressEntry(
          id: 'p2',
          note: 'Old',
          kind: ExecutionProgressKind.checkin,
          createdAt: now.subtract(const Duration(days: 9)),
          sync: _sync(),
        ),
      ],
      now: now,
    );

    expect(snapshot.todayCount, 2);
    expect(snapshot.blockedCount, 1);
    expect(snapshot.openCount, 4);
    expect(snapshot.backlogCount, 1);
    expect(snapshot.highPriorityCount, 1);
    expect(snapshot.dueCount, 1);
    expect(snapshot.activePlanCount, 1);
    expect(snapshot.recentProgressCount, 1);
  });

  test('filteredExecutionActions applies selected focus lens', () {
    final now = DateTime.utc(2026, 6, 8, 9);
    final today = _action(id: 'today');
    final blocked = _action(
      id: 'blocked',
      status: ExecutionActionStatus.blocked,
    );
    final high = _action(id: 'high', priority: ExecutionPriority.high);
    final due = _action(
      id: 'due',
      dueAt: now.subtract(const Duration(days: 1)),
    );
    final backlog = _action(id: 'backlog');
    final open = [today, blocked, high, due, backlog];

    expect(
      filteredExecutionActions(
        filter: ExecutionTodayFilter.today,
        todayActions: [today],
        openActions: open,
      ),
      [today],
    );
    expect(
      filteredExecutionActions(
        filter: ExecutionTodayFilter.blocked,
        todayActions: [today],
        openActions: open,
      ),
      [blocked],
    );
  });

  test('execution relation labels resolve known rows and fall back to ids', () {
    expect(
      executionPlanRelationLabel([
        ExecutionPlan(
          id: 'proj-1',
          title: 'Execution polish',
          createdAt: DateTime.utc(2026, 6, 1),
          sync: _sync(),
        ),
      ], 'proj-1'),
      'Execution polish',
    );
    expect(executionPlanRelationLabel(const [], null), isNull);
  });

  test('execution relation map preserves labels outside active lists', () {
    final relations = ExecutionRelations(
      actions: const {},
      plans: {
        'proj-done': ExecutionPlan(
          id: 'proj-done',
          title: 'Completed execution migration',
          status: ExecutionPlanStatus.completed,
          createdAt: DateTime.utc(2026, 6, 1),
          sync: _sync(),
        ),
      },
    );

    expect(relations.planLabel('proj-done'), 'Completed execution migration');
    expect(relations.planLabel('missing-plan'), 'missing-plan');
  });

  testWidgets('overview strip exposes tappable action filters', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var selected = ExecutionTodayFilter.today;
    const snapshot = ExecutionOverviewSnapshot(
      todayCount: 3,
      blockedCount: 1,
      openCount: 6,
      backlogCount: 2,
      highPriorityCount: 2,
      dueCount: 1,
      activePlanCount: 4,
      recentProgressCount: 5,
    );

    await tester.pumpWidget(
      _wrap(
        StatefulBuilder(
          builder: (context, setState) => ExecutionOverviewStrip(
            snapshot: snapshot,
            selectedFilter: selected,
            onFilterChanged: (filter) {
              setState(() => selected = filter);
            },
          ),
        ),
      ),
    );

    expect(find.textContaining('Today'), findsOneWidget);
    expect(find.textContaining('Open'), findsNothing);
    expect(find.textContaining('Blocked'), findsOneWidget);
    expect(find.textContaining('7d progress'), findsNothing);

    await tester.tap(find.textContaining('Today').last);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Blocked'));
    await tester.pumpAndSettle();

    expect(selected, ExecutionTodayFilter.blocked);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('overview hides zero summary-only metrics', (tester) async {
    const snapshot = ExecutionOverviewSnapshot(
      todayCount: 0,
      blockedCount: 0,
      openCount: 0,
      backlogCount: 0,
      highPriorityCount: 0,
      dueCount: 0,
      activePlanCount: 0,
      recentProgressCount: 0,
    );

    await tester.pumpWidget(
      _wrap(
        ExecutionOverviewStrip(
          snapshot: snapshot,
          selectedFilter: ExecutionTodayFilter.today,
          onFilterChanged: (_) {},
        ),
      ),
    );

    expect(find.text('Plans'), findsNothing);
    expect(find.textContaining('7d progress'), findsNothing);
    expect(find.textContaining('Today'), findsOneWidget);
    expect(find.textContaining('Due'), findsNothing);
  });

  testWidgets('action card exposes edit and status actions', (tester) async {
    var edited = false;
    var started = false;
    var blocked = false;
    var resumed = false;
    var done = false;
    var dropped = false;
    var progressed = false;
    var sourceOpened = false;

    await tester.pumpWidget(
      _wrap(
        ExecutionActionCard(
          action: _action(
            priority: ExecutionPriority.high,
            dueAt: DateTime.utc(2026, 1, 1),
            scheduledFor: DateTime.utc(2026, 6, 3),
            planId: 'proj-1',
            source: const ExecutionSourceRef(labelSnapshot: 'Budget alert'),
          ),
          planLabel: 'Execution polish',
          onSourceOpen: () => sourceOpened = true,
          onEdit: () => edited = true,
          onStart: () => started = true,
          onBlock: () => blocked = true,
          onResume: () => resumed = true,
          onDone: () => done = true,
          onDrop: () => dropped = true,
          onRecordProgress: () => progressed = true,
        ),
      ),
    );

    expect(find.text('Review budget delta'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
    expect(find.textContaining('Overdue'), findsOneWidget);
    expect(find.textContaining('Scheduled'), findsOneWidget);
    expect(find.text('Belongs to: Execution polish'), findsOneWidget);
    expect(find.text('Budget alert'), findsOneWidget);

    await tester.tap(find.text('Budget alert'));
    await tester.pump();
    expect(sourceOpened, isTrue);

    await tester.tap(find.byIcon(FLucideIcons.play));
    await tester.pump(const Duration(milliseconds: 200));

    Future<void> selectMoreAction(String label) async {
      await tester.tap(find.byIcon(FLucideIcons.ellipsis));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    await selectMoreAction('Edit Action');
    await selectMoreAction('New Update');
    await selectMoreAction('Block');
    await selectMoreAction('Done');
    await selectMoreAction('Drop');

    expect(edited, isTrue);
    expect(started, isTrue);
    expect(blocked, isTrue);
    expect(resumed, isFalse);
    expect(done, isTrue);
    expect(dropped, isTrue);
    expect(progressed, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('compact action card defers secondary context', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ExecutionActionCard(
          action: _action(
            priority: ExecutionPriority.high,
            dueAt: DateTime.utc(2026, 1, 1),
            scheduledFor: DateTime.utc(2026, 1, 2),
            planId: 'proj-1',
            source: const ExecutionSourceRef(labelSnapshot: 'Budget alert'),
          ),
          compact: true,
          planLabel: 'Execution polish',
          onSourceOpen: () {},
          onEdit: () {},
          onStart: () {},
          onBlock: () {},
          onResume: () {},
          onDone: () {},
          onDrop: () {},
          onRecordProgress: () {},
        ),
      ),
    );

    expect(find.text('Review budget delta'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
    expect(find.text('Overdue 1/1/2026'), findsOneWidget);
    expect(find.textContaining('Scheduled'), findsNothing);
    expect(find.textContaining('Plan:'), findsNothing);
    expect(find.text('Budget alert'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('action card shows a single busy affordance', (tester) async {
    var edited = false;

    await tester.pumpWidget(
      _wrap(
        ExecutionActionCard(
          action: _action(priority: ExecutionPriority.high),
          busy: true,
          onEdit: () => edited = true,
          onStart: () {},
          onBlock: () {},
          onResume: () {},
          onDone: () {},
          onDrop: () {},
          onRecordProgress: () {},
        ),
      ),
    );

    expect(find.byType(FCircularProgress), findsOneWidget);
    expect(find.byIcon(FLucideIcons.pencil), findsNothing);
    expect(find.byIcon(FLucideIcons.messageSquareText), findsNothing);

    expect(edited, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('action card supports a read-only detail presentation', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        ExecutionActionCard(
          action: _action(),
          showActions: false,
          onEdit: () {},
          onStart: () {},
          onBlock: () {},
          onResume: () {},
          onDone: () {},
          onDrop: () {},
          onRecordProgress: () {},
        ),
      ),
    );

    expect(find.text('Review budget delta'), findsOneWidget);
    expect(find.byIcon(FLucideIcons.play), findsNothing);
    expect(find.byIcon(FLucideIcons.ellipsis), findsNothing);
  });

  testWidgets('closed action card renders the cross-domain outcome summary', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        ExecutionActionCard(
          action: _action(status: ExecutionActionStatus.done),
          outcome: ActionOutcomeSummary(
            status: ActionOutcomeStatus.signalCleared,
            sourceLabel: 'HealthOS',
            sourceCapturedAt: DateTime.utc(2026, 7, 16),
            evaluatedAt: DateTime.utc(2026, 7, 18),
          ),
          showActions: false,
          onEdit: () {},
          onStart: () {},
          onBlock: () {},
          onResume: () {},
          onDone: () {},
          onDrop: () {},
          onRecordProgress: () {},
        ),
      ),
    );

    expect(find.text('HealthOS: signal no longer detected'), findsOneWidget);
  });

  testWidgets(
    'closed action card exposes resume without block or done actions',
    (tester) async {
      var resumed = false;
      var blocked = false;
      var done = false;
      var dropped = false;

      await tester.pumpWidget(
        _wrap(
          ExecutionActionCard(
            action: _action(status: ExecutionActionStatus.done),
            onEdit: () {},
            onStart: () {},
            onBlock: () => blocked = true,
            onResume: () => resumed = true,
            onDone: () => done = true,
            onDrop: () => dropped = true,
            onRecordProgress: () {},
          ),
        ),
      );

      expect(find.text('Done'), findsOneWidget);
      expect(find.byIcon(FLucideIcons.rotateCcw), findsOneWidget);
      expect(find.byIcon(FLucideIcons.pause), findsNothing);
      expect(find.byIcon(FLucideIcons.check), findsNothing);
      expect(find.byIcon(FLucideIcons.archive), findsNothing);

      await tester.tap(find.byIcon(FLucideIcons.rotateCcw));
      await tester.pump(const Duration(milliseconds: 200));

      expect(resumed, isTrue);
      expect(blocked, isFalse);
      expect(done, isFalse);
      expect(dropped, isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 200));
    },
  );

  testWidgets('plan card renders lifecycle fields and edit action', (
    tester,
  ) async {
    var created = false;
    var edited = false;
    var paused = false;
    var resumed = false;
    var completed = false;
    var archived = false;
    var progressed = false;
    var opened = false;

    await tester.pumpWidget(
      _wrap(
        ExecutionPlanCard(
          plan: ExecutionPlan(
            id: 'proj-1',
            title: 'Ship execution loop',
            description: 'Action and review workflow',
            status: ExecutionPlanStatus.active,
            horizon: ExecutionHorizon.quarter,
            createdAt: DateTime.utc(2026, 6, 1),
            sync: _sync(),
          ),
          openActionCount: 3,
          blockedActionCount: 1,
          onCreateAction: () => created = true,
          onEdit: () => edited = true,
          onPause: () => paused = true,
          onResume: () => resumed = true,
          onComplete: () => completed = true,
          onArchive: () => archived = true,
          onRecordProgress: () => progressed = true,
          onOpen: () => opened = true,
        ),
      ),
    );

    expect(find.text('Ship execution loop'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Actions: 3'), findsOneWidget);
    expect(find.text('Blocked: 1'), findsOneWidget);

    await tester.tap(find.text('Ship execution loop'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(opened, isTrue);

    await tester.tap(find.byIcon(FLucideIcons.plus));
    await tester.pump(const Duration(milliseconds: 200));

    Future<void> selectMoreAction(String label) async {
      await tester.tap(find.byIcon(FLucideIcons.ellipsis));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    await selectMoreAction('Edit Plan');
    await selectMoreAction('New Update');
    await selectMoreAction('Pause');
    await selectMoreAction('Complete');
    await selectMoreAction('Archive');

    expect(created, isTrue);
    expect(edited, isTrue);
    expect(paused, isTrue);
    expect(resumed, isFalse);
    expect(completed, isTrue);
    expect(archived, isTrue);
    expect(progressed, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('plan target shows overdue state', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ExecutionPlanCard(
          plan: ExecutionPlan(
            id: 'overdue-plan',
            title: 'Overdue plan',
            targetDate: DateTime.utc(2026, 1, 1),
            createdAt: DateTime.utc(2026, 6, 1),
            sync: _sync(),
          ),
          onCreateAction: () {},
          onEdit: () {},
          onPause: () {},
          onResume: () {},
          onComplete: () {},
          onArchive: () {},
          onRecordProgress: () {},
        ),
      ),
    );

    expect(find.text('Overdue 1/1/2026'), findsOneWidget);
    expect(find.textContaining('Target'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('plan detail renders scoped actions and progress', (
    tester,
  ) async {
    final plan = ExecutionPlan(
      id: 'proj-detail',
      title: 'Canonical plan detail',
      description: 'Plan-owned execution context',
      createdAt: DateTime.utc(2026, 6, 1),
      sync: _sync(),
    );
    final action = _action(
      id: 'action-detail',
      title: 'Scoped plan action',
      planId: plan.id,
    );
    final progress = ExecutionProgressEntry(
      id: 'progress-detail',
      planId: plan.id,
      kind: ExecutionProgressKind.checkin,
      note: 'Scoped plan progress',
      createdAt: DateTime.utc(2026, 6, 2),
      sync: _sync(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          executionPlanDetailProvider(plan.id)
              .overrideWith((ref) => Stream.value(plan)),
          executionActionsForPlanProvider(plan.id)
              .overrideWith((ref) => Stream.value([action])),
          executionProgressForPlanProvider(plan.id)
              .overrideWith((ref) => Stream.value([progress])),
          executionActionRelationsProvider.overrideWith(
            (ref) async => ExecutionRelations(
              actions: {action.id: action},
              plans: {plan.id: plan},
            ),
          ),
        ],
        child: _wrap(ExecutionPlanDetailPage(planId: plan.id)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Canonical plan detail'), findsOneWidget);
    expect(find.text('Scoped plan action'), findsOneWidget);
    expect(find.text('Scoped plan progress'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closed plan card exposes resume without close actions', (
    tester,
  ) async {
    var paused = false;
    var resumed = false;
    var completed = false;

    await tester.pumpWidget(
      _wrap(
        ExecutionPlanCard(
          plan: ExecutionPlan(
            id: 'proj-closed',
            title: 'Closed plan',
            status: ExecutionPlanStatus.completed,
            createdAt: DateTime.utc(2026, 6, 1),
            completedAt: DateTime.utc(2026, 6, 2),
            sync: _sync(),
          ),
          onCreateAction: () {},
          onEdit: () {},
          onPause: () => paused = true,
          onResume: () => resumed = true,
          onComplete: () => completed = true,
          onArchive: () {},
          onRecordProgress: () {},
        ),
      ),
    );

    expect(find.text('Closed plan'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.byIcon(FLucideIcons.play), findsOneWidget);
    expect(find.byIcon(FLucideIcons.pause), findsNothing);
    expect(find.byIcon(FLucideIcons.check), findsNothing);
    expect(find.byIcon(FLucideIcons.plus), findsNothing);

    await tester.tap(find.byIcon(FLucideIcons.play));
    await tester.pump(const Duration(milliseconds: 200));

    expect(resumed, isTrue);
    expect(paused, isFalse);
    expect(completed, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('progress card renders relation context badges', (tester) async {
    var deleted = false;
    var edited = false;
    var openedAction = false;

    await tester.pumpWidget(
      _wrap(
        ExecutionProgressCard(
          entry: ExecutionProgressEntry(
            id: 'p1',
            actionId: 'a1',
            planId: 'proj-1',
            kind: ExecutionProgressKind.completion,
            note: 'Completed proposal coverage.',
            createdAt: DateTime.utc(2026, 6, 1),
            sync: _sync(),
          ),
          actionLabel: 'Review budget delta',
          planLabel: 'Execution polish',
          onEdit: () => edited = true,
          onDelete: () => deleted = true,
          onActionOpen: () => openedAction = true,
        ),
      ),
    );

    expect(find.text('Completion'), findsOneWidget);
    expect(find.text('Completed proposal coverage.'), findsOneWidget);
    expect(find.text('Action: Review budget delta'), findsOneWidget);
    expect(find.textContaining('Plan: Execution polish'), findsNothing);

    await tester.tap(find.text('Action: Review budget delta'));
    await tester.pump();
    expect(openedAction, isTrue);

    await tester.tap(find.byIcon(FLucideIcons.ellipsis));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit Update'));
    await tester.pumpAndSettle();
    expect(edited, isTrue);

    await tester.tap(find.byIcon(FLucideIcons.ellipsis));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(deleted, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });
}

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: FTheme(data: FTheme.neutral.light.desktop, child: child),
  );
}

ExecutionAction _action({
  String id = 'a1',
  String title = 'Review budget delta',
  ExecutionActionStatus status = ExecutionActionStatus.todo,
  ExecutionPriority priority = ExecutionPriority.normal,
  DateTime? dueAt,
  DateTime? scheduledFor,
  String? planId,
  ExecutionSourceRef source = const ExecutionSourceRef(),
}) {
  return ExecutionAction(
    id: id,
    title: title,
    status: status,
    priority: priority,
    dueAt: dueAt,
    scheduledFor: scheduledFor,
    planId: planId,
    source: source,
    createdAt: DateTime.utc(2026, 6, 1),
    sync: _sync(),
  );
}

SyncMeta _sync() {
  final now = DateTime.utc(2026, 6, 1, 8);
  return SyncMeta(
    ownerUserId: 'u-test',
    updatedAt: now,
    updatedByDevice: 'dev-test',
    hlc: Hlc(
      wallMillis: now.millisecondsSinceEpoch,
      counter: 0,
      nodeId: 'dev-test',
    ),
  );
}
