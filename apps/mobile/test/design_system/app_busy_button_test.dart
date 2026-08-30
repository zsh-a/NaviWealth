import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: FTheme(
      data: FTheme.neutral.light.desktop,
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  testWidgets('uses a stable label and invokes the idle action', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(
      _wrap(
        AppBusyButton(
          label: 'Save',
          busyLabel: 'Saving',
          onPress: () => presses++,
        ),
      ),
    );

    expect(find.text('Save'), findsOneWidget);
    expect(find.byType(FCircularProgress), findsNothing);
    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(presses, 1);
  });

  testWidgets('shows progress and blocks activation while busy', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(
      _wrap(
        AppBusyButton(
          label: 'Save',
          busyLabel: 'Saving',
          busy: true,
          onPress: () => presses++,
        ),
      ),
    );

    expect(find.text('Saving'), findsOneWidget);
    expect(find.byType(FCircularProgress), findsOneWidget);
    await tester.tap(find.text('Saving'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(presses, 0);
  });

  group('haptics', () {
    final hapticCalls = <String>[];

    setUp(() {
      hapticCalls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'HapticFeedback.vibrate') {
              hapticCalls.add((call.arguments as String?) ?? 'default');
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    /// Enables haptics for the duration of [body]; the platform override is a
    /// foundation debug variable that must be restored before the widget-test
    /// invariant check, so it cannot live in `tearDown`.
    Future<void> withHaptics(Future<void> Function() body) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await body();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    testWidgets('fires commit feedback on press by default', (tester) async {
      await withHaptics(() async {
        await tester.pumpWidget(
          _wrap(AppBusyButton(label: 'Save', onPress: () {})),
        );

        await tester.tap(find.text('Save'));
        await tester.pump(const Duration(milliseconds: 200));
        expect(hapticCalls, ['HapticFeedbackType.lightImpact']);
      });
    });

    testWidgets('stays silent when hapticIntent is null', (tester) async {
      await withHaptics(() async {
        var presses = 0;
        await tester.pumpWidget(
          _wrap(
            AppBusyButton(
              label: 'Save',
              onPress: () => presses++,
              hapticIntent: null,
            ),
          ),
        );

        await tester.tap(find.text('Save'));
        await tester.pump(const Duration(milliseconds: 200));
        expect(presses, 1);
        expect(hapticCalls, isEmpty);
      });
    });

    testWidgets('does not fire while busy', (tester) async {
      await withHaptics(() async {
        await tester.pumpWidget(
          _wrap(
            AppBusyButton(
              label: 'Save',
              busyLabel: 'Saving',
              busy: true,
              onPress: () {},
            ),
          ),
        );

        await tester.tap(find.text('Saving'));
        await tester.pump(const Duration(milliseconds: 200));
        expect(hapticCalls, isEmpty);
      });
    });
  });
}
