import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

void main() {
  for (final role in AppMotionRole.values) {
    testWidgets('${role.name} motion keeps its duration by default', (
      tester,
    ) async {
      late Duration duration;
      late bool enabled;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              duration = AppMotionPolicy.duration(
                context,
                Motion.medium,
                role: role,
              );
              enabled = AppMotionPolicy.isEnabled(context, role: role);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(duration, Motion.medium);
      expect(enabled, isTrue);
    });

    testWidgets('${role.name} motion degrades under the system setting', (
      tester,
    ) async {
      late Duration duration;
      late bool enabled;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Builder(
              builder: (context) {
                duration = AppMotionPolicy.duration(
                  context,
                  Motion.medium,
                  role: role,
                );
                enabled = AppMotionPolicy.isEnabled(context, role: role);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(duration, Duration.zero);
      expect(enabled, isFalse);
    });
  }

  testWidgets('imperative routes inherit the reduced-motion duration', (
    tester,
  ) async {
    late PageRoute<void> route;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              route = buildAppPageRoute<void>(
                context: context,
                pageBuilder: (_, _, _) => const Text('detail'),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(route.transitionDuration, Duration.zero);
    expect(route.reverseTransitionDuration, Duration.zero);
  });

  testWidgets('observes the independent iOS reduced-motion flag and changes', (
    tester,
  ) async {
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );
    late Duration transition;
    late bool decorative;
    late bool disabled;
    await tester.pumpWidget(
      MaterialApp(
        home: FAccessibilityScope(
          child: Builder(
            builder: (context) {
              transition = AppMotionPolicy.duration(context, Motion.medium);
              decorative = AppMotionPolicy.isEnabled(
                context,
                role: AppMotionRole.decorative,
              );
              disabled = AppMotionPolicy.disableAnimations(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    expect(transition, Motion.medium);
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    await tester.pump();
    expect(transition, Motion.medium * 0.5);
    expect(decorative, isFalse);
    expect(disabled, isFalse);

    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    await tester.pump();
    expect(transition, Duration.zero);
    expect(disabled, isTrue);
  });
}
