import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/knowledge/data/capture_classifier.dart';
import 'package:naviwealth/features/knowledge/data/capture_kind.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_llm_client.dart';
import 'package:naviwealth/features/knowledge/data/providers.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';
import 'package:naviwealth/features/knowledge/ui/knowledge_inbox_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  Future<void> pumpInbox(
    WidgetTester tester, {
    CaptureClassifier? captureClassifier,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
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
    expect(find.byIcon(FLucideIcons.sparkles), findsNothing);
    expect(find.byIcon(FLucideIcons.gitMerge), findsNothing);
    expect(find.text('Deduplicate'), findsNothing);

    await tester.tap(find.byIcon(FLucideIcons.ellipsis));
    await tester.pumpAndSettle();

    expect(find.text('Ask KnowledgeOS'), findsOneWidget);
    expect(find.text('Deduplicate'), findsOneWidget);
    expect(find.text('Weekly review'), findsOneWidget);
    expect(find.text('Search knowledge'), findsOneWidget);
  });

  testWidgets('keeps capture in the shared shell header', (tester) async {
    await pumpInbox(tester);

    expect(find.text('Inbox'), findsWidgets);
    expect(find.text('Inbox · KnowledgeOS'), findsNothing);
    expect(find.byIcon(FLucideIcons.plus), findsOneWidget);
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

    await tester.tap(find.byIcon(FLucideIcons.plus).first);
    await pumpVisualTransition(tester);
    await tester.enterText(find.byType(FTextField).last, 'A durable thought');
    await tester.tap(find.text('Cancel'));
    await pumpVisualTransition(tester);

    expect(find.text('Discard changes?'), findsOneWidget);
    expect(find.text('Keep editing'), findsOneWidget);
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
    expect(classifier.lastText, contains('original_body_md'));
    expect(
      classifier.lastText,
      contains('rough note: one thing, another thing'),
    );

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
