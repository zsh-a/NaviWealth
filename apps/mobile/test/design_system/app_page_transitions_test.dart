import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/theme/app_page_transitions.dart';
import 'package:naviwealth/design_system/tokens/motion_tokens.dart';

Widget _buildTransition({
  required Animation<double> primary,
  required Animation<double> secondary,
  Size size = const Size(400, 800),
  bool disableAnimations = false,
}) {
  const builder = AppPageTransitionsBuilder();
  return MediaQuery(
    data: MediaQueryData(size: size, disableAnimations: disableAnimations),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Builder(
        builder: (context) => builder.buildTransitions<void>(
          PageRouteBuilder<void>(
            pageBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
          context,
          primary,
          secondary,
          const Text('page'),
        ),
      ),
    ),
  );
}

List<SlideTransition> _ancestorSlides(WidgetTester tester) => tester
    .widgetList<SlideTransition>(
      find.ancestor(
        of: find.text('page'),
        matching: find.byType(SlideTransition),
      ),
    )
    .toList();

void main() {
  testWidgets('outgoing page stays static while the next route pushes in', (
    tester,
  ) async {
    // Page fully entered; the secondary animation must not move or dim it.
    final primary = AnimationController(
      vsync: tester,
      duration: Motion.pageTransition,
      value: 1,
    );
    final secondary = AnimationController(
      vsync: tester,
      duration: Motion.pageTransition,
    );
    addTearDown(primary.dispose);
    addTearDown(secondary.dispose);
    secondary.value = 0.5;

    await tester.pumpWidget(
      _buildTransition(primary: primary, secondary: secondary),
    );

    expect(
      _ancestorSlides(tester).where((s) => s.position.value.dx < 0),
      isEmpty,
    );
    expect(
      find.ancestor(
        of: find.text('page'),
        matching: find.byType(FadeTransition),
      ),
      findsNothing,
    );

    // At rest (nothing pushing over this page) the result is unchanged too.
    secondary.value = 0;
    await tester.pump();
    expect(
      _ancestorSlides(tester).where((s) => s.position.value.dx < 0),
      isEmpty,
    );
    expect(
      find.ancestor(
        of: find.text('page'),
        matching: find.byType(FadeTransition),
      ),
      findsNothing,
    );
  });

  testWidgets('reduce motion keeps a plain cross-fade (no parallax)', (
    tester,
  ) async {
    final primary = AnimationController(
      vsync: tester,
      duration: Motion.pageTransition,
    );
    final secondary = AnimationController(
      vsync: tester,
      duration: Motion.pageTransition,
      value: 0.5,
    );
    addTearDown(primary.dispose);
    addTearDown(secondary.dispose);

    await tester.pumpWidget(
      _buildTransition(
        primary: primary,
        secondary: secondary,
        disableAnimations: true,
      ),
    );

    expect(find.byType(SlideTransition), findsNothing);
    expect(
      find.ancestor(
        of: find.text('page'),
        matching: find.byType(FadeTransition),
      ),
      findsOneWidget,
    );
  });
}
