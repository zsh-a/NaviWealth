import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

    testWidgets('${role.name} motion is disabled by the system setting', (
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
    late PageRouteBuilder<void> route;
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
}
