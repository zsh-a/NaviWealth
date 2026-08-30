import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/ai/visual/ai_markdown.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/knowledge/ui/widgets/knowledge_markdown_editor.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  testWidgets('renders entered Markdown and returns to the same source', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller));

    await tester.enterText(
      find.byKey(const Key('markdown-editor')),
      '## Plan\n\n- **Keep** the source',
    );
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('markdown-preview')), findsOneWidget);
    expect(find.byType(AiMarkdown), findsOneWidget);
    expect(
      tester.widget<AiMarkdown>(find.byType(AiMarkdown)).text,
      '## Plan\n\n- **Keep** the source',
    );

    await tester.tap(find.text('Edit Markdown'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('markdown-editor')), findsOneWidget);
    expect(controller.text, '## Plan\n\n- **Keep** the source');
  });
}

Widget _host(TextEditingController controller) {
  return MaterialApp(
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: FTheme(
      data: FTheme.neutral.light.desktop,
      child: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(AppSpacing.s16),
          child: KnowledgeMarkdownEditor(
            controller: controller,
            label: 'Content (Markdown)',
            editorKey: const Key('markdown-editor'),
            previewKey: const Key('markdown-preview'),
          ),
        ),
      ),
    ),
  );
}
