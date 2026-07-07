import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/agents/agent_l10n.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('falls back to English when preferences are not available', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final l10n = agentL10n(container.read(_refProvider));

    expect(l10n.localeName, 'en');
    expect(agentLocaleIsZh(l10n), isFalse);
  });

  test('honors the app locale preference for zh agents', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    await container.read(localeProvider.notifier).set(const Locale('zh'));
    final l10n = agentL10n(container.read(_refProvider));

    expect(l10n.localeName, 'zh');
    expect(agentLocaleIsZh(l10n), isTrue);
  });
}

final _refProvider = Provider<Ref>((ref) => ref);
