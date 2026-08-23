import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';

Widget _wrap(Widget child, {bool disableAnimations = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  group('staggeredSummaryTiles', () {
    test('preserves order and roles, wraps children in FadeSlideIn', () {
      final tiles = staggeredSummaryTiles(const [
        AdaptiveSummaryTile(
          role: AdaptiveSummaryTileRole.featured,
          child: Text('a'),
        ),
        AdaptiveSummaryTile(child: Text('b')),
        AdaptiveSummaryTile(
          role: AdaptiveSummaryTileRole.continuous,
          child: Text('c'),
        ),
      ]);

      expect(tiles.length, 3);
      expect(tiles[0].role, AdaptiveSummaryTileRole.featured);
      expect(tiles[1].role, AdaptiveSummaryTileRole.standard);
      expect(tiles[2].role, AdaptiveSummaryTileRole.continuous);
      for (final tile in tiles) {
        expect(tile.child, isA<FadeSlideIn>());
      }
    });

    testWidgets('staggers entrances on the shared Motion cadence', (
      tester,
    ) async {
      final tiles = staggeredSummaryTiles(const [
        AdaptiveSummaryTile(child: Text('a')),
        AdaptiveSummaryTile(child: Text('b')),
        AdaptiveSummaryTile(child: Text('c')),
      ]);
      await tester.pumpWidget(
        _wrap(AdaptiveSummaryGrid(items: tiles, maxColumns: 1)),
      );

      final slides = tester
          .widgetList<FadeSlideIn>(find.byType(FadeSlideIn))
          .toList();
      expect(slides.length, 3);
      expect(slides[0].delay, Duration.zero);
      expect(slides[1].delay, Motion.staggerDelayFor(1, 3));
      expect(slides[2].delay, Motion.staggerDelayFor(2, 3));

      // Every child is in the tree from the first frame — the stagger is a
      // fade/slide only, never a layout shift.
      expect(find.text('a'), findsOneWidget);
      expect(find.text('c'), findsOneWidget);
    });

    testWidgets('renders fully under reduce-motion', (tester) async {
      final tiles = staggeredSummaryTiles(const [
        AdaptiveSummaryTile(child: Text('a')),
        AdaptiveSummaryTile(child: Text('b')),
      ]);
      await tester.pumpWidget(
        _wrap(
          AdaptiveSummaryGrid(items: tiles, maxColumns: 1),
          disableAnimations: true,
        ),
      );

      final opacity = tester.widgetList<FadeTransition>(
        find.byWidgetPredicate(
          (widget) =>
              widget is FadeTransition && widget.child is AnimatedBuilder,
        ),
      );
      expect(opacity.length, 2);
      for (final fade in opacity) {
        expect(fade.opacity.value, 1);
      }
    });
  });
}
