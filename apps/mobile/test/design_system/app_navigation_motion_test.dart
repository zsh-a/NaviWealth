import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';

const _detailKey = ValueKey('detail');
const _homeKey = ValueKey('home');
const _detail = Scaffold(body: SizedBox.expand(key: _detailKey));

Widget _app(GlobalKey<NavigatorState> navigator, TargetPlatform platform) =>
    MaterialApp(
      navigatorKey: navigator,
      theme: AppTheme.light().copyWith(platform: platform),
      home: const Scaffold(body: SizedBox.expand(key: _homeKey)),
    );

PageRoute<void> _route(WidgetTester tester, bool imperative) => imperative
    ? buildAppPageRoute<void>(
        context: tester.element(find.byKey(_homeKey)),
        pageBuilder: (_, _, _) => _detail,
      )
    : MaterialPageRoute<void>(builder: (_) => _detail);

void main() {
  for (final imperative in [false, true]) {
    testWidgets('detail timing is shared, imperative=$imperative', (
      tester,
    ) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(_app(navigator, TargetPlatform.android));
      final route = _route(tester, imperative);
      navigator.currentState!.push(route);
      await tester.pump();
      expect(route.transitionDuration, Motion.pageTransition);
      expect(route.reverseTransitionDuration, Motion.pageReturn);
      expect(route.animation!.isAnimating, isTrue);
      await tester.pumpAndSettle();
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.byKey(_homeKey), findsOneWidget);
    });

    for (final reduced in [false, true]) {
      testWidgets(
        'iOS edge back survives, imperative=$imperative reduced=$reduced',
        (tester) async {
          tester.view.physicalSize = const Size(400, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
              FakeAccessibilityFeatures(reduceMotion: reduced);
          addTearDown(
            tester
                .binding
                .platformDispatcher
                .clearAccessibilityFeaturesTestValue,
          );
          final navigator = GlobalKey<NavigatorState>();
          await tester.pumpWidget(_app(navigator, TargetPlatform.iOS));
          final route = _route(tester, imperative);
          navigator.currentState!.push(route);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 20));
          if (reduced) {
            expect(tester.getTopLeft(find.byKey(_detailKey)).dx, 0);
            expect(tester.getTopLeft(find.byKey(_homeKey)).dx, 0);
          }
          await tester.pumpAndSettle();
          expect(route.popGestureEnabled, isTrue);

          final gesture = await tester.startGesture(const Offset(1, 300));
          await gesture.moveBy(const Offset(300, 0));
          await tester.pump();
          expect(navigator.currentState!.userGestureInProgress, isTrue);
          if (reduced) {
            expect(tester.getTopLeft(find.byKey(_detailKey)).dx, 0);
          } else {
            expect(
              tester.getTopLeft(find.byKey(_detailKey)).dx,
              greaterThan(0),
            );
          }
          await gesture.up();
          await tester.pumpAndSettle();
          expect(find.byKey(_detailKey), findsNothing);
          expect(find.byKey(_homeKey), findsOneWidget);
        },
      );
    }
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('system animation removal is immediate on ${platform.name}', (
      tester,
    ) async {
      tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(_app(navigator, platform));
      final route = _route(tester, false);
      navigator.currentState!.push(route);
      await tester.pump();
      expect(route.animation!.isCompleted, isTrue);
      expect(route.transitionDuration, Duration.zero);
      expect(tester.getTopLeft(find.byKey(_detailKey)), Offset.zero);
      expect(tester.hasRunningAnimations, isFalse);
    });
  }

  testWidgets('iOS edge back still respects a dirty form guard', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigator, TargetPlatform.iOS));
    final route = MaterialPageRoute<void>(
      builder: (_) => const PopScope(canPop: false, child: _detail),
    );
    navigator.currentState!.push(route);
    await tester.pumpAndSettle();
    expect(route.popGestureEnabled, isFalse);
    await navigator.currentState!.maybePop();
    await tester.pump();
    expect(find.byKey(_detailKey), findsOneWidget);
  });
}
