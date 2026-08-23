import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

import '../../tool/export_design_tokens.dart' as exporter;

Widget _wrap(Widget child, {bool disableAnimations = false}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: FTheme(
      data: FTheme.neutral.light.desktop,
      child: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Center(child: child),
      ),
    ),
  );
}

double _scaleOf(WidgetTester tester) {
  final transform = tester.widget<Transform>(
    find.descendant(
      of: find.byType(SpringPressScale),
      matching: find.byType(Transform),
    ),
  );
  // Transform.scale leaves z at 1, so read the x-scale directly instead of
  // getMaxScaleOnAxis (which would always return 1).
  return transform.transform[0];
}

void main() {
  test('spring presets carry documented physics parameters', () {
    expect(Motion.springGentle.stiffness, 180);
    expect(Motion.springGentle.damping, 22);
    expect(Motion.springGentle.mass, 1);
    expect(Motion.springSnappy.stiffness, 400);
    expect(Motion.springSnappy.damping, 28);
    expect(Motion.springSnappy.mass, 1);
  });

  test('spring presets are exported to tokens.json', () {
    final motion = exporter.buildTokens()['motion']! as Map<String, Object>;
    final spring = motion['spring']! as Map<String, Object>;

    final gentle = spring['gentle']! as Map<String, Object>;
    expect(gentle[r'$type'], 'spring');
    final gentleValue = gentle[r'$value']! as Map<String, Object>;
    expect(gentleValue['stiffness'], '180');
    expect(gentleValue['damping'], '22');
    expect(gentleValue['mass'], '1');

    final snappy = spring['snappy']! as Map<String, Object>;
    expect(snappy[r'$type'], 'spring');
    final snappyValue = snappy[r'$value']! as Map<String, Object>;
    expect(snappyValue['stiffness'], '400');
    expect(snappyValue['damping'], '28');
    expect(snappyValue['mass'], '1');
  });

  testWidgets('press uses the fast curve and release springs back to rest', (
    tester,
  ) async {
    const child = SizedBox(width: 120, height: 48, child: Text('press me'));

    await tester.pumpWidget(
      _wrap(const SpringPressScale(pressed: false, child: child)),
    );
    expect(_scaleOf(tester), 1);

    // Press down: quick curve toward the theme press scale (0.98).
    await tester.pumpWidget(
      _wrap(const SpringPressScale(pressed: true, child: child)),
    );
    await tester.pump(const Duration(milliseconds: 30));
    final pressing = _scaleOf(tester);
    expect(pressing, lessThan(1));
    expect(pressing, greaterThan(0.98));

    await tester.pump(Motion.tapFeedback);
    expect(_scaleOf(tester), closeTo(0.98, 0.001));

    // Release: spring rebound settles exactly at rest.
    await tester.pumpWidget(
      _wrap(const SpringPressScale(pressed: false, child: child)),
    );
    await tester.pump(const Duration(milliseconds: 30));
    expect(_scaleOf(tester), greaterThan(0.98));

    await tester.pumpAndSettle();
    expect(_scaleOf(tester), closeTo(1, 0.01));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('reduce-motion keeps the resting scale while pressed', (
    tester,
  ) async {
    const child = SizedBox(width: 120, height: 48, child: Text('press me'));

    await tester.pumpWidget(
      _wrap(
        const SpringPressScale(pressed: true, child: child),
        disableAnimations: true,
      ),
    );
    expect(_scaleOf(tester), 1);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('PressableScale taps still fire and rebound to rest', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      _wrap(
        PressableScale(
          haptic: false,
          onTap: () => tapped = true,
          child: const SizedBox(width: 120, height: 48, child: Text('tap')),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('tap')),
    );
    // First frame rebuilds with pressed=true and starts the press curve;
    // the next advance moves the scale below 1.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(_scaleOf(tester), lessThan(1));

    await gesture.up();
    await tester.pump();
    expect(tapped, isTrue);

    await tester.pumpAndSettle();
    expect(_scaleOf(tester), closeTo(1, 0.01));
  });
}
