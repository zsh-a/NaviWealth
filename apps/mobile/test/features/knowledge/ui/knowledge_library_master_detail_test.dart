import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/shell/master_detail_layout.dart';
import 'package:naviwealth/core/shell/selection_query.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_repository.dart';
import 'package:naviwealth/features/knowledge/data/providers.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';
import 'package:naviwealth/features/knowledge/ui/knowledge_library_page.dart';
import 'package:naviwealth/features/knowledge/ui/knowledge_note_detail_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/test_database.dart';

late SharedPreferences _prefs;
late KnowledgeRepository _repository;

final _note = KnowledgeNote(
  id: 'note-1',
  title: 'Library note',
  bodyMd: 'Body',
  tags: const <String>['work'],
  createdAt: DateTime.utc(2026, 8, 30),
  sync: SyncMeta(
    ownerUserId: 'knowledge-md-user',
    updatedAt: DateTime.utc(2026, 8, 30),
    updatedByDevice: 'knowledge-md-device',
    hlc: Hlc.zero('knowledge-md-device'),
  ),
);

Widget _wrap({required double contentWidth}) {
  final router = GoRouter(
    initialLocation: '/knowledge/library',
    routes: [
      GoRoute(
        path: '/knowledge/library',
        builder: (_, _) => Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: contentWidth,
            child: const KnowledgeLibraryPage(),
          ),
        ),
      ),
      GoRoute(
        path: '/knowledge/library/note/:id',
        builder: (_, _) => const Text('pushed-note-detail'),
      ),
      GoRoute(
        path: '/knowledge/library/decision/:id',
        builder: (_, _) => const Text('pushed-decision-detail'),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(_prefs),
      knowledgeRepositoryProvider.overrideWith((_) async => _repository),
      knowledgeOwnerUserIdProvider.overrideWith(
        (_) async => _note.sync.ownerUserId,
      ),
      knowledgeNotesProvider.overrideWith((_) => Stream.value([_note])),
      knowledgeDecisionsProvider.overrideWith(
        (_) => Stream.value(const <KnowledgeDecision>[]),
      ),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      routerConfig: router,
      builder: (context, child) =>
          FTheme(data: FTheme.neutral.light.desktop, child: child!),
    ),
  );
}

Future<void> _setSurface(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _settlePaint(WidgetTester tester) async {
  for (var index = 0; index < 12; index++) {
    await tester.pump(const Duration(milliseconds: 75), EnginePhase.paint);
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
    final database = makeTestDatabase();
    addTearDown(database.close);
    _repository = KnowledgeRepository(
      db: database,
      outbox: InMemoryOutboxStore(),
    );
    await _repository.upsertNote(_note);
  });

  testWidgets('wide layout opens the note detail in the side pane', (
    tester,
  ) async {
    await _setSurface(tester, 1280);
    await tester.pumpWidget(_wrap(contentWidth: 1100));
    await _settlePaint(tester);

    expect(find.byType(MasterDetailLayout), findsOneWidget);
    await tester.tap(find.text('Library note'));
    await _settlePaint(tester);

    expect(
      selectedQueryOf(tester.element(find.byType(KnowledgeLibraryPage))),
      'note:note-1',
    );
    expect(find.byType(KnowledgeNoteDetailPage), findsOneWidget);
    expect(find.text('pushed-note-detail'), findsNothing);
    await _disposeWidget(tester);
  });

  testWidgets('narrow layout pushes the note detail route', (tester) async {
    await _setSurface(tester, 1600);
    await tester.pumpWidget(_wrap(contentWidth: 900));
    await _settlePaint(tester);

    expect(find.byType(MasterDetailLayout), findsNothing);
    await tester.tap(find.text('Library note'));
    await _settlePaint(tester);

    expect(find.byType(KnowledgeNoteDetailPage), findsNothing);
    expect(find.text('pushed-note-detail'), findsOneWidget);
    await _disposeWidget(tester);
  });
}

Future<void> _disposeWidget(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}
