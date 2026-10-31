import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/app/app.dart';
import 'package:naviwealth/app/routing/router.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/settings/ui/overview/settings_overview.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/persistence/test_database.dart';

const _probeKey = Key('theme-probe');
const _draftKey = Key('theme-draft');

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Map<String, Object> preferences = const {},
  String initialLocation = '/',
}) async {
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures();
  tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

  SharedPreferences.setMockInitialValues({
    'naviwealth.locale': 'zh',
    'naviwealth.theme.material_style': 'translucent',
    ...preferences,
  });
  final prefs = await SharedPreferences.getInstance();
  final db = makeTestDatabase();
  addTearDown(db.close);
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(
          body: AppGlassSurface(
            child: SizedBox(
              key: _probeKey,
              height: 100,
              child: TextField(key: _draftKey),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/appearance',
        builder: (_, _) => const AppearanceSettingsPage(),
      ),
    ],
  );
  addTearDown(router.dispose);
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWith((_) async => db),
      appRouterProvider.overrideWithValue(router),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const NaviWealthApp(),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void _expectTheme(
  WidgetTester tester, {
  required Brightness brightness,
  required AppVisualStyle visual,
  required bool highContrast,
}) {
  final context = tester.element(find.byKey(_probeKey));
  final material = Theme.of(context);
  final forui = context.theme.colors;
  final app = context.appTheme;
  final expected = resolveAppTheme(
    ThemeInputs(
      brightness: brightness,
      marketMode: MarketColorMode.redUpGreenDown,
      visualStyle: visual,
      highContrast: highContrast,
      materialStyle: AppMaterialStyle.translucent,
    ),
  );
  expect(material.brightness, brightness);
  expect(forui.brightness, brightness);
  expect(app.brightness, brightness);
  expect(app.surfaces.canvas, expected.surfaces.canvas);
  expect(material.colorScheme.surface, app.surfaces.canvas);
  expect(forui.background, app.surfaces.canvas);
  expect(material.colorScheme.outline, expected.surfaces.border);
  expect(forui.border, expected.surfaces.border);
  expect(app.surfaces.border, expected.surfaces.border);
  expect(material.colorScheme.onSurfaceVariant, expected.content.muted);
  expect(forui.mutedForeground, expected.content.muted);
  expect(app.content.muted, expected.content.muted);
  expect(app.status.danger.fg, expected.status.danger.fg);
  expect(app.glass.chrome.liveBlur, !highContrast);
  expect(
    find.byType(BackdropFilter),
    highContrast ? findsNothing : findsOneWidget,
  );
}

void main() {
  for (final visual in AppVisualStyle.values) {
    for (final mode in ThemeMode.values) {
      testWidgets(
        'system contrast updates all theme layers without losing input '
        '(${visual.name}/${mode.name})',
        (tester) async {
          final container = await _pump(
            tester,
            preferences: {
              'naviwealth.theme.visual_style': visual.name,
              'naviwealth.theme.mode': mode.name,
            },
          );
          await tester.enterText(find.byKey(_draftKey), '保留输入');
          final draft = tester.state<EditableTextState>(
            find.byType(EditableText),
          );
          final route = ModalRoute.of(tester.element(find.byKey(_probeKey)));
          for (final platformBrightness in Brightness.values) {
            tester.platformDispatcher.platformBrightnessTestValue =
                platformBrightness;
            final brightness = switch (mode) {
              ThemeMode.light => Brightness.light,
              ThemeMode.dark => Brightness.dark,
              ThemeMode.system => platformBrightness,
            };
            for (final highContrast in [false, true, false]) {
              tester.platformDispatcher.accessibilityFeaturesTestValue =
                  FakeAccessibilityFeatures(highContrast: highContrast);
              await tester.pumpAndSettle();
              _expectTheme(
                tester,
                brightness: brightness,
                visual: visual,
                highContrast: highContrast,
              );
              expect(tester.state(find.byType(EditableText)), same(draft));
              expect(draft.widget.controller.text, '保留输入');
              expect(draft.widget.focusNode.hasFocus, isTrue);
              expect(
                ModalRoute.of(tester.element(find.byKey(_probeKey))),
                same(route),
              );
              expect(container.read(themeModeProvider), mode);
              expect(
                container.read(materialStyleProvider),
                AppMaterialStyle.translucent,
              );
              expect(tester.takeException(), isNull);
            }
          }
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  for (final legacy in ['oled', 'highContrast']) {
    testWidgets('retired $legacy preference falls back to normal dark', (
      tester,
    ) async {
      await _pump(
        tester,
        preferences: {
          'naviwealth.theme.surface_style': legacy,
          'naviwealth.theme.mode': 'dark',
          'naviwealth.theme.visual_style': 'refined',
        },
      );
      _expectTheme(
        tester,
        brightness: Brightness.dark,
        visual: AppVisualStyle.refined,
        highContrast: false,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('appearance settings omit retired display options', (
    tester,
  ) async {
    await _pump(tester, initialLocation: '/appearance');
    expect(find.text('界面风格'), findsNothing);
    expect(find.text('材质效果'), findsOneWidget);
    expect(find.text('主题模式'), findsOneWidget);
    expect(find.text('显示增强'), findsNothing);
    expect(find.textContaining('OLED'), findsNothing);
    expect(find.text('高对比'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
