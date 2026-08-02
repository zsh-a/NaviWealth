import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';

Future<void> _pump(
  WidgetTester tester, {
  required double width,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: textScaler),
        child: const Scaffold(
          body: AdaptiveSupportingPane(
            primary: SizedBox(key: ValueKey('primary'), height: 100),
            supporting: SizedBox(key: ValueKey('supporting'), height: 80),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('stacks in content order below the local breakpoint', (
    tester,
  ) async {
    await _pump(tester, width: 900);

    final primary = tester.getRect(find.byKey(const ValueKey('primary')));
    final supporting = tester.getRect(find.byKey(const ValueKey('supporting')));
    expect(supporting.left, primary.left);
    expect(supporting.top, greaterThan(primary.bottom));
  });

  testWidgets('uses a fixed supporting rail on a wide surface', (tester) async {
    await _pump(tester, width: 1200);

    final primary = tester.getRect(find.byKey(const ValueKey('primary')));
    final supporting = tester.getRect(find.byKey(const ValueKey('supporting')));
    expect(supporting.top, primary.top);
    expect(supporting.left, greaterThan(primary.right));
    expect(supporting.width, kAdaptiveSupportingPaneWidth);
  });

  testWidgets('large text restores a single reading flow', (tester) async {
    await _pump(tester, width: 1200, textScaler: const TextScaler.linear(2));

    final primary = tester.getRect(find.byKey(const ValueKey('primary')));
    final supporting = tester.getRect(find.byKey(const ValueKey('supporting')));
    expect(supporting.left, primary.left);
    expect(supporting.top, greaterThan(primary.bottom));
  });
}
