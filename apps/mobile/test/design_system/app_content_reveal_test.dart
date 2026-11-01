import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

Widget _wrap(Widget child, {bool disabled = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: disabled),
    child: FAccessibilityScope(child: Scaffold(body: child)),
  ),
);

double _opacity(WidgetTester tester) => tester
    .widget<FadeTransition>(
      find.descendant(
        of: find.byType(AppContentReveal),
        matching: find.byType(FadeTransition),
      ),
    )
    .opacity
    .value;

void main() {
  testWidgets('initial content and ordinary data rebuilds stay fully visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const AppContentReveal(transitionKey: 0, child: Text('initial'))),
    );
    expect(_opacity(tester), 1);
    expect(tester.hasRunningAnimations, isFalse);

    await tester.pumpWidget(
      _wrap(const AppContentReveal(transitionKey: 0, child: Text('refreshed'))),
    );
    expect(find.text('refreshed'), findsOneWidget);
    expect(_opacity(tester), 1);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('reveals a new selection and preserves live child state', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const AppContentReveal(transitionKey: 0, child: _StateProbe())),
    );
    final before = tester.state(find.byType(_StateProbe));

    await tester.pumpWidget(
      _wrap(const AppContentReveal(transitionKey: 1, child: _StateProbe())),
    );
    expect(_opacity(tester), 0);
    expect(identical(before, tester.state(find.byType(_StateProbe))), isTrue);
    await tester.pump(Motion.navigationSwitch ~/ 2);
    expect(_opacity(tester), inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(_opacity(tester), 1);
    expect(identical(before, tester.state(find.byType(_StateProbe))), isTrue);
  });

  testWidgets('rapid changes continue the active reveal without queuing', (
    tester,
  ) async {
    for (var index = 0; index < 2; index++) {
      await tester.pumpWidget(
        _wrap(AppContentReveal(transitionKey: index, child: Text('$index'))),
      );
    }
    await tester.pump(const Duration(milliseconds: 50));
    final before = _opacity(tester);
    await tester.pumpWidget(
      _wrap(const AppContentReveal(transitionKey: 2, child: Text('latest'))),
    );
    expect(_opacity(tester), closeTo(before, 0.0001));
    expect(find.text('1'), findsNothing);
    expect(find.text('latest'), findsOneWidget);
    await tester.pump(Motion.navigationSwitch);
    expect(_opacity(tester), 1);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('iOS reduced motion keeps a short fade with no displacement', (
    tester,
  ) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );
    for (var index = 0; index < 2; index++) {
      await tester.pumpWidget(
        _wrap(
          AppContentReveal(
            transitionKey: index,
            offset: const Offset(16, 0),
            child: const Text('selected'),
          ),
        ),
      );
    }
    await tester.pump(const Duration(milliseconds: 30));
    expect(_opacity(tester), inExclusiveRange(0, 1));
    final transform = tester.widget<Transform>(
      find.descendant(
        of: find.byType(AppContentReveal),
        matching: find.byType(Transform),
      ),
    );
    expect(transform.transform.getTranslation().x, 0);
    await tester.pump(Motion.navigationSwitch ~/ 2);
    expect(_opacity(tester), 1);
  });

  testWidgets('turning animations off finishes a reveal without remounting', (
    tester,
  ) async {
    for (var index = 0; index < 2; index++) {
      await tester.pumpWidget(
        _wrap(
          AppContentReveal(transitionKey: index, child: const _StateProbe()),
        ),
      );
    }
    await tester.pump(const Duration(milliseconds: 30));
    final before = tester.state(find.byType(_StateProbe));
    expect(_opacity(tester), lessThan(1));
    await tester.pumpWidget(
      _wrap(
        const AppContentReveal(transitionKey: 1, child: _StateProbe()),
        disabled: true,
      ),
    );
    expect(_opacity(tester), 1);
    expect(identical(before, tester.state(find.byType(_StateProbe))), isTrue);
    expect(tester.hasRunningAnimations, isFalse);
  });
}

class _StateProbe extends StatefulWidget {
  const _StateProbe();

  @override
  State<_StateProbe> createState() => _StateProbeState();
}

class _StateProbeState extends State<_StateProbe> {
  @override
  Widget build(BuildContext context) => const Text('retained');
}
