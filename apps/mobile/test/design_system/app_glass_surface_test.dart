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
  AppGlassStatus status = AppGlassStatus.idle,
  AppGlassRole role = AppGlassRole.chrome,
  AppGlassLightField? field,
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
                child: AppGlassEnvironment(
                  field: field,
                  child: AppGlassSurface(
                    softLight: softLight,
                    status: status,
                    role: role,
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
    ),
  );
}

void main() {
  testWidgets('glass roles tune material depth without changing semantics', (
    tester,
  ) async {
    const roles = AppGlassRole.values;
    for (final role in roles) {
      await tester.pumpWidget(_wrap(softLight: true, role: role));
      final painter = _lightPainter(tester);
      expect(painter.role, role);
      expect(find.text('glass'), findsOneWidget);
    }
    expect(
      kAppSoftGlassSpec.depthFor(AppGlassRole.overlay),
      greaterThan(kAppSoftGlassSpec.depthFor(AppGlassRole.chrome)),
    );
    expect(
      kAppSoftGlassSpec.specularOpacity(Brightness.dark, AppGlassRole.chrome),
      lessThan(
        kAppSoftGlassSpec.specularOpacity(
          Brightness.light,
          AppGlassRole.chrome,
        ),
      ),
    );
  });

  testWidgets('glass surfaces consume one shared environment light field', (
    tester,
  ) async {
    const field = AppGlassLightField(
      lightColor: Color(0xff86c8d4),
      shadeColor: Color(0xff17313a),
      origin: Alignment(-0.5, -0.8),
      energy: 0.7,
    );
    await tester.pumpWidget(_wrap(softLight: true, field: field));
    final painter = _lightPainter(tester);
    expect(painter.lightColor, field.lightColor);
    expect(painter.shadeColor, field.shadeColor);
    expect(painter.lightOrigin, field.origin);
    expect(painter.energy, field.energy);
  });

  testWidgets('environment field responds to an active domain accent', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(softLight: true));
    final context = tester.element(find.byType(AppGlassSurface));
    final themeField = AppGlassLightField.fromTheme(context);
    final domainField = AppGlassLightField.fromTheme(
      context,
      accentColor: const Color(0xff8d7aff),
    );

    expect(domainField.lightColor, isNot(themeField.lightColor));
    expect(domainField.shadeColor, themeField.shadeColor);
  });

  testWidgets('busy and disabled stop active pointer feedback', (tester) async {
    for (final status in [AppGlassStatus.busy, AppGlassStatus.disabled]) {
      await tester.pumpWidget(_wrap(softLight: true));
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('glass')),
      );
      await tester.pumpAndSettle();
      expect(_lightPainter(tester).intensity.value, 1);
      await tester.pumpWidget(_wrap(softLight: true, status: status));
      await tester.pumpAndSettle();
      expect(_lightPainter(tester).intensity.value, 0);
      expect(_lightPainter(tester).position.value, isNull);
      expect(
        _lightPainter(tester).emphasis,
        status == AppGlassStatus.busy ? kAppSoftGlassSpec.busyEmphasis : 0,
      );
      await gesture.up();
      await tester.tap(find.text('glass'));
      await tester.pumpAndSettle();
      expect(_lightPainter(tester).intensity.value, 0);
      expect(tester.binding.transientCallbackCount, 0);
    }
  });

  testWidgets('error uses semantic danger and clears on recovery', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(softLight: true, status: AppGlassStatus.error),
    );
    final context = tester.element(find.byType(AppGlassSurface));
    expect(_lightPainter(tester).stateColor, context.theme.colors.destructive);
    expect(_lightPainter(tester).emphasis, kAppSoftGlassSpec.errorEmphasis);
    await tester.pumpWidget(_wrap(softLight: true));
    await tester.pumpAndSettle();
    expect(_lightPainter(tester).emphasis, 0);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
    'local control light follows hover focus press and disabled state',
    (tester) async {
      final highlightStrategy = FocusManager.instance.highlightStrategy;
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy = highlightStrategy,
      );
      final focus = FocusNode();
      addTearDown(focus.dispose);
      var taps = 0;
      Widget control({bool enabled = true, bool selected = false}) => _wrap(
        child: FTappable(
          focusNode: focus,
          selected: selected,
          onPress: enabled ? () => taps++ : null,
          builder: (context, variants, child) =>
              AppGlassFeedback(variants: variants, child: child!),
          child: const SizedBox(
            width: 160,
            height: 52,
            child: Center(child: Text('Tab')),
          ),
        ),
      );
      await tester.pumpWidget(control());
      expect(_lightPainter(tester).emphasis, 0);
      expect(_lightPainter(tester).ambient, 0);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('Tab')));
      await tester.pumpAndSettle();
      expect(_lightPainter(tester).emphasis, kAppSoftGlassSpec.hoverEmphasis);
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      focus.requestFocus();
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isTrue);
      expect(_lightPainter(tester).emphasis, kAppSoftGlassSpec.focusEmphasis);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(taps, 1);
      focus.unfocus();
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Tab')),
      );
      await tester.pumpAndSettle();
      expect(_lightPainter(tester).emphasis, kAppSoftGlassSpec.pressedEmphasis);
      expect(
        _lightPainter(tester).intensity.value,
        0,
        reason: 'No second raw-pointer response.',
      );
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(_lightPainter(tester).emphasis, 0);
      await tester.pumpWidget(control(selected: true));
      await tester.pumpAndSettle();
      expect(
        _lightPainter(tester).emphasis,
        kAppSoftGlassSpec.selectedEmphasis,
      );
      await tester.pumpWidget(control(enabled: false, selected: true));
      await tester.pumpAndSettle();
      expect(_lightPainter(tester).emphasis, 0);
      await tester.tap(find.text('Tab'));
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(tester.binding.transientCallbackCount, 0);
      await mouse.removePointer();
    },
  );

  testWidgets(
    'reduced motion keeps static selected feedback without animation',
    (tester) async {
      for (final selected in [false, true, false]) {
        await tester.pumpWidget(
          _wrap(
            reduceMotion: true,
            child: AppGlassFeedback(
              variants: {if (selected) FTappableVariant.selected},
              child: const SizedBox(width: 160, height: 52),
            ),
          ),
        );
        await tester.pump();
        expect(
          _lightPainter(tester).emphasis,
          selected ? kAppSoftGlassSpec.selectedEmphasis : 0,
        );
        expect(tester.binding.transientCallbackCount, 0);
      }
    },
  );

  testWidgets(
    'high contrast and OLED omit local light but keep selected semantics',
    (tester) async {
      for (final style in [
        AppSurfaceStyle.highContrast,
        AppSurfaceStyle.oled,
      ]) {
        await tester.pumpWidget(
          _wrap(
            style: style,
            brightness: Brightness.dark,
            child: Semantics(
              selected: true,
              child: AppGlassFeedback(
                variants: {FTappableVariant.selected},
                child: const Text('Selected'),
              ),
            ),
          ),
        );
        expect(find.byType(AppSoftGlassLight), findsNothing);
        expect(find.text('Selected'), findsOneWidget);
      }
    },
  );

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

  testWidgets('hover light flows with a mouse and fades on exit', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(softLight: true));
    final surface = tester.getRect(find.byType(AppSoftGlassLight));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(surface.center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 140));

    final painter = _lightPainter(tester);
    expect(
      painter.intensity.value,
      closeTo(kAppSoftGlassSpec.pointerHoverIntensity, 0.02),
    );
    expect(
      painter.position.value,
      Offset(surface.width / 2, surface.height / 2),
    );

    await mouse.moveTo(surface.bottomRight + const Offset(24, 24));
    await tester.pumpAndSettle();
    expect(painter.intensity.value, 0);
    await mouse.removePointer();
  });

  testWidgets('mouse drag out does not restore hover light on release', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(softLight: true));
    final rect = tester.getRect(find.byType(AppSoftGlassLight));
    final gesture = await tester.startGesture(
      rect.center,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 140));
    expect(_lightPainter(tester).intensity.value, closeTo(1, 0.02));

    await gesture.moveTo(rect.bottomRight + const Offset(24, 24));
    await tester.pumpAndSettle();
    expect(_lightPainter(tester).intensity.value, 0);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_lightPainter(tester).intensity.value, 0);
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
