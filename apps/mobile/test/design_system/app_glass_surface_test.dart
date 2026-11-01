import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/design_system/widgets/app_soft_glass_light.dart';

Widget _wrap({
  bool highContrast = false,
  Brightness brightness = Brightness.light,
  bool platformHighContrast = false,
  bool reduceMotion = false,
  bool softLight = false,
  bool frosted = true,
  bool tickersEnabled = true,
  AppGlassRole role = AppGlassRole.chrome,
  AppGlassLightField? field,
  Widget? child,
}) {
  final appTheme = brightness == Brightness.dark
      ? AppTheme.dark(highContrast: highContrast)
      : AppTheme.light(highContrast: highContrast);
  final resolved = resolveAppTheme(
    ThemeInputs(
      materialStyle: AppMaterialStyle.translucent,
      brightness: brightness,
      marketMode: MarketColorMode.redUpGreenDown,
      highContrast: highContrast,
    ),
  );
  return MaterialApp(
    theme: appTheme,
    home: FTheme(
      data: buildAppForuiTheme(
        brightness: brightness,
        touch: true,
        highContrast: highContrast,
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

  testWidgets(
    'material and accessibility changes retain the foreground draft',
    (tester) async {
      Widget form({
        bool softLight = true,
        bool tickersEnabled = true,
        bool reduceMotion = false,
        bool frosted = true,
      }) => _wrap(
        softLight: softLight,
        tickersEnabled: tickersEnabled,
        reduceMotion: reduceMotion,
        frosted: frosted,
        child: const SizedBox(width: 300, child: TextField()),
      );
      await tester.pumpWidget(form());
      await tester.enterText(find.byType(TextField), 'Unsaved draft');
      final state = tester.state(find.byType(TextField));
      for (final configuration in [
        (true, false, false, true),
        (true, true, true, true),
        (false, true, false, true),
        (true, true, false, false),
        (true, true, false, true),
      ]) {
        await tester.pumpWidget(
          form(
            softLight: configuration.$1,
            tickersEnabled: configuration.$2,
            reduceMotion: configuration.$3,
            frosted: configuration.$4,
          ),
        );
        await tester.pump();
        expect(tester.state(find.byType(TextField)), same(state));
        expect(find.text('Unsaved draft'), findsOneWidget);
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
    await tester.pumpWidget(_wrap(highContrast: true));

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

  testWidgets('system accessibility overrides remove soft light', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(softLight: true, platformHighContrast: true));
    expect(find.byType(AppSoftGlassLight), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
    await tester.pumpWidget(_wrap(softLight: true, highContrast: true));
    expect(find.byType(AppSoftGlassLight), findsNothing);
  });

  testWidgets('touch and drag preserve static lighting and child gestures', (
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
              child: const SizedBox(width: 300, height: 100),
            );
          },
        ),
      ),
    );
    final before = builds;
    final painter = _lightPainter(tester);
    final rect = tester.getRect(find.byType(AppSoftGlassLight));
    final gesture = await tester.startGesture(rect.center);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    await gesture.moveBy(const Offset(50, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    expect(drags, greaterThan(0));
    expect(tester.binding.transientCallbackCount, 0);
    expect(_lightPainter(tester).shouldRepaint(painter), isFalse);
    await gesture.up();
    await tester.tapAt(rect.center);
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(builds, before);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('hover and cancellation leave static glass unchanged', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(softLight: true));
    final painter = _lightPainter(tester);
    final rect = tester.getRect(find.byType(AppSoftGlassLight));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(rect.center);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    await mouse.down(rect.center);
    await mouse.moveTo(rect.bottomRight + const Offset(24, 24));
    await mouse.cancel();
    await tester.pump();
    expect(_lightPainter(tester).shouldRepaint(painter), isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    await mouse.removePointer();
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
  });

  testWidgets('removing glass during a gesture leaves no pending animation', (
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
