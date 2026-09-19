import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/design_system/widgets/app_soft_glass_light.dart';

Widget _wrap({
  AppSurfaceStyle style = AppSurfaceStyle.standard,
  Brightness brightness = Brightness.light,
  bool platformHighContrast = false,
  bool reduceMotion = false,
  bool softLight = false,
  bool frosted = true,
  bool tickersEnabled = true,
  Widget? child,
}) {
  final appTheme = brightness == Brightness.dark
      ? AppTheme.dark(surfaceStyle: style)
      : AppTheme.light(surfaceStyle: style);
  final resolved = resolveAppTheme(
    ThemeInputs(
      brightness: brightness,
      marketMode: MarketColorMode.redUpGreenDown,
      surfaceStyle: style,
    ),
  );
  return MaterialApp(
    theme: appTheme,
    home: FTheme(
      data: buildAppForuiTheme(
        brightness: brightness,
        touch: true,
        surfaceStyle: style,
      ),
      child: AppThemeScope(
        data: resolved,
        child: MediaQuery(
          data: MediaQueryData(
            highContrast: platformHighContrast,
            disableAnimations: reduceMotion,
          ),
          child: Scaffold(
            body: Center(
              child: TickerMode(
                enabled: tickersEnabled,
                child: AppGlassSurface(
                  softLight: softLight,
                  frosted: frosted,
                  borderRadius: BorderRadius.circular(24),
                  child:
                      child ??
                      const SizedBox(
                        width: 300,
                        height: 100,
                        child: Text('glass'),
                      ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('standard surface uses one live backdrop layer', (tester) async {
    await tester.pumpWidget(_wrap());

    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('high-contrast theme replaces blur with opaque material', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(style: AppSurfaceStyle.highContrast));

    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('OLED theme preserves the black canvas without live blur', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(style: AppSurfaceStyle.oled, brightness: Brightness.dark),
    );

    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('platform high contrast overrides the standard glass style', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(platformHighContrast: true));

    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('soft light is opt-in and shares the single blur layer', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap());
    expect(find.byType(AppSoftGlassLight), findsNothing);
    await tester.pumpWidget(_wrap(softLight: true));
    expect(find.byType(AppSoftGlassLight), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(_lightPainter(tester).intensity.value, 0);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('opaque performance fallback can keep paint-only soft light', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(softLight: true, frosted: false));
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(AppSoftGlassLight), findsOneWidget);
    final context = tester.element(find.byType(AppGlassSurface));
    expect(
      appGlassDecoration(context, frosted: false, softLight: true).color!.a,
      1,
    );
  });

  testWidgets('accessibility and OLED overrides remove soft light', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(softLight: true, platformHighContrast: true));
    expect(find.byType(AppSoftGlassLight), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
    await tester.pumpWidget(
      _wrap(softLight: true, style: AppSurfaceStyle.highContrast),
    );
    expect(find.byType(AppSoftGlassLight), findsNothing);
    await tester.pumpWidget(
      _wrap(
        softLight: true,
        style: AppSurfaceStyle.oled,
        brightness: Brightness.dark,
      ),
    );
    expect(find.byType(AppSoftGlassLight), findsNothing);
  });

  testWidgets('pointer light follows drag without rebuilding foreground', (
    tester,
  ) async {
    var builds = 0;
    var taps = 0;
    var drags = 0;
    await tester.pumpWidget(
      _wrap(
        softLight: true,
        child: Builder(
          builder: (_) {
            builds++;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => taps++,
              onHorizontalDragUpdate: (_) => drags++,
              child: const SizedBox(
                width: 300,
                height: 100,
                child: Text('action'),
              ),
            );
          },
        ),
      ),
    );
    final before = builds;
    final rect = tester.getRect(find.byType(AppSoftGlassLight));
    final gesture = await tester.startGesture(rect.center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 140));
    final painter = _lightPainter(tester);
    expect(painter.intensity.value, 1);
    expect(painter.position.value, const Offset(150, 50));
    await gesture.moveBy(const Offset(50, 0));
    await tester.pump();
    expect(painter.position.value, const Offset(200, 50));
    // The first move wins the gesture arena; subsequent movement updates it.
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    expect(drags, greaterThan(0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(painter.intensity.value, 0);
    expect(taps, 0);
    expect(builds, before);
    await tester.tap(find.text('action'));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('cancel and leaving the surface extinguish light', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        softLight: true,
        child: const ColoredBox(
          color: Colors.transparent,
          child: SizedBox(width: 300, height: 100),
        ),
      ),
    );
    final rect = tester.getRect(find.byType(AppSoftGlassLight));
    final gesture = await tester.startGesture(rect.center);
    await tester.pumpAndSettle();
    await gesture.moveTo(rect.bottomRight + const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(_lightPainter(tester).intensity.value, 0);
    await gesture.moveTo(rect.center);
    await tester.pumpAndSettle();
    expect(_lightPainter(tester).intensity.value, 1);
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(_lightPainter(tester).intensity.value, 0);
  });

  testWidgets('secondary click does not trigger light', (tester) async {
    await tester.pumpWidget(_wrap(softLight: true));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('glass')),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    expect(_lightPainter(tester).intensity.value, 0);
    await gesture.up();
  });

  testWidgets(
    'reduce motion stops an active light and preserves static finish',
    (tester) async {
      await tester.pumpWidget(_wrap(softLight: true));
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('glass')),
      );
      await tester.pumpAndSettle();
      expect(_lightPainter(tester).intensity.value, 1);
      await tester.pumpWidget(_wrap(softLight: true, reduceMotion: true));
      expect(find.byType(AppSoftGlassLight), findsOneWidget);
      expect(_lightPainter(tester).intensity.value, 0);
      await gesture.up();
      await tester.tap(find.text('glass'));
      await tester.pumpAndSettle();
      expect(_lightPainter(tester).position.value, isNull);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets('multiple pointers do not steal the active light', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(softLight: true));
    final point = tester.getCenter(find.text('glass'));
    final first = await tester.startGesture(point, pointer: 1);
    await tester.pumpAndSettle();
    final initial = _lightPainter(tester).position.value;
    final second = await tester.startGesture(
      point + const Offset(5, 0),
      pointer: 2,
    );
    await second.up();
    await tester.pumpAndSettle();
    expect(_lightPainter(tester).position.value, initial);
    expect(_lightPainter(tester).intensity.value, 1);
    await first.up();
    await tester.pumpAndSettle();
    expect(_lightPainter(tester).intensity.value, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hidden route clears light and resumes idle', (tester) async {
    await tester.pumpWidget(_wrap(softLight: true));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('glass')),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(_wrap(softLight: true, tickersEnabled: false));
    expect(_lightPainter(tester).intensity.value, 0);
    expect(_lightPainter(tester).position.value, isNull);
    await gesture.up();
    await tester.pumpWidget(_wrap(softLight: true));
    expect(_lightPainter(tester).intensity.value, 0);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('keyboard action and focus remain owned by the child', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    var presses = 0;
    await tester.pumpWidget(
      _wrap(
        softLight: true,
        child: TextButton(
          focusNode: focus,
          onPressed: () => presses++,
          child: const Text('Save'),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(presses, 1);
    expect(focus.hasFocus, isTrue);
    expect(_lightPainter(tester).intensity.value, 0);
  });

  testWidgets('removing an active glass surface disposes its ticker', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(softLight: true));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('glass')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pumpWidget(const SizedBox.shrink());
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
  });
}

SoftGlassLightPainter _lightPainter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(
      find.descendant(
        of: find.byType(AppSoftGlassLight),
        matching: find.byType(CustomPaint),
      ),
    )
    .map((widget) => widget.painter)
    .whereType<SoftGlassLightPainter>()
    .single;
