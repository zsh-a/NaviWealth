import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/activity/ui/activity_action_panel.dart';
import 'package:naviwealth/features/settings/ui/overview/appearance_style_picker.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _AppearanceApp extends ConsumerWidget {
  const _AppearanceApp({required this.child, this.textScale = 1});

  final Widget child;
  final double textScale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visual = ref.watch(visualStyleProvider);
    final material = ref.watch(materialStyleProvider);
    return MaterialApp(
      theme: AppTheme.light(visualStyle: visual),
      highContrastTheme: AppTheme.light(
        visualStyle: visual,
        highContrast: true,
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: FTheme(
          data: buildAppForuiTheme(
            brightness: Brightness.light,
            touch: true,
            visualStyle: visual,
            highContrast: MediaQuery.highContrastOf(context),
          ),
          child: AppThemeScope(
            data: resolveAppTheme(
              ThemeInputs(
                brightness: Brightness.light,
                marketMode: MarketColorMode.redUpGreenDown,
                visualStyle: visual,
                materialStyle: material,
                highContrast: MediaQuery.highContrastOf(context),
              ),
            ),
            child: child!,
          ),
        ),
      ),
      home: child,
    );
  }
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  Widget child, {
  Map<String, Object> preferences = const {},
  double textScale = 1,
}) async {
  SharedPreferences.setMockInitialValues(preferences);
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: _AppearanceApp(textScale: textScale, child: child),
    ),
  );
  return ProviderScope.containerOf(tester.element(find.byType(_AppearanceApp)));
}

