import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/execution/data/execution_repository.dart';
import 'package:naviwealth/features/execution/data/providers.dart';
import 'package:naviwealth/features/execution/domain/execution_models.dart';
import 'package:naviwealth/features/execution/ui/execution_action_card_controller.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../../core/persistence/test_database.dart';
import '../../finance/data/repositories/_stub_stamper.dart';

class _DelayedRepository extends ExecutionRepository {
  _DelayedRepository({required super.db, required super.outbox});
  Completer<void>? gate;
  int writes = 0;
  @override
  Future<void> updateActionStatus({
    required ExecutionAction action,
    required ExecutionActionStatus status,
    required SyncMeta sync,
    String? progressId,
    String? progressNote,
  }) async {
    writes++;
    await gate?.future;
    await super.updateActionStatus(
      action: action,
      status: status,
      sync: sync,
      progressId: progressId,
      progressNote: progressNote,
    );
  }
}

void main() {
  testWidgets(
    'block reason remains mounted through failure and commits with progress on retry',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final db = makeTestDatabase();
      addTearDown(db.close);
      final repository = _DelayedRepository(
        db: db,
        outbox: InMemoryOutboxStore(),
      );
      final action = ExecutionAction(
        id: 'action',
        title: 'Follow through',
        status: ExecutionActionStatus.doing,
        createdAt: DateTime.utc(2026),
        sync: SyncMeta(
          ownerUserId: 'user',
          updatedAt: DateTime.utc(2026),
          updatedByDevice: 'dev',
          hlc: Hlc.zero('dev'),
        ),
      );
      await repository.upsertAction(action);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            executionRepositoryProvider.overrideWith((_) async => repository),
            mutationStamperProvider.overrideWith(
              (_) async => makeStubStamper(userId: 'user'),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (_, child) =>
                FTheme(data: FTheme.neutral.light.desktop, child: child!),
            home: Scaffold(
              body: ExecutionActionCardController(
                action: action,
                onEdit: () {},
                onRecordProgress: () {},
                doneProgressNote: 'Done',
                droppedProgressNote: 'Dropped',
              ),
            ),
          ),
        ),
      );
      // Open the card's overflow menu, then capture a blocker.
      final controller = tester.widget<ExecutionActionCardController>(
        find.byType(ExecutionActionCardController),
      );
      expect(controller.action.status, ExecutionActionStatus.doing);
      await tester.tap(find.byIcon(FLucideIcons.ellipsis).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Block'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(EditableText).first,
        'Waiting for a reply',
      );
      await tester.pump();
      repository.gate = Completer<void>();
      await tester.tap(find.text('Block').last);
      await _pump(tester);
      expect(repository.writes, 1);
      await tester.binding.handlePopRoute();
      await _pump(tester);
      expect(find.text('Waiting for a reply'), findsOneWidget);
      expect(find.text('Discard changes?'), findsNothing);
      repository.gate!.completeError(StateError('storage failed'));
      await _pump(tester);
      expect(find.byType(AppStatusBanner), findsOneWidget);
      expect(find.text('Waiting for a reply'), findsOneWidget);
      repository.gate = null;
      await tester.tap(find.text('Block').last);
      await _pump(tester);
      expect(repository.writes, 2);
      expect(find.byType(EditableText), findsNothing);
      expect(
        (await repository.findAction(
          ownerUserId: 'user',
          id: action.id,
        ))?.status,
        ExecutionActionStatus.blocked,
      );
      final entries = await repository.listRecentProgress(ownerUserId: 'user');
      expect(entries, hasLength(1));
      expect(entries.single.note, 'Waiting for a reply');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}

Future<void> _pump(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 75), EnginePhase.paint);
  }
}
