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

void main() {
  testWidgets('renders immediately when reduced motion is enabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const FadeSlideIn(
          delay: Duration(milliseconds: 200),
          child: Text('ready'),
        ),
        disableAnimations: true,
      ),
    );

    final opacity = tester.widget<FadeTransition>(
      find.byWidgetPredicate(
        (widget) => widget is FadeTransition && widget.child is AnimatedBuilder,
      ),
    );
    expect(opacity.opacity.value, 1);
    expect(find.text('ready'), findsOneWidget);
  });

  testWidgets('cancels delayed entrance timer when removed', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const FadeSlideIn(delay: Duration(seconds: 1), child: Text('delayed')),
      ),
    );

    await tester.pumpWidget(_wrap(const SizedBox.shrink()));

    expect(find.text('delayed'), findsNothing);
  });
}
