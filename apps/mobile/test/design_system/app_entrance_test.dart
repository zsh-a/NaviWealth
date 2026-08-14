import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';

Widget _wrap(Widget child, {bool disableAnimations = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: child,
    ),
  );
}

Opacity _entranceOpacity(WidgetTester tester) {
  return tester.widget<Opacity>(
    find.byWidgetPredicate(
      (widget) => widget is Opacity && widget.child is Transform,
    ),
  );
}

void main() {
  testWidgets('fades and slides in, then settles at rest', (tester) async {
    await tester.pumpWidget(_wrap(const AppEntrance(child: Text('hello'))));

    expect(_entranceOpacity(tester).opacity, 0);

    await tester.pump(const Duration(milliseconds: 110));
    final mid = _entranceOpacity(tester).opacity;
    expect(mid, greaterThan(0));
    expect(mid, lessThan(1));

    await tester.pump(const Duration(milliseconds: 110));
    expect(_entranceOpacity(tester).opacity, 1);

    final transform = tester.widget<Transform>(
      find.byWidgetPredicate(
        (widget) => widget is Transform && widget.child is Text,
      ),
    );
    expect(transform.transform.getTranslation().y, 0);
  });

  testWidgets('disabled entrance renders the child directly', (tester) async {
    await tester.pumpWidget(
      _wrap(const AppEntrance(enabled: false, child: Text('static'))),
    );

    expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
    expect(find.text('static'), findsOneWidget);
  });

  testWidgets('transition role halves duration under reduce motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const AppEntrance(child: Text('fast')), disableAnimations: true),
    );

    // Motion.medium (220ms) is halved to 110ms for the transition role.
    await tester.pump(const Duration(milliseconds: 60));
    expect(_entranceOpacity(tester).opacity, lessThan(1));

    await tester.pump(const Duration(milliseconds: 60));
    expect(_entranceOpacity(tester).opacity, 1);
  });

  testWidgets('decorative role collapses to no animation under reduce motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const AppEntrance(role: AppMotionRole.decorative, child: Text('still')),
        disableAnimations: true,
      ),
    );
    await tester.pump();

    expect(_entranceOpacity(tester).opacity, 1);
  });
}
