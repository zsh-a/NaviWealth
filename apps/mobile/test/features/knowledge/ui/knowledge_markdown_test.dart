import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/ai/visual/flow_block.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/knowledge/ui/_widgets.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(390, 844),
  bool dark = false,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    FTheme(
      data: dark ? FTheme.neutral.dark.desktop : FTheme.neutral.light.desktop,
      child: MaterialApp(
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

String _renderedText(WidgetTester tester) {
  final buffer = StringBuffer();
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    buffer.write(text.data ?? text.textSpan?.toPlainText() ?? '');
    buffer.write('\n');
  }
  for (final text in tester.widgetList<SelectableText>(
    find.byType(SelectableText),
  )) {
    buffer.write(text.data ?? text.textSpan?.toPlainText() ?? '');
    buffer.write('\n');
  }
  return buffer.toString();
}

void main() {
  testWidgets('renders GFM document blocks with a clear reading hierarchy', (
    tester,
  ) async {
    await _pump(
      tester,
      const KnowledgeMarkdown(
        text:
            '# 决策记录\n\n'
            '正文包含 **重点**、~~旧结论~~ 和 `code`.\n\n'
            '> 保留判断依据。\n\n'
            '- [x] 已验证\n'
            '- [ ] 待验证',
      ),
    );

    final rendered = _renderedText(tester);
    expect(rendered, contains('决策记录'));
    expect(rendered, contains('重点'));
    expect(rendered, contains('旧结论'));
    expect(rendered, contains('保留判断依据'));
    expect(rendered, contains('已验证'));
    expect(find.byIcon(FLucideIcons.check), findsOneWidget);

    final semantics = tester.getSemantics(find.text('决策记录'));
    expect(semantics.flagsCollection.isHeader, isTrue);
  });

  testWidgets('renders responsive tables without intrinsic column sizing', (
    tester,
  ) async {
    await _pump(
      tester,
      const KnowledgeMarkdown(
        text:
            '| 方案 | 结果 |\n'
            '| --- | ---: |\n'
            '| A | 8 |\n'
            '| B | 13 |',
      ),
    );

    expect(find.byType(Table), findsOneWidget);
    final table = tester.widget<Table>(find.byType(Table));
    expect(table.defaultColumnWidth, isA<FlexColumnWidth>());
    expect(
      find.bySemanticsLabel('Table, 3 rows and 2 columns'),
      findsOneWidget,
    );
  });

  testWidgets('renders flow fences as diagrams and code fences with copy', (
    tester,
  ) async {
    await _pump(
      tester,
      const KnowledgeMarkdown(
        text:
            '```flow\nstep: 收集证据\nstep: 复盘\n```\n\n'
            '```dart\nfinal answer = 42;\n```',
      ),
    );

    expect(find.byType(FlowDiagramWidget), findsOneWidget);
    expect(_renderedText(tester), contains('final answer = 42;'));
    expect(find.byIcon(FLucideIcons.copy), findsOneWidget);
  });

  testWidgets('only turns allowlisted external schemes into tappable links', (
    tester,
  ) async {
    await _pump(
      tester,
      const KnowledgeMarkdown(
        text: '[安全链接](https://example.com) [本地命令](javascript:alert(1))',
      ),
    );

    expect(find.text('安全链接'), findsOneWidget);
    expect(find.text('本地命令'), findsNothing);
    expect(find.byType(GestureDetector), findsOneWidget);
    expect(_renderedText(tester), contains('本地命令'));
  });

  testWidgets('does not fetch markdown images and exposes their alt text', (
    tester,
  ) async {
    await _pump(
      tester,
      const KnowledgeMarkdown(text: '![研究截图](https://example.com/a.png)'),
    );

    expect(find.byType(Image), findsNothing);
    expect(find.text('Image: 研究截图'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Image: 研究截图' &&
            widget.properties.image == true,
      ),
      findsOneWidget,
    );
  });

  testWidgets('mobile editor toolbar formats the active selection', (
    tester,
  ) async {
    final controller = TextEditingController(text: '重要结论');
    addTearDown(controller.dispose);
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 4);

    await _pump(tester, MarkdownEditorWithPreview(controller: controller));
    await tester.tap(find.byIcon(FLucideIcons.bold));
    await tester.pump(const Duration(milliseconds: 250));

    expect(controller.text, '**重要结论**');
  });

  testWidgets('wide editor keeps authoring and live preview side by side', (
    tester,
  ) async {
    final controller = TextEditingController(text: '## 实时预览');
    addTearDown(controller.dispose);

    await _pump(
      tester,
      MarkdownEditorWithPreview(controller: controller),
      size: const Size(680, 800),
    );

    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
    expect(_renderedText(tester), contains('实时预览'));
    expect(find.byType(SegmentedRow), findsNothing);
  });

  testWidgets('remains readable in dark mode with large dynamic type', (
    tester,
  ) async {
    await _pump(
      tester,
      const KnowledgeMarkdown(
        text:
            '## 长文本缩放\n\n'
            '内容在较大的系统文字设置下仍然换行，不截断，也不依赖固定高度。',
      ),
      size: const Size(375, 812),
      dark: true,
      textScale: 2,
    );

    expect(_renderedText(tester), contains('内容在较大的系统文字设置下仍然换行'));
    expect(tester.takeException(), isNull);
  });
}
