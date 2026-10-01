import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/ai/visual/ai_markdown.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_repository.dart';
import 'package:naviwealth/features/knowledge/data/providers.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';
import 'package:naviwealth/features/knowledge/ui/knowledge_note_detail_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../../core/persistence/test_database.dart';
import '../../finance/data/repositories/_stub_stamper.dart';

const _owner = 'knowledge-editor-user';

void main() {
  testWidgets(
    'Note save locks editing and preserves a failed draft for retry',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final database = makeTestDatabase();
      addTearDown(database.close);
      final repository = _DelayedRepository(
        db: database,
        outbox: InMemoryOutboxStore(),
      );
      final note = _note();
      await repository.upsertNote(note);
      await tester.pumpWidget(_wrap(note.id, repository));
      await _settle(tester);
      await tester.tap(find.text('Open note'));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('knowledge-note-edit-toggle')));
      await _settle(tester);
      await tester.enterText(
        find.byKey(const Key('knowledge-note-title')),
        'Retryable title',
      );
      await _settle(tester);
      repository.gate = Completer<void>();
      await tester.tap(find.text('Save'));
      await _settle(tester);
      expect(repository.writes, 1);
      await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(find.text('Discard changes?'), findsNothing);
      expect(
        tester.widget<EditableText>(find.byType(EditableText).first).readOnly,
        isTrue,
      );
      repository.gate!.completeError(StateError('private storage path'));
      await _settle(tester);
      expect(find.text('Retryable title'), findsOneWidget);
      expect(find.byType(AppStatusBanner), findsWidgets);
      expect(find.textContaining('private storage path'), findsNothing);
      expect(
        (await repository.findNote(ownerUserId: _owner, id: note.id))?.title,
        note.title,
      );
      repository.gate = null;
      await tester.tap(find.text('Save'));
      await _settle(tester);
      expect(repository.writes, 2);
      expect(
        (await repository.findNote(ownerUserId: _owner, id: note.id))?.title,
        'Retryable title',
      );
      expect(find.byKey(const Key('knowledge-note-title')), findsNothing);
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    },
  );

  testWidgets('a body-only Note can be edited and saved without a title', (
    tester,
  ) async {
    final database = makeTestDatabase();
    addTearDown(database.close);
    final repository = KnowledgeRepository(
      db: database,
      outbox: InMemoryOutboxStore(),
    );
    final note = KnowledgeNote(
      id: 'body-only',
      title: '',
      bodyMd: 'Source text',
      createdAt: _sync().updatedAt,
      sync: _sync(),
    );
    await repository.upsertNote(note);
    await tester.pumpWidget(_wrap(note.id, repository));
    await tester.tap(find.text('Open note'));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('knowledge-note-edit-toggle')));
    await _settle(tester);
    await tester.enterText(
      find.byKey(const Key('knowledge-note-body')),
      'Updated body',
    );
    await _settle(tester);
    await tester.tap(find.widgetWithText(FButton, 'Save'));
    await _settle(tester);
    final saved = await repository.findNote(ownerUserId: _owner, id: note.id);
    expect(saved?.title, '');
    expect(saved?.bodyMd, 'Updated body');
    expect(find.byKey(const Key('knowledge-note-title')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('Note editor guards dirty exits and confirms deletion', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final database = makeTestDatabase();
    addTearDown(database.close);
    final repository = KnowledgeRepository(
      db: database,
      outbox: InMemoryOutboxStore(),
    );
    final note = _note();
    await repository.upsertNote(note);

    await tester.pumpWidget(_wrap(note.id, repository));
    await _settle(tester);
    await tester.tap(find.text('Open note'));
    await _settle(tester);

    // Read mode is the default: rendered title, markdown body, tag chips.
    expect(find.text('Original evidence'), findsOneWidget);
    expect(find.byType(AiMarkdown), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('knowledge-note-tag-work')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('knowledge-note-title')), findsNothing);

    await tester.tap(find.byKey(const Key('knowledge-note-edit-toggle')));
    await _settle(tester);

    expect(
      tester.widget<FButton>(find.widgetWithText(FButton, 'Save')).onPress,
      isNull,
    );
    final titleField = find.byKey(const Key('knowledge-note-title'));
    await tester.enterText(titleField, 'Updated evidence');
    await _settle(tester);
    expect(
      tester.widget<FButton>(find.widgetWithText(FButton, 'Save')).onPress,
      isNotNull,
    );

    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await _settle(tester);
    expect(find.text('Updated evidence'), findsOneWidget);

    await tester.tap(find.widgetWithText(FButton, 'Save'));
    await _settle(tester);
    final saved = await repository.findNote(ownerUserId: _owner, id: note.id);
    expect(saved?.title, 'Updated evidence');
    // Saving returns to read mode; re-enter edit mode to confirm the form
    // is pristine again.
    expect(find.text('Updated evidence'), findsOneWidget);
    await tester.tap(find.byKey(const Key('knowledge-note-edit-toggle')));
    await _settle(tester);
    expect(
      tester.widget<FButton>(find.widgetWithText(FButton, 'Save')).onPress,
      isNull,
    );

    await tester.tap(find.byIcon(FLucideIcons.ellipsis));
    await _settle(tester);
    await tester.tap(find.text('Delete').hitTestable());
    await _settle(tester);
    expect(find.text('Delete this note?'), findsOneWidget);
    await tester.tap(find.text('Cancel').hitTestable());
    await _settle(tester);
    expect(
      (await repository.findNote(
        ownerUserId: _owner,
        id: note.id,
      ))?.sync.deletedAt,
      isNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
  testWidgets('live updates preserve dirty drafts and deletion blocks saving', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final database = makeTestDatabase();
    addTearDown(database.close);
    final repository = KnowledgeRepository(
      db: database,
      outbox: InMemoryOutboxStore(),
    );
    final original = _note();
    await repository.upsertNote(original);
    await tester.pumpWidget(_wrap(original.id, repository));
    await tester.tap(find.text('Open note'));
    await _settle(tester);
    KnowledgeNote update(String title, int counter) => KnowledgeNote(
      id: original.id,
      title: title,
      bodyMd: original.bodyMd,
      createdAt: original.createdAt,
      sync: original.sync.copyWith(
        hlc: Hlc(
          wallMillis: original.sync.hlc.wallMillis,
          counter: counter,
          nodeId: original.sync.hlc.nodeId,
        ),
      ),
    );
    await repository.upsertNote(update('Latest read title', 1));
    await _settle(tester);
    expect(find.text('Latest read title'), findsOneWidget);
    await tester.tap(find.byKey(const Key('knowledge-note-edit-toggle')));
    await _settle(tester);
    await tester.enterText(
      find.byKey(const Key('knowledge-note-title')),
      'My preserved draft',
    );
    await repository.upsertNote(update('External update', 2));
    await _settle(tester);
    expect(find.text('My preserved draft'), findsOneWidget);
    expect(
      find.byKey(const Key('knowledge-edit-change-notice')),
      findsOneWidget,
    );
    expect(
      tester.widget<FButton>(find.widgetWithText(FButton, 'Save')).onPress,
      isNull,
    );
    await tester.tap(find.byKey(const Key('knowledge-edit-reload')));
    await _settle(tester);
    await tester.tap(find.text('Keep editing'));
    await _settle(tester);
    expect(find.text('My preserved draft'), findsOneWidget);
    await tester.tap(find.byKey(const Key('knowledge-edit-reload')));
    await _settle(tester);
    await tester.tap(find.text('Discard'));
    await _settle(tester);
    expect(find.text('External update'), findsOneWidget);
    await tester.tap(find.byKey(const Key('knowledge-note-edit-toggle')));
    await _settle(tester);
    await tester.enterText(
      find.byKey(const Key('knowledge-note-title')),
      'Deleted source draft',
    );
    await repository.deleteEntry(
      kind: KnowledgeEntryKind.note,
      id: original.id,
      sync: _sync(),
    );
    await _settle(tester);
    expect(find.text('Deleted source draft'), findsOneWidget);
    expect(
      tester.widget<FButton>(find.widgetWithText(FButton, 'Save')).onPress,
      isNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}

Widget _wrap(String noteId, KnowledgeRepository repository) => ProviderScope(
  overrides: [
    knowledgeRepositoryProvider.overrideWith((ref) async => repository),
    knowledgeOwnerUserIdProvider.overrideWith((ref) async => _owner),
    mutationStamperProvider.overrideWith(
      (ref) async => makeStubStamper(userId: _owner),
    ),
  ],
  child: MaterialApp(
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    builder: (context, child) =>
        FTheme(data: FTheme.neutral.light.desktop, child: child!),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => KnowledgeNoteDetailPage(noteId: noteId),
              ),
            ),
            child: const Text('Open note'),
          ),
        ),
      ),
    ),
  ),
);

Future<void> _settle(WidgetTester tester) async {
  for (var index = 0; index < 12; index++) {
    await tester.pump(const Duration(milliseconds: 75), EnginePhase.paint);
  }
}

KnowledgeNote _note() => KnowledgeNote(
  id: 'note-editor',
  title: 'Original evidence',
  bodyMd: 'A body with **Markdown**.',
  tags: const <String>['work'],
  createdAt: _sync().updatedAt,
  sync: _sync(),
);

SyncMeta _sync() {
  final now = DateTime.utc(2026, 8, 30, 10);
  return SyncMeta(
    ownerUserId: _owner,
    updatedAt: now,
    updatedByDevice: 'knowledge-editor-device',
    hlc: Hlc(
      wallMillis: now.millisecondsSinceEpoch,
      counter: 0,
      nodeId: 'knowledge-editor-device',
    ),
  );
}

class _DelayedRepository extends KnowledgeRepository {
  _DelayedRepository({required super.db, required super.outbox});
  Completer<void>? gate;
  int writes = 0;
  @override
  Future<void> upsertNote(KnowledgeNote note) async {
    if (note.title == 'Retryable title') {
      writes++;
      await gate?.future;
    }
    await super.upsertNote(note);
  }
}
