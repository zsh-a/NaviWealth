import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';

Widget _frame({
  required Widget primary,
  Widget? secondary,
  AdaptiveFrameLayout layout = AdaptiveFrameLayout.singleColumn,
  double maxWidth = AdaptiveMaxWidth.page,
  double columnBreakpoint = Breakpoints.contentTwoColumn,
}) {
  return MaterialApp(
    home: Scaffold(
      body: AdaptiveContentFrame(
        primary: primary,
        secondary: secondary,
        layout: layout,
        maxWidth: maxWidth,
        columnBreakpoint: columnBreakpoint,
      ),
    ),
  );
}

void main() {
  testWidgets('stacks secondary content below the column breakpoint', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _frame(
        layout: AdaptiveFrameLayout.twoColumn,
        primary: const SizedBox(key: ValueKey('primary'), height: 120),
        secondary: const SizedBox(key: ValueKey('secondary'), height: 80),
      ),
    );

    final primary = tester.getTopLeft(find.byKey(const ValueKey('primary')));
    final secondary = tester.getTopLeft(
      find.byKey(const ValueKey('secondary')),
    );
    expect(secondary.dx, primary.dx);
    expect(secondary.dy, greaterThan(primary.dy));
  });

  testWidgets('uses columns at the shared content breakpoint', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _frame(
        layout: AdaptiveFrameLayout.twoColumn,
        primary: const SizedBox(key: ValueKey('primary'), height: 120),
        secondary: const SizedBox(key: ValueKey('secondary'), height: 80),
      ),
    );

    final primary = tester.getTopLeft(find.byKey(const ValueKey('primary')));
    final secondary = tester.getTopLeft(
      find.byKey(const ValueKey('secondary')),
    );
    expect(secondary.dy, primary.dy);
    expect(secondary.dx, greaterThan(primary.dx));
  });

  testWidgets('centers and caps a single-column page', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _frame(
        maxWidth: AdaptiveMaxWidth.narrow,
        primary: const SizedBox(
          key: ValueKey('primary'),
          width: double.infinity,
          height: 120,
        ),
      ),
    );

    final size = tester.getSize(find.byKey(const ValueKey('primary')));
    final left = tester.getTopLeft(find.byKey(const ValueKey('primary'))).dx;
    expect(size.width, AdaptiveMaxWidth.narrow);
    expect(left, (1600 - AdaptiveMaxWidth.narrow) / 2);
  });
}
