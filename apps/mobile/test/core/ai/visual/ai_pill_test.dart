import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/ai/visual/ai_pill.dart';
import 'package:naviwealth/design_system/design_system.dart';

Future<void> _pumpPill(
  WidgetTester tester, {
  required Widget child,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      builder: (context, appChild) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(textScaler: textScaler),
          child: appChild!,
        );
      },
      home: FTheme(
        data: FThemes.slate.light.desktop,
        child: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  testWidgets('non-interactive pill is not exposed as a button', (
    tester,
  ) async {
    const label = 'Status';
    final semantics = tester.ensureSemantics();

    await _pumpPill(
      tester,
      child: const Center(child: AiPill(label: label)),
    );

    final node = find.semantics.byLabel(label).evaluate().single;
    expect(node.getSemanticsData().flagsCollection.isButton, isFalse);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    semantics.dispose();
  });

  testWidgets('interactive pill exposes one selected enabled button', (
    tester,
  ) async {
    const label = 'Selected';
    var taps = 0;
    final semantics = tester.ensureSemantics();

    await _pumpPill(
      tester,
      child: Center(
        child: AiPill(
          label: label,
          state: AiPillState.selected,
          onTap: () => taps += 1,
        ),
      ),
    );

    final buttonFinder = find.semantics.byPredicate(
      (node) => node.getSemanticsData().flagsCollection.isButton,
    );
    final buttonNodes = buttonFinder.evaluate().toList();
    expect(find.bySubtype<FTappable>(), findsOneWidget);
    expect(buttonNodes, hasLength(1));

    final data = buttonNodes.single.getSemanticsData();
    expect(data.label, label);
    expect(data.flagsCollection.isSelected, ui.Tristate.isTrue);
    expect(data.flagsCollection.isEnabled, ui.Tristate.isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue);

    tester.semantics.tap(buttonFinder);
    await tester.pump();
    expect(taps, 1);
    semantics.dispose();
  });

  testWidgets('Enter and Space activate once and focus keeps pill size', (
    tester,
  ) async {
    const label = 'Keyboard action';
    var taps = 0;

    await _pumpPill(
      tester,
      child: Center(
        child: AiPill(label: label, onTap: () => taps += 1),
      ),
    );

    final sizeBeforeFocus = tester.getSize(find.byType(AiPill));
    expect(
      tester.widget<FTappable>(find.bySubtype<FTappable>()).focusedOutlineStyle,
      isNotNull,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    final outline = tester.widget<FFocusedOutline>(
      find.byType(FFocusedOutline),
    );
    expect(outline.focused, isTrue);
    expect(tester.getSize(find.byType(AiPill)), sizeBeforeFocus);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(taps, 1);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(taps, 1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(taps, 2);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(taps, 2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
  });

  testWidgets('bounded long label truncates safely at 2x text scale', (
    tester,
  ) async {
    const label =
        'Review every imported transaction before adding it to the ledger';
    final semantics = tester.ensureSemantics();

    await _pumpPill(
      tester,
      textScaler: const TextScaler.linear(2),
      child: const Center(
        child: SizedBox(
          width: 180,
          child: AiPill(label: label, leading: SizedBox(width: 12, height: 12)),
        ),
      ),
    );

    final text = tester.widget<Text>(find.text(label));
    final richText = find.descendant(
      of: find.text(label),
      matching: find.byType(RichText),
    );
    final paragraph = tester.renderObject<RenderParagraph>(richText);

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(AiPill)).width, 180);
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(paragraph.didExceedMaxLines, isTrue);
    expect(tester.getSemantics(find.text(label)).label, label);
    semantics.dispose();
  });

  testWidgets('unbounded short pill stays compact and fully interactive', (
    tester,
  ) async {
    const label = 'Review';
    const pillKey = ValueKey('pill');
    const leadingKey = ValueKey('leading');
    var taps = 0;

    await _pumpPill(
      tester,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: AiPill(
          key: pillKey,
          label: label,
          leading: const SizedBox(key: leadingKey, width: 12, height: 12),
          onTap: () => taps += 1,
        ),
      ),
    );

    final pillRect = tester.getRect(find.byKey(pillKey));
    final leadingRect = tester.getRect(find.byKey(leadingKey));
    final labelRect = tester.getRect(find.text(label));

    expect(tester.takeException(), isNull);
    expect(pillRect.width, lessThan(160));
    expect(labelRect.left - leadingRect.right, AppSpacing.s6);

    await tester.tapAt(Offset(pillRect.left + 2, pillRect.center.dy));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });
}
