import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/theme/app_theme.dart';
import 'package:naviwealth/features/execution/data/execution_repository.dart';
import 'package:naviwealth/features/execution/data/providers.dart';
import 'package:naviwealth/features/execution/domain/execution_models.dart';
import 'package:naviwealth/features/execution/ui/execution_review_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../../core/persistence/test_database.dart';
import '../../finance/data/repositories/_stub_stamper.dart';

void main() {
  testWidgets('review renders concrete attention rows from domain state', (
    tester,
  ) async {
    final now = DateTime.now();
    final action = ExecutionAction(
      id: 'blocked-action',
      title: 'Prepare quarterly review',
      note: 'Waiting for the final statement.',
      status: ExecutionActionStatus.blocked,
      dueAt: now.subtract(const Duration(days: 1)),
      createdAt: now.subtract(const Duration(days: 8)),
      sync: _sync(now.subtract(const Duration(days: 8))),
    );

    await tester.pumpWidget(
      _wrap(
        const ExecutionReviewPage(),
        overrides: _reviewOverrides(actions: <ExecutionAction>[action]),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Needs attention')).dy,
      lessThan(tester.getTopLeft(find.text('This week')).dy),
    );
    expect(find.text('Prepare quarterly review'), findsOneWidget);
    expect(find.textContaining('Blocked work'), findsOneWidget);
    expect(find.textContaining('Due work'), findsOneWidget);
    expect(find.textContaining('Agent'), findsNothing);

    await tester.tap(find.text('Prepare quarterly review'));
    await tester.pumpAndSettle();

    expect(find.text('Evidence'), findsOneWidget);
    expect(find.text('Waiting for the final statement.'), findsOneWidget);
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
        overrides: _reviewOverrides(
          progress: <ExecutionProgressEntry>[recent, old],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recent activity · 1'), findsOneWidget);
    expect(find.text('Recent execution progress'), findsNothing);
    expect(find.text('Old execution blocker'), findsNothing);

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

    await tester.pumpWidget(
      _wrap(
        const ExecutionReviewPage(),
        overrides: [
          ..._reviewOverrides(
            projects: <ExecutionProject>[project],
            commitments: <ExecutionCommitment>[commitment],
          ),
          executionRepositoryProvider.overrideWith((_) async => repository),
          executionOwnerUserIdProvider.overrideWith((_) async => 'user-1'),
          mutationStamperProvider.overrideWith(
            (_) async => makeStubStamper(userId: 'user-1'),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Review 2 missing next actions'));
    await tester.pumpAndSettle();

    expect(find.text('Launch project'), findsWidgets);
    expect(find.text('Weekly planning'), findsWidgets);
    expect(find.text('Create 2 next actions'), findsOneWidget);

    await tester.tap(find.text('Weekly planning').last);
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

List<Override> _reviewOverrides({
  List<ExecutionAction> actions = const <ExecutionAction>[],
  List<ExecutionProject> projects = const <ExecutionProject>[],
  List<ExecutionCommitment> commitments = const <ExecutionCommitment>[],
  List<ExecutionProgressEntry> progress = const <ExecutionProgressEntry>[],
  List<ExecutionAction> closedActions = const <ExecutionAction>[],
}) => <Override>[
  executionOpenActionsProvider.overrideWith((ref) => Stream.value(actions)),
  executionProjectsProvider.overrideWith((ref) => Stream.value(projects)),
  executionCommitmentsProvider.overrideWith((ref) => Stream.value(commitments)),
  executionRecentProgressProvider.overrideWith((ref) => Stream.value(progress)),
  executionClosedActionsProvider.overrideWith(
    (ref) => Stream.value(closedActions),
  ),
  executionReviewRelationsProvider.overrideWith(
    (ref) async => ExecutionReviewRelations(
      actions: {for (final action in actions) action.id: action},
      projects: {for (final project in projects) project.id: project},
      commitments: {
        for (final commitment in commitments) commitment.id: commitment,
      },
    ),
  ),
];

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
