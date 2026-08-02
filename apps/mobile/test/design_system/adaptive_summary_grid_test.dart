import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';

Future<void> _pumpGrid(
  WidgetTester tester, {
  required double width,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: textScaler),
        child: const Scaffold(
          body: AdaptiveSummaryGrid(
            items: [
              AdaptiveSummaryTile(
                span: AdaptiveSummaryTileSpan.featured,
                child: SizedBox(key: ValueKey('featured'), height: 80),
              ),
              AdaptiveSummaryTile(
                child: SizedBox(key: ValueKey('second'), height: 60),
              ),
              AdaptiveSummaryTile(
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

  testWidgets('enlarged text returns a wide canvas to one column', (
    tester,
  ) async {
    await _pumpGrid(
      tester,
      width: 1200,
      textScaler: const TextScaler.linear(2),
    );

    final featured = tester.getRect(find.byKey(const ValueKey('featured')));
    final second = tester.getRect(find.byKey(const ValueKey('second')));
    expect(second.top, greaterThan(featured.bottom));
    expect(second.width, featured.width);
  });

  testWidgets('adds no glass or backdrop rendering layer', (tester) async {
    await _pumpGrid(tester, width: 1200);

    expect(find.byType(BackdropFilter), findsNothing);
  });
}
