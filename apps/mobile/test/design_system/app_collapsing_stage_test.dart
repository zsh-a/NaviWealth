import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';

void main() {
  testWidgets('AppCollapsingStage scales down as the scroll view moves', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            controller: controller,
            children: const [
              AppCollapsingStage(
                key: Key('collapse'),
                collapseExtent: 80,
                minScale: 0.5,
                child: SizedBox(
                  key: Key('stage-box'),
                  height: 160,
                  width: double.infinity,
                  child: ColoredBox(color: Color(0xFF00AABB)),
                ),
              ),
              SizedBox(height: 1600),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Transform scaleOf() {
      return tester.widget<Transform>(
        find.descendant(
          of: find.byKey(const Key('collapse')),
          matching: find.byType(Transform),
        ),
      );
    }

    // storage[0] is the X scale (Z is always 1.0 so getMaxScaleOnAxis is useless).
    expect(scaleOf().transform.storage[0], closeTo(1.0, 0.01));

    controller.jumpTo(120);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(scaleOf().transform.storage[0], lessThan(0.9));
  });

  testWidgets('AppCollapsingScrollHost reveals sticky summary on scroll', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppCollapsingScrollHost(
            collapseExtent: 80,
            stickyBuilder: (context, progress) => AppCollapsedSummaryBar(
              progress: progress,
              showAfter: 0.4,
              child: const Text('sticky-summary'),
            ),
            body: ListView(
              children: const [
                SizedBox(height: 200, child: Text('hero')),
                SizedBox(height: 1600, child: Text('tail')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Fully transparent until threshold — IgnorePointer may still keep the
    // text in the tree, so assert opacity via the host progress path.
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(find.text('sticky-summary'), findsOneWidget);

    scrollable.position.jumpTo(100);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    final opacity = tester
        .widgetList<Opacity>(find.byType(Opacity))
        .map((o) => o.opacity)
        .fold<double>(0, (a, b) => a > b ? a : b);
    expect(opacity, greaterThan(0.5));
  });

  testWidgets('explicit primary controller ignores secondary column scroll', (
    tester,
  ) async {
    final primary = ScrollController();
    final secondary = ScrollController();
    addTearDown(primary.dispose);
    addTearDown(secondary.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppCollapsingScrollHost(
            primaryController: primary,
            collapseExtent: 80,
            stickyBuilder: (context, progress) => AppCollapsedSummaryBar(
              progress: progress,
              showAfter: 0.4,
              child: const Text('primary-only-summary'),
            ),
            body: Row(
              children: [
                Expanded(
                  child: ListView(
                    controller: primary,
                    children: const [SizedBox(height: 1600)],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: secondary,
                    children: const [SizedBox(height: 1600)],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Opacity summaryOpacity() => tester.widget<Opacity>(
      find
          .ancestor(
            of: find.text('primary-only-summary'),
            matching: find.byType(Opacity),
          )
          .first,
    );

    secondary.jumpTo(100);
    await tester.pump();
    expect(summaryOpacity().opacity, 0);

    primary.jumpTo(100);
    await tester.pump();
    expect(summaryOpacity().opacity, greaterThan(0.5));
  });

  testWidgets('AppCollapsedSummaryBar hides when not visible', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppCollapsedSummaryBar(visible: false, child: Text('summary')),
        ),
      ),
    );
    // Still in tree under Opacity 0 / IgnorePointer + glass chrome.
    expect(find.text('summary'), findsOneWidget);
    final hidden = tester
        .widgetList<Opacity>(find.byType(Opacity))
        .map((o) => o.opacity)
        .reduce((a, b) => a < b ? a : b);
    expect(hidden, 0);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppCollapsedSummaryBar(visible: true, child: Text('summary')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final shown = tester
        .widgetList<Opacity>(find.byType(Opacity))
        .map((o) => o.opacity)
        .reduce((a, b) => a > b ? a : b);
    expect(shown, 1);
    // Tonal glass chrome (no live BackdropFilter — matches FloatingGlassNav).
    expect(find.byType(DecoratedBox), findsWidgets);
  });

  test('appScrollCollapseProgress clamps into 0–1', () {
    expect(appScrollCollapseProgress(pixels: -10, extent: 100), 0);
    expect(appScrollCollapseProgress(pixels: 50, extent: 100), 0.5);
    expect(appScrollCollapseProgress(pixels: 200, extent: 100), 1);
  });
}
