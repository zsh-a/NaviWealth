import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/execution/data/execution_repository.dart';
import 'package:naviwealth/features/execution/data/providers.dart';
import 'package:naviwealth/features/execution/domain/execution_models.dart';
import 'package:naviwealth/features/execution/ui/execution_detail_page.dart';
import 'package:naviwealth/features/execution/ui/execution_widgets.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../../core/persistence/test_database.dart';

void main() {
  testWidgets(
    'action timeline lazily renders and loads records older than the previous 100-row cutoff',
    (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final db = makeTestDatabase();
      addTearDown(db.close);
      final repo = ExecutionRepository(db: db, outbox: InMemoryOutboxStore());
      final now = DateTime.utc(2026);
      final sync = SyncMeta(
        ownerUserId: 'owner',
        updatedAt: now,
        updatedByDevice: 'device',
        hlc: Hlc.zero('device'),
      );
      await repo.upsertAction(
        ExecutionAction(
          id: 'a',
          title: 'Action history',
          createdAt: now,
          sync: sync,
        ),
      );
      for (var i = 0; i < 125; i++) {
        await repo.recordProgress(
          ExecutionProgressEntry(
            id: 'p$i',
            actionId: 'a',
            kind: ExecutionProgressKind.checkin,
            note: 'History record $i',
            createdAt: now.add(Duration(minutes: i)),
            sync: sync,
          ),
        );
      }
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            executionRepositoryProvider.overrideWith((_) async => repo),
            executionOwnerUserIdProvider.overrideWith((_) async => 'owner'),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: FTheme(
              data: FTheme.neutral.light.desktop,
              child: const ExecutionActionDetailPage(actionId: 'a'),
            ),
          ),
        ),
      );
      await _settle(tester);
      expect(
        find.byType(ExecutionProgressCard).evaluate().length,
        lessThan(30),
      );
      expect(find.text('125'), findsOneWidget);
      for (var batch = 0; batch < 4; batch++) {
        for (
          var scroll = 0;
          scroll < 15 &&
              find.text('Load more').hitTestable().evaluate().isEmpty;
          scroll++
        ) {
          await tester.drag(
            find.byType(CustomScrollView).first,
            const Offset(0, -3000),
          );
          await _settle(tester);
        }
        expect(find.text('Load more').hitTestable(), findsOneWidget);
        await tester.tap(find.text('Load more'));
        await _settle(tester);
      }
      for (
        var scroll = 0;
        scroll < 10 && find.text('History record 0').evaluate().isEmpty;
        scroll++
      ) {
        await tester.drag(
          find.byType(CustomScrollView).first,
          const Offset(0, -3000),
        );
        await _settle(tester);
      }
      expect(find.text('History record 0'), findsOneWidget);
      expect(
        find.byType(ExecutionProgressCard).evaluate().length,
        lessThan(30),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}
