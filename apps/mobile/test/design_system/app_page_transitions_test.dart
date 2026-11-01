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
      findsOneWidget,
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
      findsOneWidget,
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

  testWidgets(
    'removed animations keep the page fully visible with no displacement',
    (tester) async {
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

      expect(_ancestorSlides(tester).single.position.value, Offset.zero);
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
      expect(
        find.ancestor(
          of: find.text('page'),
          matching: find.byType(FadeTransition),
        ),
        findsOneWidget,
      );
    },
  );
  for (final width in [400.0, 1440.0]) {
    testWidgets('detail motion stays within 16dp at width $width', (
      tester,
    ) async {
      const primary = AlwaysStoppedAnimation<double>(0);
      const secondary = AlwaysStoppedAnimation<double>(0);
      await tester.pumpWidget(
        _buildTransition(
          primary: primary,
          secondary: secondary,
          size: Size(width, 800),
        ),
      );
      expect(_ancestorSlides(tester).single.position.value.dx * width, 16);
    });
  }

  testWidgets('iOS reduced motion fades details without spatial motion', (
    tester,
  ) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );
    await tester.pumpWidget(
      _buildTransition(
        primary: const AlwaysStoppedAnimation<double>(0.5),
        secondary: const AlwaysStoppedAnimation<double>(0.5),
      ),
    );
    expect(_ancestorSlides(tester).single.position.value, Offset.zero);
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
      inExclusiveRange(0, 1),
    );
  });
}
