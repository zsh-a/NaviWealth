import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_repository.dart';
import 'package:naviwealth/features/knowledge/data/providers.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';
import 'package:naviwealth/features/knowledge/ui/knowledge_capture_sheet.dart';
import 'package:naviwealth/features/knowledge/ui/knowledge_note_detail_page.dart';
import 'package:naviwealth/features/knowledge/ui/knowledge_tag_picker_sheet.dart';
import 'package:naviwealth/features/knowledge/ui/widgets/knowledge_tag_chips.dart';
import 'package:naviwealth/features/knowledge/ui/widgets/knowledge_tag_input.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../../core/persistence/test_database.dart';

void main() {
  testWidgets(
    'tag completion replaces the unfinished token and chips remove selected tags',
    (tester) async {
      final database = makeTestDatabase();
      addTearDown(database.close);
      final repository = KnowledgeRepository(
        db: database,
        outbox: InMemoryOutboxStore(),
      );
      final now = DateTime.utc(2026, 8, 30);
      await repository.upsertNote(
        KnowledgeNote(
          id: 'tag-source',
          title: 'Tags',
          bodyMd: '',
          tags: const ['work', 'world', 'health', 'deep work'],
          createdAt: now,
          sync: SyncMeta(
            ownerUserId: 'tag-user',
            updatedAt: now,
            updatedByDevice: 'tag-device',
            hlc: Hlc.zero('tag-device'),
          ),
        ),
      );
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            knowledgeRepositoryProvider.overrideWith((_) async => repository),
            knowledgeOwnerUserIdProvider.overrideWith((_) async => 'tag-user'),
          ],
          child: _app(KnowledgeTagInput(controller: controller)),
        ),
      );
      await _settle(tester);
      await tester.enterText(find.byType(FTextField), 'home, wo');
      await _settle(tester);
      expect(
        find.byKey(const ValueKey('knowledge-tag-suggestion-health')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('knowledge-tag-suggestion-world')),
      );
      await _settle(tester);
      expect(parseKnowledgeTags(controller.text), ['home', 'world']);
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('knowledge-tag-remove-world')),
          matching: find.byIcon(FLucideIcons.x),
        ),
      );
      await _settle(tester);
      expect(parseKnowledgeTags(controller.text), ['home']);
      await tester.enterText(find.byType(FTextField), 'home, deep w');
      await _settle(tester);
      await tester.tap(
        find.byKey(const ValueKey('knowledge-tag-suggestion-deep work')),
      );
      await _settle(tester);
      expect(parseKnowledgeTags(controller.text), ['home', 'deep work']);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    },
  );

  testWidgets(
    'tag picker finds distant tags on a narrow screen with large text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(375, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      String? selected;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => FButton(
              onPress: () async {
                selected = await showKnowledgeTagPickerSheet(
                  context: context,
                  tags: List.generate(
                    100,
                    (index) => 'tag-${index.toString().padLeft(3, '0')}',
                  ),
                  selectedTag: null,
                  title: 'Tags',
                  allLabel: 'All tags',
                );
              },
              child: const Text('Open'),
            ),
          ),
          textScale: 2,
        ),
      );
      await tester.tap(find.text('Open'));
      await _settle(tester);
      await tester.enterText(
        find.byKey(const Key('knowledge-tag-picker-search')),
        'tag-099',
      );
      await _settle(tester);
      await tester.tap(
        find.byKey(const ValueKey('knowledge-library-tag-tag-099')),
      );
      await _settle(tester);
      expect(selected, 'tag-099');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    },
  );

  testWidgets('viewing a duplicate source keeps the capture draft mounted', (
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
    final now = DateTime.utc(2026, 8, 30);
    await repository.upsertNote(
      KnowledgeNote(
        id: 'existing-source',
        title: 'Existing evidence',
        bodyMd: 'Stored source',
        sourceUrl: 'https://example.com/source',
        createdAt: now,
        sync: SyncMeta(
          ownerUserId: 'tag-user',
          updatedAt: now,
          updatedByDevice: 'tag-device',
          hlc: Hlc.zero('tag-device'),
        ),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          knowledgeRepositoryProvider.overrideWith((_) async => repository),
          knowledgeOwnerUserIdProvider.overrideWith((_) async => 'tag-user'),
        ],
        child: _app(
          Builder(
            builder: (context) => FButton(
              onPress: () => showKnowledgeCaptureSheet(context),
              child: const Text('Capture'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Capture'));
    await _settle(tester);
    final title = find.widgetWithText(FTextField, 'Title (optional)');
    await tester.enterText(title, 'Preserved capture');
    expect(find.text('Preserved capture'), findsOneWidget);
    await tester.tap(find.text('Source and tags'));
    await _settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('knowledge-capture-source-url')),
      'https://example.com/source',
    );
    await _settle(tester);
    expect(
      find.byKey(const Key('knowledge-duplicate-source-open')),
      findsOneWidget,
    );
    expect(find.text('Preserved capture'), findsOneWidget);
    await tester.tap(find.byKey(const Key('knowledge-duplicate-source-open')));
    await _settle(tester);
    expect(find.byType(KnowledgeNoteDetailPage), findsOneWidget);
    expect(find.text('Existing evidence'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('app.back')));
    await _settle(tester);
    expect(find.byType(KnowledgeNoteDetailPage), findsNothing);
    expect(find.text('Preserved capture'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('knowledge-capture-source-url')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}

Widget _app(Widget child, {double textScale = 1}) => MaterialApp(
  theme: AppTheme.light(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  builder: (context, child) => FTheme(
    data: FTheme.neutral.light.desktop,
    child: MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
  ),
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(AppSpacing.s16), child: child),
  ),
);

Future<void> _settle(WidgetTester tester) async {
  for (var index = 0; index < 12; index++) {
    await tester.pump(const Duration(milliseconds: 75), EnginePhase.paint);
  }
}
