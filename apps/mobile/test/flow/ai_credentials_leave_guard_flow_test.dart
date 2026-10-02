import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime/runner/agent_runtime_runner.dart';
import 'package:naviwealth/app/routing/router.dart';
import 'package:naviwealth/core/ai/llm_credentials/providers.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/security/in_memory_key_store.dart';
import 'package:naviwealth/core/shell/settings_route_paths.dart';
import 'package:naviwealth/features/settings/ui/ai/ai_llm_credentials_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import 'support/app_harness.dart';

void main() {
  testWidgets('AI profile protects route changes and Android system back', (
    tester,
  ) async {
    await bootApp(
      tester,
      initialLocation: SettingsRoutes.aiLlm,
      extraOverrides: [
        deviceLlmPlatformSupportedProvider.overrideWithValue(true),
        secureKeyStoreProvider.overrideWithValue(InMemoryKeyStore()),
        agentRuntimeProfileTurnRunnerProvider.overrideWithValue(null),
      ],
    );
    await tester.tap(find.text('Add provider'));
    await settle(tester);
    await tester.enterText(
      find.byKey(const Key('llm-profile-name')),
      'Unsaved provider',
    );
    await settle(tester);
    final router = ProviderScope.containerOf(
      tester.element(find.byType(AiLlmCredentialsPage)),
    ).read(appRouterProvider);
    final l10n = lookupAppLocalizations(const Locale('en'));
    router.go(SettingsRoutes.ai);
    await settle(tester);
    expect(find.text(l10n.unsavedChangesTitle), findsOneWidget);
    await tester.tap(find.text(l10n.unsavedChangesKeepEditing));
    await settle(tester);
    expect(router.routerDelegate.state.uri.path, SettingsRoutes.aiLlm);
    expect(find.text('Unsaved provider'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.text(l10n.unsavedChangesTitle), findsOneWidget);
    await tester.tap(find.text(l10n.unsavedChangesKeepEditing));
    await settle(tester);
    expect(find.text('Unsaved provider'), findsOneWidget);
    expect(router.routerDelegate.state.uri.path, SettingsRoutes.aiLlm);

    router.go(SettingsRoutes.ai);
    await settle(tester);
    await tester.tap(find.text(l10n.unsavedChangesDiscard));
    await settle(tester);
    expect(router.routerDelegate.state.uri.path, SettingsRoutes.ai);
    expect(find.byType(AiLlmCredentialsPage), findsNothing);
    router.go(SettingsRoutes.aiLlm);
    await settle(tester);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(router.routerDelegate.state.uri.path, SettingsRoutes.ai);
    expect(find.text(l10n.unsavedChangesTitle), findsNothing);
    await closeApp(tester);
  });
}
