import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

Widget _wrap(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: brightness == Brightness.light
          ? AppTheme.light()
          : AppTheme.dark(),
      home: FTheme(
        data: buildAppForuiTheme(brightness: brightness, touch: false),
        child: Scaffold(body: child),
      ),
    );

void main() {
  testWidgets(
    'navigation has one accessible label and one working tap action',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var presses = 0;
      await tester.pumpWidget(
        _wrap(
          AppNavRow(
            icon: FLucideIcons.wallet,
            title: 'Portfolio',
            subtitle: 'Review allocation',
            onTap: () => presses++,
          ),
        ),
      );
      final node = find.semantics
          .byLabel('Portfolio, Review allocation')
          .evaluate()
          .single;
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      tester.binding.rootPipelineOwner.visitChildren(
        (owner) =>
            owner.semanticsOwner?.performAction(node.id, SemanticsAction.tap),
      );
      await tester.pump();
      expect(presses, 1);
      await tester.tap(find.text('Portfolio'));
      await tester.pumpAndSettle();
      expect(presses, 2);
      semantics.dispose();
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets('hover and keyboard feedback remain usable in $brightness', (
      tester,
    ) async {
      var presses = 0;
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        _wrap(
          AppTappable(
            focusNode: focus,
            onPress: () => presses++,
            child: const SizedBox(width: 180, height: 48, child: Text('Open')),
          ),
          brightness: brightness,
        ),
      );
      final surface = find.descendant(
        of: find.byType(AppTappable),
        matching: find.byType(AnimatedContainer),
      );
      Color color() =>
          (tester.widget<AnimatedContainer>(surface).decoration!
                  as BoxDecoration)
              .color!;
      expect(color().a, 0);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(700, 500));
      await mouse.moveTo(tester.getCenter(find.text('Open')));
      await tester.pumpAndSettle();
      expect(color().a, greaterThan(0));
      await mouse.removePointer();
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(presses, 1);
    });
  }

  testWidgets('disabled navigation does not expose activation', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _wrap(const AppNavRow(icon: FLucideIcons.wallet, title: 'Unavailable')),
    );
    final data = find.semantics
        .byLabel('Unavailable')
        .evaluate()
        .single
        .getSemanticsData();
    expect(data.hasAction(SemanticsAction.tap), isFalse);
    semantics.dispose();
  });

  testWidgets('absent brief slots do not leave phantom spacing', (
    tester,
  ) async {
    const module = SizedBox(key: ValueKey('module'), height: 40);
    await tester.pumpWidget(
      _wrap(
        const BriefScaffold(
          padding: EdgeInsets.zero,
          atmosphere: false,
          modules: [module],
        ),
      ),
    );
    expect(tester.getTopLeft(find.byKey(const ValueKey('module'))).dy, 0);
  });
}
