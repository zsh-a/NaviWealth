import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: FTheme(
      data: FTheme.neutral.light.desktop,
      child: FScaffold(childPad: false, child: Center(child: child)),
    ),
  );
}

void main() {
  group('AppFormSection (flat)', () {
    testWidgets('renders title and inserts gap between children', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const SizedBox(
            width: 300,
            child: AppFormSection(
              title: 'Basics',
              children: [
                SizedBox(key: Key('first'), height: 10),
                SizedBox(key: Key('second'), height: 10),
                SizedBox(key: Key('third'), height: 10),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Basics'), findsOneWidget);

      final firstBottom = tester.getBottomLeft(find.byKey(const Key('first')));
      final secondTop = tester.getTopLeft(find.byKey(const Key('second')));
      final secondBottom = tester.getBottomLeft(
        find.byKey(const Key('second')),
      );
      final thirdTop = tester.getTopLeft(find.byKey(const Key('third')));

      expect(secondTop.dy - firstBottom.dy, AppSpacing.s12);
      expect(thirdTop.dy - secondBottom.dy, AppSpacing.s12);

      // Title sits above the first child with an s8 gap.
      final titleBottom = tester.getBottomLeft(find.text('Basics'));
      expect(firstBottom.dy - 10 - titleBottom.dy, AppSpacing.s8);
    });

    testWidgets('honours a custom gap', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SizedBox(
            width: 300,
            child: AppFormSection(
              gap: AppSpacing.s4,
              children: [
                SizedBox(key: Key('first'), height: 10),
                SizedBox(key: Key('second'), height: 10),
              ],
            ),
          ),
        ),
      );

      final firstBottom = tester.getBottomLeft(find.byKey(const Key('first')));
      final secondTop = tester.getTopLeft(find.byKey(const Key('second')));
      expect(secondTop.dy - firstBottom.dy, AppSpacing.s4);
    });
  });

  group('AppFormSection.collapsible', () {
    testWidgets('collapsed body is offstage and excluded from focus', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          AppFormSection.collapsible(
            title: 'Advanced',
            summary: 'Optional details',
            expanded: false,
            onChanged: (_) {},
            children: const [SizedBox(key: Key('body'), height: 10)],
          ),
        ),
      );

      expect(find.text('Advanced'), findsOneWidget);
      expect(find.text('Optional details'), findsOneWidget);

      final body = find.byKey(const Key('body'), skipOffstage: false);
      final offstage = tester.widget<Offstage>(
        find.byWidgetPredicate(
          (widget) => widget is Offstage && widget.child is ExcludeFocus,
          skipOffstage: false,
        ),
      );
      expect(offstage.offstage, isTrue);

      final excludeFocus = tester.widget<ExcludeFocus>(
        find.ancestor(of: body, matching: find.byType(ExcludeFocus)),
      );
      expect(excludeFocus.excluding, isTrue);

      final excludeSemantics = tester.widget<ExcludeSemantics>(
        find.ancestor(of: body, matching: find.byType(ExcludeSemantics)),
      );
      expect(excludeSemantics.excluding, isTrue);

      // Body stays mounted but hidden.
      expect(body, findsOneWidget);
    });

    testWidgets('expanded body is onstage and focusable', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AppFormSection.collapsible(
            title: 'Advanced',
            expanded: true,
            onChanged: (_) {},
            children: const [SizedBox(key: Key('body'), height: 10)],
          ),
        ),
      );

      final offstage = tester.widget<Offstage>(
        find.byWidgetPredicate(
          (widget) => widget is Offstage && widget.child is ExcludeFocus,
        ),
      );
      expect(offstage.offstage, isFalse);

      final excludeFocus = tester.widget<ExcludeFocus>(
        find.byWidgetPredicate(
          (widget) =>
              widget is ExcludeFocus && widget.child is ExcludeSemantics,
        ),
      );
      expect(excludeFocus.excluding, isFalse);

      final excludeSemantics = tester.widget<ExcludeSemantics>(
        find.byWidgetPredicate(
          (widget) => widget is ExcludeSemantics && widget.child is Column,
        ),
      );
      expect(excludeSemantics.excluding, isFalse);
    });

    testWidgets('tapping the header reports the toggle via onChanged', (
      tester,
    ) async {
      var expanded = false;
      await tester.pumpWidget(
        _wrap(
          StatefulBuilder(
            builder: (context, setState) => AppFormSection.collapsible(
              title: 'Advanced',
              icon: FLucideIcons.slidersHorizontal,
              expanded: expanded,
              onChanged: (value) => setState(() => expanded = value),
              children: const [SizedBox(key: Key('body'), height: 10)],
            ),
          ),
        ),
      );

      Finder bodyOffstage() => find.byWidgetPredicate(
        (widget) => widget is Offstage && widget.child is ExcludeFocus,
        skipOffstage: false,
      );

      expect(tester.widget<Offstage>(bodyOffstage()).offstage, isTrue);

      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();

      expect(expanded, isTrue);
      expect(tester.widget<Offstage>(bodyOffstage()).offstage, isFalse);

      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();

      expect(expanded, isFalse);
      expect(tester.widget<Offstage>(bodyOffstage()).offstage, isTrue);
    });
  });
}
