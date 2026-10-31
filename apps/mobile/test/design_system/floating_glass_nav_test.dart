import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

const _tabs = [
  FloatingNavTab(
    icon: FLucideIcons.house,
    selectedIcon: FLucideIcons.house,
    label: 'Today',
  ),
  FloatingNavTab(
    icon: FLucideIcons.wallet,
    selectedIcon: FLucideIcons.wallet,
    label: 'Wealth',
  ),
];

Widget _nav({
  required ValueChanged<int> onIndexChanged,
  required VoidCallback? onAssistant,
  List<FloatingNavTab> items = _tabs,
  String? assistantLabel = 'Ask AI',
  double width = 360,
  Brightness brightness = Brightness.light,
  double textScale = 1,
  int selectedIndex = 0,
  AppVisualStyle visualStyle = AppVisualStyle.refined,
  bool touch = false,
}) => MaterialApp(
  theme: brightness == Brightness.light
      ? AppTheme.light(visualStyle: visualStyle)
      : AppTheme.dark(visualStyle: visualStyle),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: AppThemeScope(
    data: resolveAppTheme(
      ThemeInputs(
        brightness: brightness,
        marketMode: MarketColorMode.redUpGreenDown,
        visualStyle: visualStyle,
      ),
    ),
    child: FTheme(
      data: buildAppForuiTheme(
        brightness: brightness,
        touch: touch,
        visualStyle: visualStyle,
      ),
      child: Scaffold(
        body: Center(
          child: RepaintBoundary(
            key: const ValueKey('nav-paint'),
            child: SizedBox(
              width: width,
              child: FloatingGlassNavBar(
                items: items,
                selectedIndex: selectedIndex,
                onIndexChanged: onIndexChanged,
                onAssistantAction: onAssistant,
                assistantLabel: assistantLabel,
                assistantSemanticLabel: 'Open assistant conversation',
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

const _fourTabs = [
  FloatingNavTab(
    icon: FLucideIcons.house,
    selectedIcon: FLucideIcons.house,
    label: 'Today',
  ),
  FloatingNavTab(
    icon: FLucideIcons.receipt,
    selectedIcon: FLucideIcons.receipt,
    label: 'Activity',
  ),
  FloatingNavTab(
    icon: FLucideIcons.wallet,
    selectedIcon: FLucideIcons.wallet,
    label: 'Wealth',
  ),
  FloatingNavTab(
    icon: FLucideIcons.lightbulb,
    selectedIcon: FLucideIcons.lightbulb,
    label: 'Plan',
  ),
];

void main() {
  for (final brightness in Brightness.values) {
    for (final visualStyle in AppVisualStyle.values) {
      testWidgets(
        'touch selection does not darken the previous tab: '
        '${brightness.name}/${visualStyle.name}',
        (tester) async {
          var selected = 0;
          await tester.pumpWidget(
            StatefulBuilder(
              builder: (context, setState) => _nav(
                brightness: brightness,
                visualStyle: visualStyle,
                touch: true,
                selectedIndex: selected,
                onIndexChanged: (index) => setState(() => selected = index),
                onAssistant: () {},
              ),
            ),
          );
          await tester.pumpAndSettle();
          final previousTab = find.ancestor(
            of: find.text('Today'),
            matching: find.byType(AppActionTappable),
          );
          // Empty inset, clear of the icon, text, rounded edge and indicator.
          final sample = tester.getTopLeft(previousTab) + const Offset(24, 8);
          final before = await _samplePixel(tester, sample);
          await tester.tap(find.text('Wealth'));
          await tester.pump();
          final frames = <Color>[];
          for (var frame = 0; frame < 10; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            frames.add(await _samplePixel(tester, sample));
          }
          await tester.pumpAndSettle();
          final after = await _samplePixel(tester, sample);
          for (var frame = 0; frame < frames.length; frame++) {
            final color = frames[frame];
            for (final channel in [
              (before.r, after.r, color.r),
              (before.g, after.g, color.g),
              (before.b, after.b, color.b),
            ]) {
              final lower = channel.$1 < channel.$2 ? channel.$1 : channel.$2;
              expect(
                channel.$3,
                greaterThanOrEqualTo(lower - 2 / 255),
                reason:
                    'Unpressed tab must fade without a dark pulse '
                    'at frame $frame; $before -> $color -> $after',
              );
            }
          }
          expect(selected, 1);
          expect(tester.takeException(), isNull);
        },
        variant: const TargetPlatformVariant({
          TargetPlatform.android,
          TargetPlatform.iOS,
        }),
      );
    }
  }

  for (final scale in [2.0, 3.0]) {
    testWidgets('enlarged navigation labels retain their scale at $scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        _nav(onIndexChanged: (_) {}, onAssistant: () {}, textScale: scale),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(FloatingGlassNavBar)).height,
        greaterThan(kFloatingGlassNavBarHeight),
      );
      expect(
        MediaQuery.textScalerOf(tester.element(find.text('Today'))).scale(11),
        11 * scale,
      );
    });
  }

  for (final brightness in Brightness.values) {
    for (final width in [360.0, 500.0]) {
      testWidgets('one semantic control per destination: $brightness $width', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        final selected = <int>[];
        var assistantTaps = 0;
        await tester.pumpWidget(
          _nav(
            brightness: brightness,
            width: width,
            onIndexChanged: selected.add,
            onAssistant: () => assistantTaps += 1,
          ),
        );

        final buttons = find.semantics.byPredicate(
          (node) => node.getSemanticsData().flagsCollection.isButton,
        );
        expect(buttons.evaluate(), hasLength(3));
        final today = find.semantics
            .byLabel('Today')
            .evaluate()
            .single
            .getSemanticsData();
        final wealth = find.semantics
            .byLabel('Wealth')
            .evaluate()
            .single
            .getSemanticsData();
        expect(today.flagsCollection.isSelected, ui.Tristate.isTrue);
        expect(wealth.flagsCollection.isSelected, ui.Tristate.isFalse);
        for (final button in buttons.evaluate()) {
          expect(
            button.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
          );
        }
        expect(find.semantics.byLabel('Ask AI').evaluate(), isEmpty);

        tester.semantics.tap(find.semantics.byLabel('Wealth'));
        tester.semantics.tap(
          find.semantics.byLabel('Open assistant conversation'),
        );
        await tester.pumpAndSettle();
        expect(selected, [1]);
        expect(assistantTaps, 1);
        semantics.dispose();
      });
    }
  }

  testWidgets('Tab follows destinations and activation ignores key repeats', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final selected = <int>[];
    var assistantTaps = 0;
    await tester.pumpWidget(
      _nav(onIndexChanged: selected.add, onAssistant: () => assistantTaps += 1),
    );

    for (final label in ['Today', 'Wealth', 'Open assistant conversation']) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final data = find.semantics
          .byLabel(label)
          .evaluate()
          .single
          .getSemanticsData();
      expect(data.flagsCollection.isFocused, ui.Tristate.isTrue);
      for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
        await tester.sendKeyDownEvent(key);
        await tester.sendKeyRepeatEvent(key);
        await tester.sendKeyUpEvent(key);
      }
    }
    expect(selected, [0, 0, 1, 1]);
    expect(assistantTaps, 2);
    await tester.pumpAndSettle();
    semantics.dispose();
  });
  testWidgets(
    'assistant is a separate action with its own target and no tab change',
    (tester) async {
      final selected = <int>[];
      var assistantTaps = 0;
      await tester.pumpWidget(
        _nav(
          items: _fourTabs,
          onIndexChanged: selected.add,
          onAssistant: () => assistantTaps++,
        ),
      );
      final destinations = find.byKey(
        const ValueKey('floating-nav.destinations'),
      );
      final assistant = find.byKey(const ValueKey('floating-nav.assistant'));
      final navRect = tester.getRect(destinations);
      final aiRect = tester.getRect(assistant);
      expect(aiRect.left - navRect.right, AppSpacing.s12);
      expect(aiRect.center.dy, navRect.center.dy);
      expect(aiRect.size.shortestSide, greaterThanOrEqualTo(48));
      expect(
        find.ancestor(of: assistant, matching: find.byType(AppGlassSurface)),
        findsNothing,
      );
      expect(find.byType(AppGlassSurface), findsOneWidget);
      await tester.tapAt(
        Offset(navRect.right + AppSpacing.s6, navRect.center.dy),
      );
      expect(selected, isEmpty);
      expect(assistantTaps, 0);
      await tester.tap(assistant);
      expect(selected, isEmpty);
      expect(assistantTaps, 1);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  for (final scale in [1.0, 2.0, 3.0]) {
    testWidgets(
      'four destinations retain touch targets on a narrow dock at $scale',
      (tester) async {
        await tester.pumpWidget(
          _nav(
            width: 288,
            textScale: scale,
            items: _fourTabs,
            onIndexChanged: (_) {},
            onAssistant: () {},
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final tab in _fourTabs) {
          final target = find.ancestor(
            of: find.text(tab.label),
            matching: find.byType(AppActionTappable),
          );
          expect(tester.getSize(target).width, greaterThanOrEqualTo(48));
          expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
        }
        final action = find.byKey(const ValueKey('floating-nav.assistant'));
        final destinations = find.byKey(
          const ValueKey('floating-nav.destinations'),
        );
        expect(
          tester.getRect(action).center.dy,
          tester.getRect(destinations).center.dy,
        );
        expect(tester.getSize(action), const Size(64, 64));
        expect(find.text('Ask AI'), findsNothing);
      },
    );
  }

  testWidgets('assistant label yields to page labels at large text sizes', (
    tester,
  ) async {
    await tester.pumpWidget(
      _nav(width: 500, onIndexChanged: (_) {}, onAssistant: () {}),
    );
    expect(find.text('Ask AI'), findsOneWidget);
    await tester.pumpWidget(
      _nav(
        width: 500,
        textScale: 3,
        onIndexChanged: (_) {},
        onAssistant: () {},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ask AI'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'large Chinese destination names remain readable on narrow screens',
    (tester) async {
      const labels = ['今日', '记录', '资产', '规划'];
      final tabs = [
        for (var i = 0; i < _fourTabs.length; i++)
          FloatingNavTab(
            icon: _fourTabs[i].icon,
            selectedIcon: _fourTabs[i].selectedIcon,
            label: labels[i],
          ),
      ];
      await tester.pumpWidget(
        _nav(
          width: 288,
          textScale: 3,
          items: tabs,
          onIndexChanged: (_) {},
          onAssistant: () {},
        ),
      );
      await tester.pumpAndSettle();
      for (final label in labels) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(label),
        );
        expect(paragraph.didExceedMaxLines, isFalse);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('destinations fill the dock when assistant is unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(
      _nav(width: 360, onIndexChanged: (_) {}, onAssistant: null),
    );
    expect(find.byKey(const ValueKey('floating-nav.assistant')), findsNothing);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('floating-nav.destinations')))
          .width,
      360,
    );
    expect(tester.getSize(find.byType(FloatingGlassNavBar)).height, 64);
  });
}

Future<Color> _samplePixel(WidgetTester tester, Offset globalPosition) async {
  return (await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('nav-paint')),
    );
    final position = boundary.globalToLocal(globalPosition);
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final offset =
        (position.dy.floor() * image.width + position.dx.floor()) * 4;
    final color = Color.fromARGB(
      bytes!.getUint8(offset + 3),
      bytes.getUint8(offset),
      bytes.getUint8(offset + 1),
      bytes.getUint8(offset + 2),
    );
    image.dispose();
    return color;
  }))!;
}
