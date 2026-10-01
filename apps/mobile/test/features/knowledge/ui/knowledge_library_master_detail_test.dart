import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/shell/master_detail_layout.dart';
import 'package:naviwealth/core/shell/selection_query.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_repository.dart';
import 'package:naviwealth/features/knowledge/data/providers.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';
import 'package:naviwealth/features/knowledge/ui/knowledge_library_page.dart';
import 'package:naviwealth/features/knowledge/ui/knowledge_note_detail_page.dart';
import 'package:naviwealth/features/knowledge/ui/widgets/knowledge_entry_tile.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/test_database.dart';
import '../../finance/data/repositories/_stub_stamper.dart';

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

Widget _wrap({
  required double contentWidth,
  double textScale = 1,
  List<KnowledgeNote>? notes,
  List<KnowledgeDecision>? decisions,
  String initialLocation = '/knowledge/library',
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/knowledge/library',
        onExit: (context, _) => FormLeaveScope.confirmRouteLeave(
          context,
          path: '/knowledge/library',
        ),
        builder: (_, _) => Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: contentWidth,
            child: const KnowledgeLibraryPage(),
          ),
        ),
      ),
      GoRoute(path: '/elsewhere', builder: (_, _) => const Text('elsewhere')),
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
      if (notes != null)
        knowledgeLibraryNotesProvider.overrideWith(
          (_, request) => Stream.value(notes.take(request.limit + 1).toList()),
        ),
      if (decisions != null)
        knowledgeLibraryDecisionsProvider.overrideWith(
          (_, limit) => Stream.value(decisions.take(limit + 1).toList()),
        ),
      mutationStamperProvider.overrideWith(
        (_) async => makeStubStamper(userId: _note.sync.ownerUserId),
      ),
      sharedPreferencesProvider.overrideWithValue(_prefs),
      knowledgeRepositoryProvider.overrideWith((_) async => _repository),
      knowledgeOwnerUserIdProvider.overrideWith(
        (_) async => _note.sync.ownerUserId,
      ),
      knowledgeNotesProvider.overrideWith(
        (_) => Stream.value(notes ?? [_note]),
      ),
      knowledgeDecisionsProvider.overrideWith(
        (_) => Stream.value(decisions ?? const <KnowledgeDecision>[]),
      ),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: FTheme(data: FTheme.neutral.light.desktop, child: child!),
      ),
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

  testWidgets(
    'route restores filters and clearing preserves the selected object',
    (tester) async {
      await _setSurface(tester, 1280);
      await tester.pumpWidget(
        _wrap(
          contentWidth: 1100,
          initialLocation:
              '/knowledge/library?scope=notes&tag=work&selected=note:note-1',
        ),
      );
      await _settlePaint(tester);
      final context = tester.element(find.byType(KnowledgeLibraryPage));
      final router = GoRouter.of(context);
      expect(find.byType(AppFilterSummary), findsOneWidget);
      expect(find.byType(KnowledgeNoteDetailPage), findsOneWidget);
      await tester.tap(find.text('Clear filters'));
      await _settlePaint(tester);
      expect(router.routeInformationProvider.value.uri.queryParameters, {
        'selected': 'note:note-1',
      });
      expect(find.byType(AppFilterSummary), findsNothing);
      expect(find.byType(KnowledgeNoteDetailPage), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('clearing the last search condition removes its URL query', (
    tester,
  ) async {
    await _setSurface(tester, 1280);
    await tester.pumpWidget(
      _wrap(
        contentWidth: 1100,
        initialLocation: '/knowledge/library?scope=notes',
      ),
    );
    await _settlePaint(tester);
    final router = GoRouter.of(
      tester.element(find.byType(KnowledgeLibraryPage)),
    );
    await tester.tap(find.text('Clear filters'));
    await _settlePaint(tester);
    expect(router.routeInformationProvider.value.uri.hasQuery, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
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
    expect(
      tester.widget<AppSelectedRow>(find.byType(AppSelectedRow)).selected,
      isTrue,
    );
    expect(find.text('pushed-note-detail'), findsNothing);
    await _disposeWidget(tester);
  });

  testWidgets('dirty detail blocks row changes, pane close, and route exit', (
    tester,
  ) async {
    final other = KnowledgeNote(
      id: 'note-2',
      title: 'Another note',
      bodyMd: 'Other body',
      createdAt: _note.createdAt,
      sync: _note.sync,
    );
    await _repository.upsertNote(other);
    await _setSurface(tester, 1280);
    await tester.pumpWidget(
      _wrap(
        contentWidth: 1100,
        notes: [_note, other],
        initialLocation: '/knowledge/library?selected=note:note-1',
      ),
    );
    await _settlePaint(tester);
    final context = tester.element(find.byType(KnowledgeLibraryPage));
    final router = GoRouter.of(context);
    await tester.tap(find.byKey(const Key('knowledge-note-edit-toggle')));
    await _settlePaint(tester);
    await tester.enterText(
      find.byKey(const Key('knowledge-note-title')),
      'Unsaved title',
    );
    await tester.tap(find.text('Another note'));
    await _settlePaint(tester);
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await _settlePaint(tester);
    expect(
      router.routeInformationProvider.value.uri.queryParameters['selected'],
      'note:note-1',
    );
    expect(find.text('Unsaved title'), findsOneWidget);
    expect(clearSelectedDetail(context), isTrue);
    await _settlePaint(tester);
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await _settlePaint(tester);
    router.go('/elsewhere');
    await _settlePaint(tester);
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await _settlePaint(tester);
    expect(find.text('Unsaved title'), findsOneWidget);
    await tester.tap(find.text('Another note'));
    await _settlePaint(tester);
    await tester.tap(find.text('Discard'));
    await _settlePaint(tester);
    expect(
      router.routeInformationProvider.value.uri.queryParameters['selected'],
      'note:note-2',
    );
    expect(
      (await _repository.findNote(
        ownerUserId: _note.sync.ownerUserId,
        id: _note.id,
      ))?.title,
      _note.title,
    );
    await _disposeWidget(tester);
  });

  testWidgets('saving a detail locks row selection and pane close', (
    tester,
  ) async {
    final database = makeTestDatabase();
    addTearDown(database.close);
    final repository = _BlockingRepository(
      db: database,
      outbox: InMemoryOutboxStore(),
    );
    _repository = repository;
    final other = KnowledgeNote(
      id: 'note-2',
      title: 'Another note',
      bodyMd: 'Other',
      createdAt: _note.createdAt,
      sync: _note.sync,
    );
    await repository.upsertNote(_note);
    await repository.upsertNote(other);
    await _setSurface(tester, 1280);
    await tester.pumpWidget(
      _wrap(
        contentWidth: 1100,
        notes: [_note, other],
        initialLocation: '/knowledge/library?selected=note:note-1',
      ),
    );
    await _settlePaint(tester);
    final context = tester.element(find.byType(KnowledgeLibraryPage));
    final router = GoRouter.of(context);
    await tester.tap(find.byKey(const Key('knowledge-note-edit-toggle')));
    await _settlePaint(tester);
    await tester.enterText(
      find.byKey(const Key('knowledge-note-title')),
      'Busy draft',
    );
    await _settlePaint(tester);
    await tester.tap(find.widgetWithText(FButton, 'Save'));
    await _settlePaint(tester);
    await tester.tap(find.text('Another note'));
    clearSelectedDetail(context);
    router.go('/elsewhere');
    await _settlePaint(tester);
    expect(
      router.routeInformationProvider.value.uri.queryParameters['selected'],
      'note:note-1',
    );
    expect(find.text('Discard changes?'), findsNothing);
    repository.gate.complete();
    await _settlePaint(tester);
    expect(
      (await repository.findNote(
        ownerUserId: _note.sync.ownerUserId,
        id: _note.id,
      ))?.title,
      'Busy draft',
    );
    await _disposeWidget(tester);
  });

  testWidgets('library filters fit a narrow viewport with large text', (
    tester,
  ) async {
    await _setSurface(tester, 320);
    await tester.pumpWidget(
      _wrap(
        contentWidth: 320,
        textScale: 1.5,
        initialLocation: '/knowledge/library?scope=notes&tag=work',
      ),
    );
    await _settlePaint(tester);
    expect(
      find.byKey(const Key('knowledge-library-tag-filter')),
      findsOneWidget,
    );
    expect(find.byType(AppFilterSummary), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _disposeWidget(tester);
  });

  testWidgets('row actions reveal on mouse hover and keyboard focus', (
    tester,
  ) async {
    await _setSurface(tester, 800);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(790, 890));
    await tester.pumpWidget(_wrap(contentWidth: 700));
    await _settlePaint(tester);
    final menu = find.byIcon(FLucideIcons.ellipsis);
    double opacity() => tester
        .widget<AnimatedOpacity>(
          find.ancestor(of: menu, matching: find.byType(AnimatedOpacity)).first,
        )
        .opacity;
    expect(opacity(), 0);
    await mouse.moveTo(tester.getCenter(find.text('Library note')));
    await tester.pumpAndSettle();
    expect(opacity(), 1);
    await mouse.moveTo(const Offset(790, 890));
    await tester.pumpAndSettle();
    expect(opacity(), 0);
    // Reach the row through normal keyboard traversal, without a mouse.
    for (var i = 0; i < 20 && opacity() == 0; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
    }
    expect(opacity(), 1);
    await mouse.removePointer();
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

  testWidgets('rows render plain excerpts, meta, badges, and date sections', (
    tester,
  ) async {
    final now = DateTime.now();
    SyncMeta meta(DateTime at) => SyncMeta(
      ownerUserId: 'knowledge-md-user',
      updatedAt: at,
      updatedByDevice: 'knowledge-md-device',
      hlc: Hlc.zero('knowledge-md-device'),
    );
    KnowledgeNote note(String id, String title, String bodyMd, DateTime at) =>
        KnowledgeNote(
          id: id,
          title: title,
          bodyMd: bodyMd,
          createdAt: at,
          sync: meta(at),
        );
    final notes = [
      note('note-recent', 'Markdown note', '**Bold** intro\n- [ ] task', now),
      note(
        'note-older',
        'Older note',
        'older body',
        now.subtract(const Duration(days: 10)),
      ),
    ];
    final decisions = [
      KnowledgeDecision(
        id: 'decision-1',
        question: 'Ship the redesign?',
        options: const <DecisionOption>[],
        selectedLabel: 'Ship it',
        rationaleMd: '',
        status: DecisionStatus.active,
        decidedAt: now,
        sync: meta(now),
      ),
    ];

    for (final item in notes) {
      await _repository.upsertNote(item);
    }
    for (final item in decisions) {
      await _repository.upsertDecision(item);
    }
    await _setSurface(tester, 800);
    await tester.pumpWidget(
      _wrap(contentWidth: 700, notes: notes, decisions: decisions),
    );
    await _settlePaint(tester);

    // Markdown markers are stripped from row subtitles.
    expect(find.textContaining('Bold intro'), findsOneWidget);
    expect(find.textContaining('**'), findsNothing);
    // Relative meta and activity-feed date section headers.
    expect(find.text('just now'), findsWidgets);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Earlier'), findsOneWidget);
    // Decision rows carry a status badge, and every row has an overflow menu.
    expect(find.text('Active'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(KnowledgeEntryTile),
        matching: find.byIcon(FLucideIcons.ellipsis),
      ),
      findsNWidgets(3),
    );
    await _disposeWidget(tester);
  });
}

Future<void> _disposeWidget(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

class _BlockingRepository extends KnowledgeRepository {
  _BlockingRepository({required super.db, required super.outbox});
  final gate = Completer<void>();
  @override
  Future<void> upsertNote(KnowledgeNote note) async {
    if (note.title == 'Busy draft') {
      await gate.future;
    }
    await super.upsertNote(note);
  }
}
