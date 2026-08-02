import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';

Future<void> _pumpGrid(
  WidgetTester tester, {
  required double width,
  TextScaler textScaler = TextScaler.noScaling,
  bool featuredFirst = true,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: textScaler),
        child: Scaffold(
          body: AdaptiveSummaryGrid(
            items: [
              AdaptiveSummaryTile(
                role: featuredFirst
                    ? AdaptiveSummaryTileRole.featured
                    : AdaptiveSummaryTileRole.standard,
                child: const SizedBox(key: ValueKey('featured'), height: 80),
              ),
              const AdaptiveSummaryTile(
                child: SizedBox(key: ValueKey('second'), height: 60),
              ),
              const AdaptiveSummaryTile(
                child: SizedBox(key: ValueKey('third'), height: 40),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('keeps compact surfaces in content order as one column', (
    tester,
  ) async {
    await _pumpGrid(tester, width: 375);

    final featured = tester.getRect(find.byKey(const ValueKey('featured')));
    final second = tester.getRect(find.byKey(const ValueKey('second')));
    final third = tester.getRect(find.byKey(const ValueKey('third')));
    expect(second.top, greaterThan(featured.bottom));
    expect(third.top, greaterThan(second.bottom));
    expect([featured.left, second.left, third.left], everyElement(0));
  });

  testWidgets('uses a restrained featured span on a three-column canvas', (
    tester,
  ) async {
    await _pumpGrid(tester, width: 1200);

    final featured = tester.getRect(find.byKey(const ValueKey('featured')));
    final second = tester.getRect(find.byKey(const ValueKey('second')));
    final third = tester.getRect(find.byKey(const ValueKey('third')));
    expect(featured.top, second.top);
    expect(featured.width, greaterThan(second.width * 1.9));
    expect(second.left, greaterThan(featured.right));
    expect(third.top, greaterThan(featured.bottom));
  });

  testWidgets('supporting tile becomes a rail only with three columns', (
    tester,
  ) async {
    Future<void> pump(double width) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveSummaryGrid(
              items: [
                AdaptiveSummaryTile(
                  role: AdaptiveSummaryTileRole.supporting,
                  child: SizedBox(key: ValueKey('supporting'), height: 80),
                ),
                AdaptiveSummaryTile(
                  role: AdaptiveSummaryTileRole.featured,
                  child: SizedBox(key: ValueKey('primary'), height: 80),
                ),
              ],
            ),
          ),
        ),
      );
    }

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pump(900);
    final mediumSupporting = tester.getRect(
      find.byKey(const ValueKey('supporting')),
    );
    final mediumPrimary = tester.getRect(find.byKey(const ValueKey('primary')));
    expect(mediumPrimary.top, greaterThan(mediumSupporting.bottom));
    expect(mediumPrimary.width, mediumSupporting.width);

    await pump(1200);
    final wideSupporting = tester.getRect(
      find.byKey(const ValueKey('supporting')),
    );
    final widePrimary = tester.getRect(find.byKey(const ValueKey('primary')));
    expect(widePrimary.top, wideSupporting.top);
    expect(widePrimary.left, greaterThan(wideSupporting.right));
    expect(widePrimary.width, greaterThan(wideSupporting.width * 1.9));
  });

  testWidgets('enlarged text reduces density without wasting a wide canvas', (
    tester,
  ) async {
    await _pumpGrid(
      tester,
      width: 1200,
      textScaler: const TextScaler.linear(2),
      featuredFirst: false,
    );

    final featured = tester.getRect(find.byKey(const ValueKey('featured')));
    final second = tester.getRect(find.byKey(const ValueKey('second')));
    final third = tester.getRect(find.byKey(const ValueKey('third')));
    expect(second.top, featured.top);
    expect(second.left, greaterThan(featured.right));
    expect(third.top, greaterThan(featured.bottom));
  });

  testWidgets('adds no glass or backdrop rendering layer', (tester) async {
    await _pumpGrid(tester, width: 1200);

    expect(find.byType(BackdropFilter), findsNothing);
  });
}
