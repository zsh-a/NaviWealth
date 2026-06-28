import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/theme/app_theme.dart';
import 'package:naviwealth/features/execution/data/providers.dart';
import 'package:naviwealth/features/execution/domain/execution_models.dart';
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
      projects: [
        ExecutionProject(
          id: 'proj-1',
          title: 'Project',
          createdAt: now,
          sync: _sync(),
        ),
      ],
      commitments: [
        ExecutionCommitment(
          id: 'commit-1',
          title: 'Commitment',
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
    expect(snapshot.backlogCount, 1);
    expect(snapshot.highPriorityCount, 1);
    expect(snapshot.dueCount, 1);
    expect(snapshot.activeProjectCount, 1);
    expect(snapshot.activeCommitmentCount, 1);
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
        filter: ExecutionTodayFilter.focus,
        todayActions: [today],
        openActions: open,
        now: now,
      ),
      [today],
    );
    expect(
      filteredExecutionActions(
        filter: ExecutionTodayFilter.blocked,
        todayActions: [today],
        openActions: open,
        now: now,
      ),
      [blocked],
    );
    expect(
      filteredExecutionActions(
        filter: ExecutionTodayFilter.backlog,
        todayActions: [today],
        openActions: open,
        now: now,
      ),
      [today, backlog],
    );
    expect(
      filteredExecutionActions(
        filter: ExecutionTodayFilter.high,
        todayActions: [today],
        openActions: open,
        now: now,
      ),
      [high],
    );
    expect(
      filteredExecutionActions(
        filter: ExecutionTodayFilter.due,
        todayActions: [today],
        openActions: open,
        now: now,
      ),
      [due],
    );
  });

  test('execution relation labels resolve known rows and fall back to ids', () {
    expect(
      executionProjectRelationLabel([
        ExecutionProject(
          id: 'proj-1',
          title: 'Execution polish',
          createdAt: DateTime.utc(2026, 6, 1),
          sync: _sync(),
        ),
      ], 'proj-1'),
      'Execution polish',
    );
    expect(
      executionCommitmentRelationLabel([
        ExecutionCommitment(
          id: 'commit-1',
          title: 'Weekly review',
          createdAt: DateTime.utc(2026, 6, 1),
          sync: _sync(),
        ),
      ], 'missing-commitment'),
      'missing-commitment',
    );
    expect(executionProjectRelationLabel(const [], null), isNull);
  });

  test('execution relation map preserves labels outside active lists', () {
    final relations = ExecutionRelations(
      actions: const {},
      projects: {
        'proj-done': ExecutionProject(
          id: 'proj-done',
          title: 'Completed execution migration',
          status: ExecutionProjectStatus.completed,
          createdAt: DateTime.utc(2026, 6, 1),
          sync: _sync(),
        ),
      },
      commitments: {
        'commit-archived': ExecutionCommitment(
          id: 'commit-archived',
          title: 'Archived weekly promise',
          status: ExecutionCommitmentStatus.archived,
          createdAt: DateTime.utc(2026, 6, 1),
          sync: _sync(),
        ),
      },
    );

    expect(
      relations.projectLabel('proj-done'),
      'Completed execution migration',
    );
    expect(
      relations.commitmentLabel('commit-archived'),
      'Archived weekly promise',
    );
    expect(relations.projectLabel('missing-project'), 'missing-project');
    expect(relations.commitmentLabel(null), isNull);
  });

  testWidgets('overview strip exposes tappable action filters', (tester) async {
    var selected = ExecutionTodayFilter.focus;
    const snapshot = ExecutionOverviewSnapshot(
      todayCount: 3,
      blockedCount: 1,
      backlogCount: 2,
      highPriorityCount: 2,
      dueCount: 1,
      activeProjectCount: 4,
      activeCommitmentCount: 2,
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

    expect(find.text('Focus'), findsOneWidget);
    expect(find.text('Backlog'), findsOneWidget);
    expect(find.text('Blocked'), findsOneWidget);
    expect(find.text('7d progress'), findsOneWidget);

    await tester.tap(find.text('Blocked'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(selected, ExecutionTodayFilter.blocked);

    await tester.tap(find.text('Backlog'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(selected, ExecutionTodayFilter.backlog);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('action card exposes edit and status actions', (tester) async {
    var edited = false;
    var started = false;
    var blocked = false;
    var resumed = false;
    var done = false;
    var dropped = false;
    var progressed = false;

    await tester.pumpWidget(
      _wrap(
        ExecutionActionCard(
          action: _action(
            priority: ExecutionPriority.high,
            projectId: 'proj-1',
            commitmentId: 'commit-1',
          ),
          projectLabel: 'Execution polish',
          commitmentLabel: 'Weekly review',
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
    expect(find.text('Project: Execution polish'), findsOneWidget);
    expect(find.text('Commitment: Weekly review'), findsOneWidget);

    await tester.tap(find.byIcon(FLucideIcons.pencil));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byIcon(FLucideIcons.messageSquareText));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byIcon(FLucideIcons.play));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byIcon(FLucideIcons.pause));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byIcon(FLucideIcons.check));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byIcon(FLucideIcons.archive));
    await tester.pump(const Duration(milliseconds: 200));

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

  testWidgets('project card renders lifecycle fields and edit action', (
    tester,
  ) async {
    var created = false;
    var edited = false;
    var paused = false;
    var resumed = false;
    var completed = false;
    var progressed = false;

    await tester.pumpWidget(
      _wrap(
        ExecutionProjectCard(
          project: ExecutionProject(
            id: 'proj-1',
            title: 'Ship execution loop',
            description: 'Action and review workflow',
            status: ExecutionProjectStatus.active,
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
          onRecordProgress: () => progressed = true,
        ),
      ),
    );

    expect(find.text('Ship execution loop'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Quarter'), findsOneWidget);
    expect(find.text('Actions: 3'), findsOneWidget);
    expect(find.text('Blocked: 1'), findsOneWidget);

    await tester.tap(find.byIcon(FLucideIcons.pause));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byIcon(FLucideIcons.check));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byIcon(FLucideIcons.messageSquareText));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byIcon(FLucideIcons.plus));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byIcon(FLucideIcons.pencil));
    await tester.pump(const Duration(milliseconds: 200));

    expect(created, isTrue);
    expect(edited, isTrue);
    expect(paused, isTrue);
    expect(resumed, isFalse);
    expect(completed, isTrue);
    expect(progressed, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('closed project card exposes resume without close actions', (
    tester,
  ) async {
    var paused = false;
    var resumed = false;
    var completed = false;

    await tester.pumpWidget(
      _wrap(
        ExecutionProjectCard(
          project: ExecutionProject(
            id: 'proj-closed',
            title: 'Closed project',
            status: ExecutionProjectStatus.completed,
            createdAt: DateTime.utc(2026, 6, 1),
            completedAt: DateTime.utc(2026, 6, 2),
            sync: _sync(),
          ),
          onCreateAction: () {},
          onEdit: () {},
          onPause: () => paused = true,
          onResume: () => resumed = true,
          onComplete: () => completed = true,
          onRecordProgress: () {},
        ),
      ),
    );

    expect(find.text('Closed project'), findsOneWidget);
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

  testWidgets('commitment card exposes create action and edit affordances', (
    tester,
  ) async {
    var created = false;
    var edited = false;
    var paused = false;
    var resumed = false;
    var completed = false;
    var progressed = false;

    await tester.pumpWidget(
      _wrap(
        ExecutionCommitmentCard(
          commitment: ExecutionCommitment(
            id: 'commit-1',
            title: 'Weekly review',
            description: 'Keep execution commitments current',
            status: ExecutionCommitmentStatus.paused,
            horizon: ExecutionHorizon.week,
            targetDate: DateTime.utc(2026, 6, 8),
            createdAt: DateTime.utc(2026, 6, 1),
            sync: _sync(),
          ),
          openActionCount: 2,
          blockedActionCount: 0,
          onCreateAction: () => created = true,
          onEdit: () => edited = true,
          onPause: () => paused = true,
          onResume: () => resumed = true,
          onComplete: () => completed = true,
          onRecordProgress: () => progressed = true,
        ),
      ),
    );

    expect(find.text('Weekly review'), findsOneWidget);
    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('Week'), findsOneWidget);
    expect(find.text('Actions: 2'), findsOneWidget);
    expect(find.text('Blocked: 0'), findsNothing);

    await tester.tap(find.byIcon(FLucideIcons.play));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byIcon(FLucideIcons.check));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byIcon(FLucideIcons.messageSquareText));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byIcon(FLucideIcons.plus));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byIcon(FLucideIcons.pencil));
    await tester.pump(const Duration(milliseconds: 200));

    expect(created, isTrue);
    expect(edited, isTrue);
    expect(paused, isFalse);
    expect(resumed, isTrue);
    expect(completed, isTrue);
    expect(progressed, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('progress card renders relation context badges', (tester) async {
    var deleted = false;

    await tester.pumpWidget(
      _wrap(
        ExecutionProgressCard(
          entry: ExecutionProgressEntry(
            id: 'p1',
            actionId: 'a1',
            projectId: 'proj-1',
            commitmentId: 'commit-1',
            kind: ExecutionProgressKind.completion,
            note: 'Completed proposal coverage.',
            createdAt: DateTime.utc(2026, 6, 1),
            sync: _sync(),
          ),
          actionLabel: 'Review budget delta',
          projectLabel: 'Execution polish',
          commitmentLabel: 'Weekly review',
          onDelete: () => deleted = true,
        ),
      ),
    );

    expect(find.text('Completion'), findsOneWidget);
    expect(find.text('Completed proposal coverage.'), findsOneWidget);
    expect(find.text('Action: Review budget delta'), findsOneWidget);
    expect(find.text('Project: Execution polish'), findsOneWidget);
    expect(find.text('Commitment: Weekly review'), findsOneWidget);

    await tester.tap(find.byIcon(FLucideIcons.trash2));
    await tester.pump(const Duration(milliseconds: 200));

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
    home: FTheme(data: FThemes.slate.light.desktop, child: child),
  );
}

ExecutionAction _action({
  String id = 'a1',
  String title = 'Review budget delta',
  ExecutionActionStatus status = ExecutionActionStatus.todo,
  ExecutionPriority priority = ExecutionPriority.normal,
  DateTime? dueAt,
  String? projectId,
  String? commitmentId,
}) {
  return ExecutionAction(
    id: id,
    title: title,
    status: status,
    priority: priority,
    dueAt: dueAt,
    projectId: projectId,
    commitmentId: commitmentId,
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
