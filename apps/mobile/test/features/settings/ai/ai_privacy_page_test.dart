import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/ai_privacy_settings.dart';
import 'package:naviwealth/core/ai/llm_credentials/providers.dart';
import 'package:naviwealth/core/shell/settings_ui/inline_setting_row.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/settings/ui/ai/ai_privacy_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/test_app_theme.dart';

void main() {
  Future<ProviderContainer> pump(
    WidgetTester tester, {
    required bool supported,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        deviceLlmPlatformSupportedProvider.overrideWithValue(supported),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => buildTestAppTheme(context, child!),
          home: const AiPrivacyPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('native document permission defaults off and persists a tap', (
    tester,
  ) async {
    final container = await pump(tester, supported: true);
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(
      container.read(aiPrivacySettingsProvider).allowDocumentRecognition,
      isFalse,
    );
    expect(find.text(l10n.aiPrivacyIntro), findsOneWidget);
    await tester.tap(find.text(l10n.aiPrivacyDocumentRecognitionLabel));
    await tester.pumpAndSettle();
    expect(
      container.read(aiPrivacySettingsProvider).allowDocumentRecognition,
      isTrue,
    );
    container.invalidate(aiPrivacySettingsProvider);
    expect(
      container.read(aiPrivacySettingsProvider).allowDocumentRecognition,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('unsupported platforms show no document permission control', (
    tester,
  ) async {
    await pump(tester, supported: false);
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(find.text(l10n.settingsAiNativeOnly), findsOneWidget);
    expect(find.byType(InlineSwitchRow), findsNothing);
    expect(find.byType(Dialog), findsNothing);
  });
}
