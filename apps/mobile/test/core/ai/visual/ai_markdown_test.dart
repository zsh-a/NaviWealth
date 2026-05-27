// Tests for `AiMarkdown` — the lightweight markdown renderer used by
// the assistant chat bubble.
//
// We assert through the widget tree because the parser and renderer
// are private to the file. Coverage focuses on:
//   - block structure (heading vs paragraph vs list vs code vs quote
//     vs hr) appears in the rendered tree
//   - inline formatting (bold / italic / inline code / link) is
//     surfaced as a styled span on the SelectableText.rich subtree
//   - streaming safety: unclosed delimiters and unclosed fences do not
//     crash and surface the streaming caret on the last block
//   - the trailing caret slot lands on the last text-bearing block

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/visual/visual.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Padding(padding: const EdgeInsets.all(8), child: child)),
    ),
  );
}

/// Flattens every `TextSpan` rooted at `root` into a list of
/// (text, style) pairs so individual styling can be asserted.
List<(String, TextStyle?)> _flatten(InlineSpan root) {
  final out = <(String, TextStyle?)>[];
  void walk(InlineSpan s) {
    if (s is TextSpan) {
      if (s.text != null && s.text!.isNotEmpty) {
        out.add((s.text!, s.style));
      }
      for (final c in s.children ?? const <InlineSpan>[]) {
        walk(c);
      }
    }
  }

  walk(root);
  return out;
}

/// Returns the joined text from every `SelectableText.rich` and
/// `Text.rich` in the rendered tree. Lets us assert the textual
/// content even when blocks are split into separate widgets.
String _allText(WidgetTester tester) {
  final buf = StringBuffer();
  for (final t in tester.widgetList<SelectableText>(find.byType(SelectableText))) {
    final span = t.textSpan;
    if (span == null) continue;
    for (final p in _flatten(span)) {
      buf.write(p.$1);
    }
    buf.write('\n');
  }
  for (final t in tester.widgetList<Text>(find.byType(Text))) {
    final span = t.textSpan;
    if (span != null) {
      for (final p in _flatten(span)) {
        buf.write(p.$1);
      }
      buf.write('\n');
    } else if (t.data != null) {
      buf.write(t.data);
      buf.write('\n');
    }
  }
  return buf.toString();
}

