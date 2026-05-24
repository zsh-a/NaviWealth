import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';

Future<void> _pumpAt(
  WidgetTester tester, {
  required double width,
  required Widget child,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

void main() {
  const left = SizedBox(key: ValueKey('left'), height: 100);
  const right = SizedBox(key: ValueKey('right'), height: 100);

  testWidgets('stacks vertically below the breakpoint', (tester) async {
    await _pumpAt(
      tester,
      width: 800,
      child: const ResponsiveTwoColumn(left: left, right: right),
    );

    final leftRect = tester.getRect(find.byKey(const ValueKey('left')));
    final rightRect = tester.getRect(find.byKey(const ValueKey('right')));
    expect(rightRect.top, greaterThan(leftRect.bottom));
    expect(leftRect.left, rightRect.left);
  });

  testWidgets('splits into two equal columns at or above the breakpoint', (
    tester,
  ) async {
    await _pumpAt(
      tester,
      width: 1200,
      child: const ResponsiveTwoColumn(left: left, right: right),
    );

    final leftRect = tester.getRect(find.byKey(const ValueKey('left')));
    final rightRect = tester.getRect(find.byKey(const ValueKey('right')));
    expect(leftRect.top, rightRect.top);
    expect(rightRect.left, greaterThan(leftRect.right));
    expect(leftRect.width, rightRect.width);
  });

  testWidgets('breakpoint override applies', (tester) async {
    await _pumpAt(
      tester,
      width: 700,
      child: const ResponsiveTwoColumn(
        left: left,
        right: right,
        breakpoint: 600,
      ),
    );

    final leftRect = tester.getRect(find.byKey(const ValueKey('left')));
    final rightRect = tester.getRect(find.byKey(const ValueKey('right')));
    expect(leftRect.top, rightRect.top);
    expect(rightRect.left, greaterThan(leftRect.right));
  });
}
