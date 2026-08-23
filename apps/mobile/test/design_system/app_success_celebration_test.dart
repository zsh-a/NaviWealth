import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/haptics/haptics.dart';
import 'package:naviwealth/design_system/design_system.dart';

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

Widget _toastWrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    builder: (context, child) => AppMessenger.init(child: child!),
    home: FTheme(data: FTheme.neutral.light.desktop, child: child),
  );
}

double _entranceScale(WidgetTester tester) {
  final transform = tester.widget<Transform>(
    find.descendant(
      of: find.byType(AppSuccessCelebration),
      matching: find.byType(Transform),
    ),
  );
  // Transform.scale leaves z at 1, so read the x-scale directly instead of
  // getMaxScaleOnAxis (which would always return 1).
  return transform.transform[0];
}

void main() {
  setUp(() => Haptics.disabled = true);
  tearDown(() => Haptics.disabled = false);

  testWidgets('static variant renders fully drawn with no tickers', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const AppSuccessCelebration.static()));

    expect(find.byType(AppSuccessCelebration), findsOneWidget);
    expect(_entranceScale(tester), 1);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('animated entrance springs in and settles at rest', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const AppSuccessCelebration()));

    expect(_entranceScale(tester), lessThan(1));
    expect(tester.hasRunningAnimations, isTrue);

    await tester.pumpAndSettle();
    expect(_entranceScale(tester), closeTo(1, 0.01));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('reduce-motion renders the finished check immediately', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const AppSuccessCelebration(), disableAnimations: true),
    );

    expect(_entranceScale(tester), 1);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('success toasts celebrate with the drawn check', (tester) async {
    await tester.pumpWidget(
      _toastWrap(
        Builder(
          builder: (context) => FButton(
            onPress: () =>
                AppMessenger.show(context, ToastKind.success, 'Saved'),
            child: const Text('Show'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();

    expect(find.text('Saved'), findsOneWidget);
    expect(find.byType(AppSuccessCelebration), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
  });
}
