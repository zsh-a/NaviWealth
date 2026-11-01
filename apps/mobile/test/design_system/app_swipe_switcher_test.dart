import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';

Widget _wrap(
  ValueNotifier<int> selected, {
  List<int> options = const [0, 1, 2],
  bool enabled = true,
  TextDirection direction = TextDirection.ltr,
  TargetPlatform platform = TargetPlatform.android,
  Widget? child,
}) => MaterialApp(
  theme: ThemeData(platform: platform),
  home: Directionality(
    textDirection: direction,
    child: Scaffold(
      body: ValueListenableBuilder<int>(
        valueListenable: selected,
        builder: (context, value, _) => AppSwipeSwitcher<int>(
          options: options,
          value: value,
          onChanged: enabled ? (next) => selected.value = next : null,
          child: child ?? const SizedBox.expand(),
        ),
      ),
    ),
  ),
);

void main() {
  for (final direction in TextDirection.values) {
    testWidgets(
      'swipes select adjacent categories without wrapping: $direction',
      (tester) async {
        final selected = ValueNotifier(0);
        addTearDown(selected.dispose);
        await tester.pumpWidget(_wrap(selected, direction: direction));
        final region = find.byType(AppSwipeSwitcher<int>);
        final forward = Offset(direction == TextDirection.ltr ? -180 : 180, 0);
        await tester.drag(region, -forward);
        await tester.pump();
        expect(selected.value, 0);
        await tester.drag(region, forward);
        await tester.pump();
        expect(selected.value, 1);
        await tester.drag(region, forward);
        await tester.pump();
        expect(selected.value, 2);
        await tester.drag(region, forward);
        await tester.pump();
        expect(selected.value, 2);
        await tester.drag(region, -forward);
        await tester.pump();
        expect(selected.value, 1);
      },
    );
  }

  testWidgets('short slow drags are ignored but a deliberate fling works', (
    tester,
  ) async {
    final selected = ValueNotifier(0);
    addTearDown(selected.dispose);
    await tester.pumpWidget(_wrap(selected));
    final region = find.byType(AppSwipeSwitcher<int>);
    await tester.timedDrag(
      region,
      const Offset(-30, 0),
      const Duration(milliseconds: 600),
    );
    await tester.pump();
    expect(selected.value, 0);
    await tester.fling(region, const Offset(-36, 0), 1000);
    await tester.pump();
    expect(selected.value, 1);
  });

  testWidgets('cancelled and interrupted gestures cannot switch a category', (
    tester,
  ) async {
    final selected = ValueNotifier(0);
    addTearDown(selected.dispose);
    await tester.pumpWidget(_wrap(selected));
    final point = tester.getCenter(find.byType(AppSwipeSwitcher<int>));
    final cancelled = await tester.startGesture(point);
    await cancelled.moveBy(const Offset(-100, 0));
    await cancelled.cancel();
    await tester.pump();
    expect(selected.value, 0);
    final interrupted = await tester.startGesture(point);
    await interrupted.moveBy(const Offset(-100, 0));
    selected.value = 1;
    await tester.pump();
    await interrupted.up();
    await tester.pump();
    expect(selected.value, 1);
  });

  testWidgets('vertical scrolling keeps the selected category', (tester) async {
    final selected = ValueNotifier(0);
    final scroll = ScrollController();
    addTearDown(selected.dispose);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      _wrap(
        selected,
        child: ListView(
          controller: scroll,
          children: [
            for (var i = 0; i < 40; i++)
              SizedBox(height: 60, child: Text('Item $i')),
          ],
        ),
      ),
    );
    await tester.drag(find.byType(ListView), const Offset(10, -220));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(100));
    expect(selected.value, 0);
  });

  testWidgets('child horizontal interactions take priority', (tester) async {
    final selected = ValueNotifier(0);
    addTearDown(selected.dispose);
    var updates = 0;
    await tester.pumpWidget(
      _wrap(
        selected,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (_) => updates++,
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.drag(
      find.byType(AppSwipeSwitcher<int>),
      const Offset(-180, 0),
    );
    await tester.pump();
    expect(updates, greaterThan(0));
    expect(selected.value, 0);
  });

  for (final direction in TextDirection.values) {
    testWidgets('iOS leading edge is reserved for system back: $direction', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final selected = ValueNotifier(1);
      addTearDown(selected.dispose);
      await tester.pumpWidget(
        _wrap(selected, platform: TargetPlatform.iOS, direction: direction),
      );
      final ltr = direction == TextDirection.ltr;
      final gesture = await tester.startGesture(Offset(ltr ? 4 : 396, 200));
      await gesture.moveBy(Offset(ltr ? 120 : -120, 0));
      await gesture.up();
      await tester.pump();
      expect(selected.value, 1);
      await tester.drag(
        find.byType(AppSwipeSwitcher<int>),
        Offset(ltr ? 120 : -120, 0),
      );
      await tester.pump();
      expect(selected.value, 0);
    });
  }

  testWidgets('mouse drags leave text selection to the content', (
    tester,
  ) async {
    final selected = ValueNotifier(0);
    addTearDown(selected.dispose);
    await tester.pumpWidget(_wrap(selected));
    final mouse = await tester.startGesture(
      tester.getCenter(find.byType(AppSwipeSwitcher<int>)),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(-160, 0));
    await mouse.up();
    await tester.pump();
    expect(selected.value, 0);
  });

  testWidgets('disabled, missing and single selections do not switch', (
    tester,
  ) async {
    final selected = ValueNotifier(0);
    addTearDown(selected.dispose);
    for (final config in [
      (false, <int>[0, 1, 2]),
      (true, <int>[0]),
      (true, <int>[1, 2]),
    ]) {
      await tester.pumpWidget(
        _wrap(selected, enabled: config.$1, options: config.$2),
      );
      await tester.drag(
        find.byType(AppSwipeSwitcher<int>),
        const Offset(-180, 0),
      );
      await tester.pump();
      expect(selected.value, 0);
    }
  });

  testWidgets(
    'haptics fire once per committed switch and never at a boundary',
    (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => calls.add(call),
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final selected = ValueNotifier(0);
      addTearDown(selected.dispose);
      await tester.pumpWidget(_wrap(selected));
      final region = find.byType(AppSwipeSwitcher<int>);
      await tester.drag(region, const Offset(180, 0));
      await tester.pump();
      expect(
        calls.where((call) => call.method == 'HapticFeedback.vibrate'),
        isEmpty,
      );
      await tester.drag(region, const Offset(-180, 0));
      await tester.pump();
      expect(
        calls.where((call) => call.method == 'HapticFeedback.vibrate'),
        hasLength(1),
      );
    },
  );
}
