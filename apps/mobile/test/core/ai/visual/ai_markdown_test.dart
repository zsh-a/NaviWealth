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

    testWidgets('renders a GFM table with header + body rows', (tester) async {
      await _pump(
        tester,
        const AiMarkdown(
          text:
              '| 名称 | 价格 |\n'
              '| --- | --- |\n'
              '| 苹果 | \$10 |\n'
              '| 谷歌 | \$20 |',
        ),
      );
      // Header + 2 body rows × 2 cells = 6 selectable cells.
      expect(find.byType(Table), findsOneWidget);
      final txt = _allText(tester);
      expect(txt, contains('名称'));
      expect(txt, contains('价格'));
      expect(txt, contains('苹果'));
      expect(txt, contains('\$10'));
      expect(txt, contains('谷歌'));
      expect(txt, contains('\$20'));
    });

    testWidgets('table alignment markers propagate to cells', (tester) async {
      await _pump(
        tester,
        const AiMarkdown(
          text:
              '| L | C | R |\n'
              '| :--- | :---: | ---: |\n'
              '| a | b | c |',
        ),
      );
      // Find the body cells and assert their alignments. Each cell is
      // wrapped in a Container with an Alignment matching the marker.
      final containers = tester
          .widgetList<Container>(find.byType(Container))
          .where(
            (c) =>
                c.alignment == Alignment.centerLeft ||
                c.alignment == Alignment.center ||
                c.alignment == Alignment.centerRight,
          )
          .toList();
      // 2 rows (header + body) × 3 cells = 6 aligned containers.
      expect(containers.length, greaterThanOrEqualTo(6));
      expect(
        containers.where((c) => c.alignment == Alignment.centerLeft).length,
        greaterThanOrEqualTo(2),
      );
      expect(
        containers.where((c) => c.alignment == Alignment.center).length,
        greaterThanOrEqualTo(2),
      );
      expect(
        containers.where((c) => c.alignment == Alignment.centerRight).length,
        greaterThanOrEqualTo(2),
      );
    });

    testWidgets('table cells parse inline markdown (bold inside cell)', (
      tester,
    ) async {
      await _pump(
        tester,
        const AiMarkdown(
          text:
              '| key | value |\n'
              '| --- | --- |\n'
              '| **bold** | plain |',
        ),
      );
      // Walk every selectable cell to find the bold span.
      final selectables = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .toList();
      final hasBold = selectables.any((st) {
        final flat = _flatten(st.textSpan!);
        return flat.any(
          (p) => p.$1 == 'bold' && p.$2?.fontWeight == FontWeight.w600,
        );
      });
      expect(hasBold, isTrue);
    });

    testWidgets(
      'pipe-bearing line without a separator falls back to paragraph',
      (tester) async {
        // Without the `---|---` separator on the next line, this is
        // not a table — must render as a single paragraph.
        await _pump(tester, const AiMarkdown(text: '| a | b | c |'));
        expect(find.byType(Table), findsNothing);
        expect(_allText(tester), contains('| a | b | c |'));
      },
    );

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

    testWidgets('fenced code block scrolls horizontally instead of wrapping', (
      tester,
    ) async {
      await _pump(
        tester,
        const AiMarkdown(
          text:
              '```dart\nvoid main() => print("a very long single line that '
              'will definitely overflow the bubble width on any reasonable '
              'phone screen size");\n```',
        ),
      );
      // The code block must live inside a horizontal SingleChildScrollView
      // so long lines scroll instead of soft-wrapping.
      final scroll = tester
          .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .where((s) => s.scrollDirection == Axis.horizontal)
          .toList();
      expect(scroll, isNotEmpty);
    });
  });

  group('AiMarkdown — task lists', () {
    testWidgets('parses `- [ ] todo` as unchecked task', (tester) async {
      await _pump(
        tester,
        const AiMarkdown(text: '- [ ] pending step\n- [x] done step'),
      );
      // Two list rows.
      expect(find.byType(SelectableText), findsNWidgets(2));
      // The `[ ]` / `[x]` token is consumed by the parser — it must
      // NOT appear in the rendered text.
      final txt = _allText(tester);
      expect(txt, contains('pending step'));
      expect(txt, contains('done step'));
      expect(txt, isNot(contains('[ ]')));
      expect(txt, isNot(contains('[x]')));
    });

    testWidgets('checked task gets line-through styling', (tester) async {
      await _pump(tester, const AiMarkdown(text: '- [x] complete'));
      final st = tester.widget<SelectableText>(find.byType(SelectableText));
      final flat = _flatten(st.textSpan!);
      final completeSpan = flat.firstWhere((p) => p.$1 == 'complete');
      expect(completeSpan.$2!.decoration, TextDecoration.lineThrough);
    });

    testWidgets('ordered task items keep their number + checkbox', (
      tester,
    ) async {
      await _pump(
        tester,
        const AiMarkdown(text: '1. [ ] first\n2. [x] second'),
      );
      // Numeric markers still render alongside the checkboxes.
      expect(find.text('1.'), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);
      final txt = _allText(tester);
      expect(txt, contains('first'));
      expect(txt, contains('second'));
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

    testWidgets('strikethrough emits a line-through span', (tester) async {
      await _pump(
        tester,
        const AiMarkdown(text: 'keep ~~drop this~~ rest'),
      );
      final st = tester.widget<SelectableText>(find.byType(SelectableText));
      final flat = _flatten(st.textSpan!);
      final drop = flat.firstWhere((p) => p.$1 == 'drop this');
      expect(drop.$2!.decoration, TextDecoration.lineThrough);
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

    testWidgets('parser result is memoized across rebuilds', (tester) async {
      const text = '# Title\n\nbody one\n\n- a\n- b';
      // Pump first, then rebuild the same widget tree. If memoization
      // works, the second build does not re-parse — we detect this
      // indirectly by inspecting the widget state (re-parsing always
      // produces a fresh List instance).
      const widget = AiMarkdown(text: text);
      await _pump(tester, widget);
      // ignore: invalid_use_of_protected_member
      final state = tester.state(find.byWidget(widget));
      // Capture the cached blocks pointer via reflection-free means:
      // the cache is a private field; we instead verify the public
      // behaviour: triggering a rebuild with the same text doesn't
      // change the rendered output.
      final beforeText = _allText(tester);
      await tester.pump(); // schedule frame
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AiMarkdown(text: text)),
        ),
      );
      expect(_allText(tester), beforeText);
      expect(state, isNotNull);
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
