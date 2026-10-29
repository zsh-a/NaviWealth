import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

Widget _wrap({
  double width = 800,
  double textScale = 1,
  TextDirection direction = TextDirection.ltr,
  bool enabled = true,
  bool reducedMotion = false,
  List<String> options = const ['1M', '3M', '1Y', '3Y', 'All'],
  String initialValue = '1Y',
  ValueChanged<String>? onChanged,
}) {
  var value = initialValue;
  return MaterialApp(
    theme: AppTheme.light(),
    home: MediaQuery(
      data: MediaQueryData(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: reducedMotion,
      ),
      child: FTheme(
        data: FTheme.neutral.light.desktop,
        child: Directionality(
          textDirection: direction,
          child: Center(
            child: SizedBox(
              width: width,
              child: StatefulBuilder(
                builder: (context, setState) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SegmentedRow<String>.inline(
                      options: options,
                      value: value,
                      labelOf: (option) => option,
                      semanticLabelOf: (option) => 'Trend: $option',
                      onChanged: enabled
                          ? (option) {
                              setState(() => value = option);
                              onChanged?.call(option);
                            }
                          : null,
                    ),
                    TextButton(onPressed: () {}, child: const Text('Next')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

FocusNode _focus(WidgetTester tester, String label) => tester
    .widget<AppTappable>(
      find.ancestor(of: find.text(label), matching: find.byType(AppTappable)),
    )
    .focusNode!;

void main() {
  testWidgets('compact ranges retain full touch targets and do not stretch', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap());
    final semantics = tester.ensureSemantics();
    for (final label in ['1M', '3M', '1Y', '3Y', 'All']) {
      final bounds = tester.getRect(find.bySemanticsLabel('Trend: $label'));
      expect(bounds.width, greaterThanOrEqualTo(48));
      expect(bounds.height, greaterThanOrEqualTo(48));
    }
    final first = tester.getRect(find.bySemanticsLabel('Trend: 1M'));
    final last = tester.getRect(find.bySemanticsLabel('Trend: All'));
    expect(last.right - first.left, lessThan(360));
    expect((first.left + last.right) / 2, closeTo(400, 1));
    semantics.dispose();
  });

  testWidgets('keyboard enters selection, changes range, then leaves group', (
    tester,
  ) async {
    final changes = <String>[];
    await tester.pumpWidget(_wrap(onChanged: changes.add));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    expect(_focus(tester, '1Y').hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(changes.last, '3Y');
    expect(_focus(tester, '3Y').hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();
    expect(changes.last, 'All');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(changes.last, '1M');
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pumpAndSettle();
    expect(changes.last, '1M');
    final count = changes.length;
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(changes, hasLength(count));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(_focus(tester, '1M').hasFocus, isFalse);
    // Shift+Tab returns to the selected range, not the group's last item.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(_focus(tester, '1M').hasFocus, isTrue);
  });

  testWidgets('horizontal keyboard movement follows RTL reading order', (
    tester,
  ) async {
    final changes = <String>[];
    await tester.pumpWidget(
      _wrap(direction: TextDirection.rtl, onChanged: changes.add),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(changes, ['3Y']);
    expect(
      tester.getCenter(find.text('3Y')).dx,
      lessThan(tester.getCenter(find.text('1Y')).dx),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(changes.last, '1Y');
  });

  testWidgets('accessibility focus connects to keyboard range selection', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final changes = <String>[];
    await tester.pumpWidget(_wrap(onChanged: changes.add));
    final node = tester.getSemantics(find.bySemanticsLabel('Trend: 3M'));
    node.owner!.performAction(node.id, SemanticsAction.focus);
    await tester.pump();
    expect(_focus(tester, '3M').hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(changes, ['1M']);
    semantics.dispose();
  });

  testWidgets('focus survives wrapping, text resizing and option changes', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap());
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    final node = _focus(tester, '1Y');
    await tester.pumpWidget(_wrap(width: 200, textScale: 2));
    await tester.pumpAndSettle();
    expect(_focus(tester, '1Y'), same(node));
    expect(node.hasFocus, isTrue);
    expect(
      tester.getCenter(find.text('All')).dy,
      greaterThan(tester.getCenter(find.text('1M')).dy),
    );
    await tester.pumpWidget(_wrap(width: 200, options: const ['1Y', 'All']));
    await tester.pumpAndSettle();
    expect(node.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('five large ranges wrap into balanced rows instead of 4+1', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        width: 330,
        textScale: 2,
        options: const ['1M', '3M', '1Y', '3Y', '全部'],
      ),
    );
    expect(
      tester.getCenter(find.text('1Y')).dy,
      tester.getCenter(find.text('1M')).dy,
    );
    expect(
      tester.getCenter(find.text('3Y')).dy,
      greaterThan(tester.getCenter(find.text('1M')).dy),
    );
    expect(
      tester.getCenter(find.text('全部')).dy,
      tester.getCenter(find.text('3Y')).dy,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('restores range focus when a retained route is reparented', (
    tester,
  ) async {
    final wide = ValueNotifier(true);
    addTearDown(wide.dispose);
    final retained = KeyedSubtree(
      key: GlobalKey(),
      child: SegmentedRow<String>.inline(
        options: const ['1M', '1Y', 'All'],
        value: '1Y',
        labelOf: (option) => option,
        onChanged: (_) {},
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: FTheme(
          data: FTheme.neutral.light.desktop,
          child: ValueListenableBuilder<bool>(
            valueListenable: wide,
            builder: (context, wide, _) => wide
                ? Row(children: [Expanded(child: retained)])
                : Column(children: [retained]),
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    final focus = _focus(tester, '1Y');
    expect(focus.hasFocus, isTrue);
    wide.value = false;
    await tester.pumpAndSettle();
    expect(_focus(tester, '1Y'), same(focus));
    expect(focus.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large localized labels stay readable on narrow screens', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        width: 160,
        textScale: 2,
        options: const ['过去一个月', '全部历史记录'],
        initialValue: '过去一个月',
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsNothing);
    for (final label in ['过去一个月', '全部历史记录']) {
      final text = tester.widget<Text>(find.text(label));
      expect(text.maxLines, isNull);
      expect(text.overflow, isNull);
    }
  });

  testWidgets('disabled ranges are labelled and cannot activate or focus', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final changes = <String>[];
    await tester.pumpWidget(_wrap(enabled: false, onChanged: changes.add));
    final data = tester
        .getSemantics(find.bySemanticsLabel('Trend: 1Y'))
        .getSemanticsData();
    expect(data.flagsCollection.isSelected, Tristate.isTrue);
    expect(data.flagsCollection.isEnabled, Tristate.isFalse);
    expect(data.hasAction(SemanticsAction.tap), isFalse);
    await tester.tap(find.text('All'));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    expect(_focus(tester, '1Y').hasFocus, isFalse);
    semantics.dispose();
  });

  testWidgets('tap, arrow and accessibility activation each signal once', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final semantics = tester.ensureSemantics();
    final changes = <String>[];
    await tester.pumpWidget(_wrap(onChanged: changes.add, reducedMotion: true));
    await tester.tap(find.text('3M'));
    await tester.pumpAndSettle();
    expect(_focus(tester, '3M').hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    final allNode = tester.getSemantics(find.bySemanticsLabel('Trend: All'));
    allNode.owner!.performAction(allNode.id, SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(changes, ['3M', '1Y', 'All']);
    expect(
      calls.where((call) => call.method == 'HapticFeedback.vibrate'),
      hasLength(3),
    );
    final selected = tester
        .getSemantics(find.bySemanticsLabel('Trend: All'))
        .getSemanticsData();
    expect(selected.flagsCollection.isSelected, Tristate.isTrue);
    for (final animation in tester.widgetList<AnimatedScale>(
      find.descendant(
        of: find.byType(AppSelectionIndicator),
        matching: find.byType(AnimatedScale),
      ),
    )) {
      expect(animation.duration, Duration.zero);
    }
    semantics.dispose();
  });
}