void main() {
  group('AiMarkdown — block structure', () {
    testWidgets('renders a plain paragraph', (tester) async {
      await _pump(tester, const AiMarkdown(text: 'hello world'));
      expect(find.byType(SelectableText), findsOneWidget);
      expect(_allText(tester), contains('hello world'));
    });

    testWidgets('renders headings with bold weight', (tester) async {
      await _pump(
        tester,
        const AiMarkdown(text: '# Title\n\nbody text'),
      );
      // Two SelectableText subtrees: heading + paragraph.
      expect(find.byType(SelectableText), findsNWidgets(2));
      final st = tester.widgetList<SelectableText>(find.byType(SelectableText)).toList();
      final headingFlat = _flatten(st.first.textSpan!);
      expect(headingFlat.first.$1, 'Title');
      expect(headingFlat.first.$2!.fontWeight, FontWeight.w600);
    });

    testWidgets('renders unordered lists with a bullet per item', (tester) async {
      await _pump(
        tester,
        const AiMarkdown(text: '- one\n- two\n- three'),
      );
      expect(_allText(tester), contains('one'));
      expect(_allText(tester), contains('two'));
      expect(_allText(tester), contains('three'));
      // Three rows.
      expect(find.byType(SelectableText), findsNWidgets(3));
    });

    testWidgets('renders ordered lists with the model\'s own numbering', (tester) async {
      await _pump(
        tester,
        const AiMarkdown(text: '1. alpha\n2. beta\n5. delta'),
      );
      // Numbered markers render as plain Text rather than SelectableText.
      expect(find.text('1.'), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);
      // The parser keeps the model's numbering rather than re-numbering.
      expect(find.text('5.'), findsOneWidget);
    });

    testWidgets('renders blockquote with muted/italic content', (tester) async {
      await _pump(
        tester,
        const AiMarkdown(text: '> a quoted line\n> second line'),
      );
      final st = tester.widget<SelectableText>(find.byType(SelectableText));
      final flat = _flatten(st.textSpan!);
      expect(flat.first.$1, 'a quoted line\nsecond line');
      expect(flat.first.$2!.fontStyle, FontStyle.italic);
    });

    testWidgets('renders a horizontal rule between blocks', (tester) async {
      await _pump(
        tester,
        const AiMarkdown(text: 'one\n\n---\n\ntwo'),
      );
      expect(_allText(tester), contains('one'));
      expect(_allText(tester), contains('two'));
    });

    testWidgets('renders a fenced code block + language label', (tester) async {
      await _pump(
        tester,
        const AiMarkdown(text: '```dart\nint x = 1;\nprint(x);\n```'),
      );
      expect(_allText(tester), contains('int x = 1;'));
      expect(_allText(tester), contains('print(x);'));
      // Language label is a small `Text` (not selectable).
      expect(find.text('dart'), findsOneWidget);
    });
  });

  group('AiMarkdown — inline formatting', () {
    testWidgets('bold emits a w600 span', (tester) async {
      await _pump(tester, const AiMarkdown(text: 'plain **strong** plain'));
      final st = tester.widget<SelectableText>(find.byType(SelectableText));
      final flat = _flatten(st.textSpan!);
      final bold = flat.firstWhere((p) => p.$1 == 'strong');
      expect(bold.$2!.fontWeight, FontWeight.w600);
    });

    testWidgets('italic emits an italic span when properly flanked', (tester) async {
      await _pump(tester, const AiMarkdown(text: 'plain *em* plain'));
      final st = tester.widget<SelectableText>(find.byType(SelectableText));
      final flat = _flatten(st.textSpan!);
      final em = flat.firstWhere((p) => p.$1 == 'em');
      expect(em.$2!.fontStyle, FontStyle.italic);
    });

    testWidgets('does not italicize arithmetic-like patterns', (tester) async {
      // `5*3=15` should render as-is rather than turning `3=1` italic.
      await _pump(tester, const AiMarkdown(text: 'sum: 5*3=15'));
      final st = tester.widget<SelectableText>(find.byType(SelectableText));
      final flat = _flatten(st.textSpan!);
      final italicSpans = flat.where(
        (p) => p.$2?.fontStyle == FontStyle.italic,
      );
      expect(italicSpans, isEmpty);
    });

    testWidgets('inline code emits a monospace WidgetSpan', (tester) async {
      await _pump(tester, const AiMarkdown(text: 'use `make build` here'));
      // The inline-code child is rendered inside a non-selectable Text.
      expect(find.text('make build'), findsOneWidget);
    });

    testWidgets('links style label in the active tone with underline', (
      tester,
    ) async {
      await _pump(
        tester,
        const AiMarkdown(text: 'see [the docs](https://x.example)'),
      );
      final st = tester.widget<SelectableText>(find.byType(SelectableText));
      final flat = _flatten(st.textSpan!);
      final link = flat.firstWhere((p) => p.$1 == 'the docs');
      expect(link.$2!.decoration, TextDecoration.underline);
    });
  });

  group('AiMarkdown — streaming safety', () {
    testWidgets('unclosed bold still renders the trailing text', (tester) async {
      await _pump(tester, const AiMarkdown(text: 'open **bold tail'));
      final all = _allText(tester);
      expect(all, contains('open'));
      expect(all, contains('bold tail'));
    });

    testWidgets('unclosed fence renders the partial code block', (tester) async {
      await _pump(
        tester,
        const AiMarkdown(text: '```python\nx = 1\nstill streaming'),
      );
      // The partial code is selectable.
      expect(_allText(tester), contains('x = 1'));
      expect(_allText(tester), contains('still streaming'));
      // The language tag still shows up.
      expect(find.text('python'), findsOneWidget);
    });

    testWidgets('empty text + trailing caret renders the caret only', (
      tester,
    ) async {
      const caretKey = Key('caret');
      await _pump(
        tester,
        const AiMarkdown(
          text: '',
          trailing: WidgetSpan(child: SizedBox(key: caretKey, width: 6, height: 14)),
        ),
      );
      expect(find.byKey(caretKey), findsOneWidget);
    });

    testWidgets('trailing caret lands on the last text block', (tester) async {
      const caretKey = Key('caret');
      await _pump(
        tester,
        const AiMarkdown(
          text: '# Title\n\nbody one\n\nbody two',
          trailing: WidgetSpan(child: SizedBox(key: caretKey, width: 6, height: 14)),
        ),
      );
      expect(find.byKey(caretKey), findsOneWidget);
      // The caret sits inside the *last* SelectableText (the third
      // block — `body two`).
      final selectables = tester.widgetList<SelectableText>(find.byType(SelectableText)).toList();
      final lastSpans = _flatten(selectables.last.textSpan!);
      // The very last span in the last block is the caret WidgetSpan.
      // We can detect this by looking for the body's text + no caret
      // text in earlier blocks.
      final firstSpanText = _flatten(selectables.first.textSpan!)
          .map((e) => e.$1)
          .join();
      expect(firstSpanText, isNot(contains('SizedBox')));
      // Caret span has no `text`, so check by looking at children
      // count in the last block: the last block should contain at
      // least one WidgetSpan child.
      InlineSpan? hasWidgetSpan(InlineSpan s) {
        if (s is WidgetSpan) return s;
        if (s is TextSpan) {
          for (final c in s.children ?? const <InlineSpan>[]) {
            final got = hasWidgetSpan(c);
            if (got != null) return got;
          }
        }
        return null;
      }

      expect(hasWidgetSpan(selectables.last.textSpan!), isNotNull);
      expect(lastSpans, isNotEmpty);
    });
  });
}
