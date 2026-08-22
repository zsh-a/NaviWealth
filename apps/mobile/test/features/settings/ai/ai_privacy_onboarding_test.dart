import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/settings/ui/ai/ai_privacy_onboarding.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Widget> _wrap() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh', 'CN'),
      home: FTheme(
        data: FTheme.neutral.light.desktop,
        child: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAiPrivacyOnboardingSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('AI privacy onboarding sheet fits a compact viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await _wrap());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('选择你的 AI 隐私偏好'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('ai-privacy-onboarding-dialog')),
      findsNothing,
    );
  });

  testWidgets('AI privacy onboarding uses a centered desktop dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await _wrap());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey<String>('ai-privacy-onboarding-dialog')),
      findsOneWidget,
    );
  });

  testWidgets('dismissed onboarding does not re-fire after a shell remount', (
    tester,
  ) async {
    resetAiPrivacyOnboardingForTest();
    addTearDown(resetAiPrivacyOnboardingForTest);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    Widget app() => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh', 'CN'),
        home: FTheme(
          data: FTheme.neutral.light.desktop,
          child: const Scaffold(body: AiPrivacyOnboardingMount()),
        ),
      ),
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('选择你的 AI 隐私偏好'), findsOneWidget);

    await tester.tap(find.text('好的'));
    await tester.pumpAndSettle();
    expect(find.text('选择你的 AI 隐私偏好'), findsNothing);

    // Settings lives outside the dock shell, so a settings detour unmounts
    // the mount; returning remounts it with fresh state. The seen flag must
    // hold for the rest of the session — a re-fired sheet suppresses the
    // mobile floating dock every time the user comes back to Today.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('选择你的 AI 隐私偏好'), findsNothing);
  });
}
