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
  testWidgets('outgoing page slides and dims while the next route pushes in', (
    tester,
  ) async {
    // Page fully entered; only the parallax (secondary) animation may move it.
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

    // iOS-style parallax: the outgoing page drifts in the exit direction
    // (negative x, bounded at ~30% width) and fades slightly instead of
    // freezing underneath the incoming page.
    final slides = _ancestorSlides(tester);
    final parallax = slides.where((s) => s.position.value.dx < 0).toList();
    expect(parallax, hasLength(1));
    expect(parallax.single.position.value.dx, greaterThanOrEqualTo(-0.3));

    final fade = tester.widget<FadeTransition>(
      find.ancestor(
        of: find.text('page'),
        matching: find.byType(FadeTransition),
      ),
    );
    expect(fade.opacity.value, lessThan(1));
    expect(fade.opacity.value, greaterThan(0.75));

    // At rest (nothing pushing over this page) there is no offset or dim.
    secondary.value = 0;
    await tester.pump();
    expect(
      _ancestorSlides(tester).where((s) => s.position.value.dx < 0),
      isEmpty,
    );
    expect(
      tester
          .widget<FadeTransition>(
            find.ancestor(
              of: find.text('page'),
              matching: find.byType(FadeTransition),
            ),
          )
          .opacity
          .value,
      1,
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
