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
import 'package:naviwealth/features/execution/ui/execution_commitments_page.dart';
import 'package:naviwealth/features/execution/ui/execution_lifecycle_card_controller.dart';
import 'package:naviwealth/features/execution/ui/execution_today_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../../core/persistence/test_database.dart';
import '../../finance/data/repositories/_stub_stamper.dart';

void main() {
  testWidgets('Today exposes unscheduled backlog as a first-class lens', (
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

    expect(find.textContaining('Backlog 1'), findsOneWidget);
    expect(find.text('Plan the next release'), findsNothing);

    await tester.tap(find.textContaining('Backlog 1'));
    await tester.pumpAndSettle();

    expect(find.text('Plan the next release'), findsOneWidget);
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

    expect(find.text('Open actions'), findsOneWidget);
    expect(find.text('Capture standalone follow-up'), findsOneWidget);
    expect(find.text('No active work'), findsNothing);
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
  List<ExecutionProject> projects = const [],
  List<ExecutionCommitment> commitments = const [],
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
      (ref) => Stream.value(const <ExecutionProject>[]),
    ),
    executionCommitmentsProvider.overrideWith(
      (ref) => Stream.value(commitments),
    ),
    executionClosedCommitmentsProvider.overrideWith(
      (ref) => Stream.value(const <ExecutionCommitment>[]),
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
