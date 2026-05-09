import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';

Future<void> _pumpAt(
  WidgetTester tester, {
  required double width,
  required Widget child,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(home: child));
}

void main() {
  const bodyKey = ValueKey('page-body');
  const asideKey = ValueKey('page-aside');

  testWidgets('caps body width on desktop and centers it', (tester) async {
    await _pumpAt(
      tester,
      width: 2000,
      child: const PageScaffold(
        body: SizedBox(key: bodyKey, height: 200, child: ColoredBox(color: Colors.red)),
      ),
    );

    final body = tester.getRect(find.byKey(bodyKey));
    // Cap at Spacing.contentMaxWidth = 1200; allow 1px slop.
    expect(body.width, closeTo(Spacing.contentMaxWidth, 1));
    // Centered horizontally within the 2000-wide viewport.
    final centerSlack = (2000 - body.width) / 2;
    expect(body.left, closeTo(centerSlack, 1));
  });

  testWidgets('does not cap body width on mobile', (tester) async {
    await _pumpAt(
      tester,
      width: 400,
      child: const PageScaffold(
        body: SizedBox(key: bodyKey, height: 200, child: ColoredBox(color: Colors.red)),
      ),
    );

    final body = tester.getRect(find.byKey(bodyKey));
    // Body fills the page minus the default mobile page padding (16 each side).
    expect(body.width, closeTo(400 - 32, 1));
  });

  testWidgets('renders aside on desktop and hides it below desktop', (tester) async {
    await _pumpAt(
      tester,
      width: 1500,
      child: const PageScaffold(
        aside: SizedBox(key: asideKey, height: 200, child: ColoredBox(color: Colors.blue)),
        body: SizedBox(key: bodyKey, height: 200, child: ColoredBox(color: Colors.red)),
      ),
    );

    expect(find.byKey(asideKey), findsOneWidget);
    final aside = tester.getRect(find.byKey(asideKey));
    final body = tester.getRect(find.byKey(bodyKey));
    expect(body.left, greaterThan(aside.right));
  });

  testWidgets('aside is hidden below the desktop breakpoint', (tester) async {
    await _pumpAt(
      tester,
      width: 1000,
      child: const PageScaffold(
        aside: SizedBox(key: asideKey, height: 200, child: ColoredBox(color: Colors.blue)),
        body: SizedBox(key: bodyKey, height: 200, child: ColoredBox(color: Colors.red)),
      ),
    );

    expect(find.byKey(asideKey), findsNothing);
  });
}
