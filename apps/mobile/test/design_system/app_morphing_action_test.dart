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
  testWidgets('crossfades between keyed states', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const AppMorphingAction(child: Icon(Icons.send, key: ValueKey('send'))),
      ),
    );
    expect(find.byIcon(Icons.send), findsOneWidget);

    await tester.pumpWidget(
      _wrap(
        const AppMorphingAction(child: Icon(Icons.stop, key: ValueKey('stop'))),
      ),
    );
    // Mid-transition both affordances are on stage.
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byIcon(Icons.send), findsOneWidget);
    expect(find.byIcon(Icons.stop), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.send), findsNothing);
    expect(find.byIcon(Icons.stop), findsOneWidget);
  });

  testWidgets('reduce motion shortens the switch', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const AppMorphingAction(child: Icon(Icons.send, key: ValueKey('send'))),
        disableAnimations: true,
      ),
    );
    await tester.pumpWidget(
      _wrap(
        const AppMorphingAction(child: Icon(Icons.stop, key: ValueKey('stop'))),
        disableAnimations: true,
      ),
    );

    // Motion.fast (120ms) is halved to 60ms under reduce motion; the
    // outgoing child is removed one frame after the animation completes,
    // so at 80ms it must be gone (a full 120ms morph would still show it).
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.byIcon(Icons.send), findsNothing);
    expect(find.byIcon(Icons.stop), findsOneWidget);
  });
}