void main() {
  setUp(() => appSheetOverlayDepthListenable.value = 0);

  test(
    'old and unknown preferences fall back; choices persist independently',
    () async {
      SharedPreferences.setMockInitialValues({
        'naviwealth.theme.visual_style': 'future-style',
        'naviwealth.theme.material_style': 'future-material',
      });
      final prefs = await SharedPreferences.getInstance();
      final visual = VisualStyleController(prefs);
      final material = MaterialStyleController(prefs);
      addTearDown(visual.dispose);
      addTearDown(material.dispose);
      expect(visual.state, AppVisualStyle.classic);
      expect(material.state, AppMaterialStyle.solid);
      await visual.set(AppVisualStyle.refined);
      await material.set(AppMaterialStyle.translucent);
      final reloadedVisual = VisualStyleController(prefs);
      final reloadedMaterial = MaterialStyleController(prefs);
      addTearDown(reloadedVisual.dispose);
      addTearDown(reloadedMaterial.dispose);
      expect(reloadedVisual.state, AppVisualStyle.refined);
      expect(reloadedMaterial.state, AppMaterialStyle.translucent);
    },
  );

  for (final visual in AppVisualStyle.values) {
    for (final brightness in Brightness.values) {
      test(
        'theme systems share surfaces for ${visual.name}/${brightness.name}',
        () {
          final app = resolveAppTheme(
            ThemeInputs(
              brightness: brightness,
              marketMode: MarketColorMode.colorblind,
              visualStyle: visual,
            ),
          );
          final forui = buildAppForuiTheme(
            brightness: brightness,
            touch: true,
            visualStyle: visual,
          );
          final material = brightness == Brightness.light
              ? AppTheme.light(visualStyle: visual)
              : AppTheme.dark(visualStyle: visual);
          expect(forui.colors.background, app.surfaces.canvas);
          expect(forui.colors.card, app.surfaces.card);
          expect(material.colorScheme.surface, app.surfaces.canvas);
          expect(material.colorScheme.surfaceContainerLow, app.surfaces.card);
          expect(app.glass.sheet.liveBlur, isFalse);
          expect(app.glass.chrome.liveBlur, isFalse);
          expect(
            app.type.numericMono.fontFamily,
            TypographyTokens.fontFamilyMono,
          );
        },
      );
    }

    testWidgets(
      'activity panel has no backdrop filters while moving (${visual.name})',
      (tester) async {
        var closed = false;
        tester.view
          ..physicalSize = const Size(390, 844)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await _pump(
          tester,
          Scaffold(
            body: Builder(
              builder: (context) => FButton(
                onPress: () async {
                  await showActivityActionPanel(context);
                  closed = true;
                },
                child: const Text('Open'),
              ),
            ),
          ),
          preferences: {'naviwealth.theme.visual_style': visual.name},
        );
        await tester.tap(find.text('Open'));
        await tester.pump();
        for (var frame = 0; frame < 12; frame++) {
          await tester.pump(const Duration(microseconds: 8333));
          expect(find.byType(BackdropFilter), findsNothing);
        }
        expect(find.byType(AnimatedModalBarrier), findsOneWidget);
        await tester.pumpAndSettle();
        expect(find.text('记录活动'), findsOneWidget);
        final route = ModalRoute.of(tester.element(find.byType(AppSheet)))!;
        Navigator.of(tester.element(find.byType(AppSheet))).pop();
        await tester.pump();
        expect(appSheetOverlayDepthListenable.value, 1);
        expect(
          closed,
          isTrue,
          reason: 'sheet results retain pop-time semantics',
        );
        expect(route.isActive, isFalse);
        await tester.pumpAndSettle();
        expect(appSheetOverlayDepthListenable.value, 0);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }

  for (final form in [true, false]) {
    testWidgets(
      'switching presets and materials preserves draft and focus (form: $form)',
      (tester) async {
        tester.view
          ..physicalSize = const Size(390, 844)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final controller = TextEditingController();
        final focus = FocusNode();
        addTearDown(controller.dispose);
        addTearDown(focus.dispose);
        final container = await _pump(
          tester,
          Scaffold(
            body: Builder(
              builder: (context) => FButton(
                onPress: () {
                  final field = FTextField(
                    key: const Key('draft'),
                    control: FTextFieldControl.managed(controller: controller),
                    focusNode: focus,
                  );
                  if (form) {
                    showAppFormSheet<void>(
                      context: context,
                      builder: (_) => AppSheet(title: 'Draft', child: field),
                    );
                  } else {
                    showAppSheet<void>(
                      context: context,
                      title: 'Draft',
                      builder: (_) => field,
                    );
                  }
                },
                child: const Text('Open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('draft')), '保留我的输入');
        final route = ModalRoute.of(
          tester.element(find.byKey(const Key('draft'))),
        );
        final formState = tester.state(find.byType(EditableText));
        for (final style in [AppVisualStyle.refined, AppVisualStyle.classic]) {
          await container.read(visualStyleProvider.notifier).set(style);
          for (final material in AppMaterialStyle.values) {
            await container.read(materialStyleProvider.notifier).set(material);
            await tester.pumpAndSettle();
            expect(
              ModalRoute.of(tester.element(find.byKey(const Key('draft')))),
              same(route),
            );
            expect(tester.state(find.byType(EditableText)), same(formState));
            expect(controller.text, '保留我的输入');
            expect(focus.hasFocus, isTrue);
            expect(
              find.byType(BackdropFilter),
              !form && material == AppMaterialStyle.translucent
                  ? findsOneWidget
                  : findsNothing,
            );
            expect(tester.takeException(), isNull);
          }
        }
        Navigator.of(tester.element(find.byKey(const Key('draft')))).pop();
        await tester.pumpAndSettle();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }

  testWidgets('translucency is opt-in and follows system high contrast', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      const Scaffold(body: AppSheetSurface(child: Text('Surface'))),
    );
    expect(find.byType(BackdropFilter), findsNothing);
    await container
        .read(materialStyleProvider.notifier)
        .set(AppMaterialStyle.translucent);
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsOneWidget);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(highContrast: true);
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets(
    'appearance picker applies and saves a preset at large text scale',
    (tester) async {
      tester.view
        ..physicalSize = const Size(320, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = await _pump(
        tester,
        const Scaffold(
          body: SingleChildScrollView(child: AppearanceStylePicker()),
        ),
        textScale: 1.8,
      );
      final option = find.byKey(const ValueKey('appearance-style.refined'));
      await tester.ensureVisible(option);
      await tester.tap(option);
      await tester.pumpAndSettle();
      expect(container.read(visualStyleProvider), AppVisualStyle.refined);
      expect(
        container
            .read(sharedPreferencesProvider)
            .getString('naviwealth.theme.visual_style'),
        'refined',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
