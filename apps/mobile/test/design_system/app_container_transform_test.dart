import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

const _closedKey = ValueKey<String>('closed');

Widget _wrap({required Widget home, bool disableAnimations = false}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: FTheme(
      data: FTheme.neutral.light.desktop,
      child: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: home,
      ),
    ),
  );
}

Widget _host({bool enabled = true}) {
  return Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 100, top: 100),
        child: SizedBox(
          key: _closedKey,
          width: 120,
          height: 60,
          child: AppContainerTransform(
            enabled: enabled,
            closedColor: Colors.white,
            closedBorderRadius: BorderRadius.circular(AppRadius.lg),
            closedBuilder: (context, open) => GestureDetector(
              onTap: open,
              child: const ColoredBox(
                color: Colors.white,
                child: Center(child: Text('closed')),
              ),
            ),
            openBuilder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('close'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// The open route's child is fitted into the morphing window during the
/// transition, so `FittedBox` only exists mid-flight and renders at the
/// current window size — the stable observable for "container is morphing".
Size _morphWindowSize(WidgetTester tester) {
  final fitted = tester.widgetList<FittedBox>(find.byType(FittedBox));
  expect(fitted, isNotEmpty);
  return tester.getSize(find.byWidget(fitted.first));
}

void main() {
  testWidgets('closed → open morphs the container from the source rect to '
      'full screen', (tester) async {
    await tester.pumpWidget(_wrap(home: _host()));
    final source = tester.getRect(find.byKey(_closedKey));
    expect(source.size, const Size(120, 60));
    expect(find.byType(OpenContainer<void>), findsOneWidget);

    await tester.tap(find.text('closed'));
    await tester.pump();
    // Mid-flight: the morphing window sits strictly between the source
    // rect and the full 800x600 test surface.
    await tester.pump(Motion.pageTransition ~/ 2);

    expect(tester.hasRunningAnimations, isTrue);
    expect(find.text('close'), findsOneWidget);
    final mid = _morphWindowSize(tester);
    expect(mid.width, greaterThan(source.width));
    expect(mid.width, lessThan(800));
    expect(mid.height, greaterThan(source.height));
    expect(mid.height, lessThan(600));
    // The off-center source rect also translates: the open content's center
    // has not reached the screen center yet.
    expect(
      tester.getCenter(find.text('close')),
      isNot(equals(const Offset(400, 300))),
    );

    await tester.pumpAndSettle();
    expect(find.byType(FittedBox), findsNothing);
    expect(tester.getCenter(find.text('close')), const Offset(400, 300));
  });

  testWidgets('pop runs the morph in reverse back toward the source rect', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(home: _host()));
    final source = tester.getRect(find.byKey(_closedKey));
    await tester.tap(find.text('closed'));
    await tester.pumpAndSettle();
    expect(find.byType(FittedBox), findsNothing);

    await tester.tap(find.text('close'));
    await tester.pump();
    await tester.pump(Motion.pageTransition ~/ 2);

    // Mid-reverse: the window is shrinking back towards the source rect.
    expect(tester.hasRunningAnimations, isTrue);
    final mid = _morphWindowSize(tester);
    expect(mid.width, lessThan(800));
    expect(mid.width, greaterThan(source.width));
    expect(mid.height, lessThan(600));
    expect(mid.height, greaterThan(source.height));

    await tester.pumpAndSettle();
    expect(find.byType(FittedBox), findsNothing);
    expect(find.text('closed'), findsOneWidget);
    expect(find.text('close'), findsNothing);
  });

  testWidgets('reduce motion degrades to the standard app route (no '
      'OpenContainer)', (tester) async {
    await tester.pumpWidget(_wrap(home: _host(), disableAnimations: true));
    expect(find.byType(OpenContainer<void>), findsNothing);

    await tester.tap(find.text('closed'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    // Fallback path: an ordinary pushed route — the closed content stays
    // put (OpenContainer would have swapped it for a SizedBox placeholder).
    expect(find.text('closed'), findsOneWidget);
    expect(find.byType(FittedBox), findsNothing);
    expect(
      find.ancestor(
        of: find.text('close'),
        matching: find.byType(FadeTransition),
      ),
      findsWidgets,
    );

    await tester.pumpAndSettle();
    expect(find.text('close'), findsOneWidget);
  });

  testWidgets('disabled (master-detail) falls back to the standard route', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(home: _host(enabled: false)));
    expect(find.byType(OpenContainer<void>), findsNothing);

    await tester.tap(find.text('closed'));
    await tester.pump();
    await tester.pump(Motion.pageTransition ~/ 2);
    expect(find.text('closed'), findsOneWidget);
    expect(find.byType(FittedBox), findsNothing);

    await tester.pumpAndSettle();
    expect(find.text('close'), findsOneWidget);
  });
}
