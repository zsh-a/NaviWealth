import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/knowledge/data/capture_classifier.dart';
import 'package:naviwealth/features/knowledge/data/capture_kind.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_llm_client.dart';
import 'package:naviwealth/features/knowledge/data/providers.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';
import 'package:naviwealth/features/knowledge/ui/knowledge_capture_sheet.dart';
import 'package:naviwealth/features/knowledge/ui/knowledge_inbox_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> pumpInbox(
    WidgetTester tester, {
    CaptureClassifier? captureClassifier,
    Map<String, Object> preferences = const <String, Object>{},
    double width = 390,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    SharedPreferences.setMockInitialValues(preferences);
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          activeUserIdProvider.overrideWithValue('user-1'),
          knowledgeInboxNotesProvider.overrideWith(
            (_) => Stream<List<KnowledgeNote>>.value(const <KnowledgeNote>[]),
          ),
          if (captureClassifier != null) ...[
            knowledgeLlmProfileClientProvider.overrideWithValue(
              const _AvailableKnowledgeLlmClient(),
            ),
            captureClassifierProvider.overrideWithValue(captureClassifier),
          ],
        ],
        child: FTheme(
          data: FTheme.neutral.light.desktop,
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en', 'US'),
            home: const KnowledgeInboxPage(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> pumpVisualTransition(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 80), EnginePhase.paint);
    }
  }

  testWidgets('keeps capture primary and groups AI shortcuts in one menu', (
    tester,
  ) async {
    await pumpInbox(tester);

    expect(find.text('Capture a thought'), findsWidgets);
    expect(find.byIcon(FLucideIcons.filePlus), findsOneWidget);
    expect(find.byIcon(FLucideIcons.sparkles), findsOneWidget);
    expect(find.byIcon(FLucideIcons.gitMerge), findsNothing);
    expect(find.text('Deduplicate'), findsNothing);

    await tester.tap(find.byIcon(FLucideIcons.sparkles));
    await tester.pumpAndSettle();

    expect(find.text('Ask KnowledgeOS'), findsOneWidget);
    expect(find.text('Deduplicate'), findsOneWidget);
    expect(find.text('Weekly review'), findsOneWidget);
    expect(find.text('Search knowledge'), findsOneWidget);
  });

  testWidgets('keeps one capture entry and review in the shell header', (
    tester,
  ) async {
    await pumpInbox(tester);

    expect(find.text('Inbox'), findsWidgets);
    expect(find.text('Inbox · KnowledgeOS'), findsNothing);
    expect(find.byIcon(FLucideIcons.plus), findsNothing);
    expect(find.byIcon(FLucideIcons.clipboardCheck), findsOneWidget);
  });

  testWidgets('opens quick capture from the primary Inbox surface', (
    tester,
  ) async {
    await pumpInbox(tester);

    await tester.tap(find.byIcon(FLucideIcons.filePlus));
    await pumpVisualTransition(tester);

    expect(find.byType(AppSheet), findsOneWidget);
    expect(
      find.text(
        'Write naturally. AI can shape the title and Markdown before anything is saved.',
      ),
      findsOneWidget,
    );
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('protects an unfinished capture from accidental dismissal', (
    tester,
  ) async {
    await pumpInbox(tester);

    await tester.tap(find.byIcon(FLucideIcons.filePlus));
    await pumpVisualTransition(tester);
    await tester.enterText(find.byType(FTextField).last, 'A durable thought');
    await tester.tap(find.text('Cancel'));
    await pumpVisualTransition(tester);

    expect(find.text('Discard changes?'), findsOneWidget);
    expect(find.text('Keep editing'), findsOneWidget);
  });

  testWidgets('recovers and can discard an unfinished local capture', (
    tester,
  ) async {
    await pumpInbox(
      tester,
      preferences: const <String, Object>{
        'knowledge.user-1.capture_draft.v1':
            '{"title":"Recovered title","body":"Recovered body"}',
      },
    );

    await tester.tap(find.byIcon(FLucideIcons.filePlus));
    await pumpVisualTransition(tester);

    expect(
      find.text('Recovered your unfinished capture from this device.'),
      findsOneWidget,
    );
    final fields = tester
        .widgetList<EditableText>(find.byType(EditableText))
        .toList(growable: false);
    expect(fields.first.controller.text, 'Recovered title');
    expect(fields.last.controller.text, 'Recovered body');

    await tester.tap(find.text('Discard draft'));
    await tester.pump(const Duration(milliseconds: 151));
    await tester.pumpAndSettle();
    expect(fields.first.controller.text, isEmpty);
    expect(fields.last.controller.text, isEmpty);
    expect(
      find.text('Recovered your unfinished capture from this device.'),
      findsNothing,
    );
  });

  testWidgets('organizes the complete note and opens on rendered preview', (
    tester,
  ) async {
    final classifier = _OrganizedCaptureClassifier();
    await pumpInbox(tester, captureClassifier: classifier);

    await tester.tap(find.byIcon(FLucideIcons.filePlus));
    await pumpVisualTransition(tester);

    expect(find.text('Organize & preview'), findsOneWidget);
    expect(find.text('Save original'), findsOneWidget);

    await tester.enterText(
      find.byType(FTextField).last,
      'rough note: one thing, another thing',
    );
    await pumpVisualTransition(tester);
    await tester.tap(find.text('Organize & preview'));
    await pumpVisualTransition(tester);

    expect(find.text('Review organized note'), findsOneWidget);
    expect(find.text('A clear, searchable title'), findsOneWidget);
    expect(find.text('Key points'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Save organized note'), findsOneWidget);
    expect(find.text('View original'), findsOneWidget);
    expect(classifier.lastText, contains('original_body_md'));
    expect(
      classifier.lastText,
      contains('rough note: one thing, another thing'),
    );

    await tester.tap(find.text('View original'));
    await pumpVisualTransition(tester);
    expect(find.text('Original'), findsOneWidget);
    expect(find.text('rough note: one thing, another thing'), findsOneWidget);
    await tester.tap(find.text('View organized'));
    await pumpVisualTransition(tester);
    expect(find.text('A clear, searchable title'), findsOneWidget);

    await tester.tap(find.text('Keep original'));
    await pumpVisualTransition(tester);
    final fields = tester
        .widgetList<EditableText>(find.byType(EditableText))
        .toList(growable: false);
    expect(fields.last.controller.text, 'rough note: one thing, another thing');
  });

  testWidgets('rejects an organized draft that drops a local attachment', (
    tester,
  ) async {
    await pumpInbox(tester, captureClassifier: _UnsafeCaptureClassifier());

    await tester.tap(find.byIcon(FLucideIcons.filePlus));
    await pumpVisualTransition(tester);
    const original = 'Context\n\n![receipt](attachment://abc-123)';
    await tester.enterText(find.byType(FTextField).last, original);
    await pumpVisualTransition(tester);
    await tester.tap(find.text('Organize & preview'));
    await pumpVisualTransition(tester);

    expect(find.text('Organize & preview'), findsOneWidget);
    final fields = tester
        .widgetList<EditableText>(find.byType(EditableText))
        .toList(growable: false);
    expect(fields.last.controller.text, original);
  });

  testWidgets('shows original and organized drafts side by side when wide', (
    tester,
  ) async {
    await pumpInbox(
      tester,
      width: 1100,
      captureClassifier: _OrganizedCaptureClassifier(),
    );

    await tester.tap(find.byIcon(FLucideIcons.filePlus));
    await pumpVisualTransition(tester);
    await tester.enterText(
      find.byType(FTextField).last,
      'rough note: one thing, another thing',
    );
    await pumpVisualTransition(tester);
    await tester.tap(find.text('Organize & preview'));
    await pumpVisualTransition(tester);

    expect(find.text('Original'), findsOneWidget);
    expect(find.text('AI-organized draft'), findsOneWidget);
    expect(find.text('View original'), findsNothing);
    expect(find.text('rough note: one thing, another thing'), findsOneWidget);
    expect(find.text('A clear, searchable title'), findsOneWidget);
  });

  testWidgets('organizes an existing note from its current complete content', (
    tester,
  ) async {
    final classifier = _OrganizedCaptureClassifier();
    final created = DateTime.utc(2026, 8, 21);
    final note = KnowledgeNote(
      id: 'existing-note',
      title: 'Rough title',
      bodyMd: 'rough note: one thing, another thing',
      tags: const <String>['durable'],
      projectTag: 'knowledge',
      createdAt: created,
      sync: SyncMeta(
        ownerUserId: 'user',
        updatedAt: created,
        updatedByDevice: 'device',
        hlc: Hlc.zero('device'),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          knowledgeLlmProfileClientProvider.overrideWithValue(
            const _AvailableKnowledgeLlmClient(),
          ),
          captureClassifierProvider.overrideWithValue(classifier),
        ],
        child: FTheme(
          data: FTheme.neutral.light.desktop,
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en', 'US'),
            home: Builder(
              builder: (context) => FButton(
                onPress: () => showOrganizeKnowledgeNoteSheet(context, note),
                child: const Text('Organize existing'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Organize existing'));
    await pumpVisualTransition(tester);

    expect(find.text('Review organized note'), findsOneWidget);
    expect(find.text('A clear, searchable title'), findsOneWidget);
    expect(classifier.lastText, contains('Rough title'));
    expect(classifier.lastText, contains(note.bodyMd));

    await tester.tap(find.text('Keep original'));
    await pumpVisualTransition(tester);
    await tester.tap(find.text('Cancel'));
    await pumpVisualTransition(tester);
    expect(find.text('Discard changes?'), findsNothing);
    expect(find.byType(AppSheet), findsNothing);
  });
}

class _OrganizedCaptureClassifier implements CaptureClassifier {
  String? lastText;

  @override
  Future<CaptureClassification> classify({required String text}) async {
    lastText = text;
    return CaptureClassification(
      kind: CaptureKind.note,
      confidence: 0.9,
      reasonZh: '完整整理',
      polishedTitle: 'A clear, searchable title',
      polishedBody: '## Key points\n\n- One thing\n- Another thing',
    );
  }
}

class _AvailableKnowledgeLlmClient implements KnowledgeLlmProfileClient {
  const _AvailableKnowledgeLlmClient();

  @override
  Future<Map<String, Object?>> completeProfile({
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const <Map<String, Object?>>[],
    double? temperature,
    int? maxOutputTokens,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    throw UnimplementedError();
  }
}

class _UnsafeCaptureClassifier implements CaptureClassifier {
  @override
  Future<CaptureClassification> classify({required String text}) async {
    return CaptureClassification(
      kind: CaptureKind.note,
      confidence: 0.9,
      reasonZh: '遗漏附件',
      polishedTitle: 'Context',
      polishedBody: 'Context',
    );
  }
}
