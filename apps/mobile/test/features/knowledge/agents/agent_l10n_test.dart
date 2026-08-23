import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/knowledge/agents/_agent_l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _agentReviewTitleProvider = Provider<String>(
  (ref) => knowledgeAgentL10n(ref).knowledgeAgentReviewTitle,
);

final _agentContradictionProvider = Provider<String>(
  (ref) => knowledgeAgentL10n(
    ref,
  ).knowledgeAgentContradictionSummaryOne('detail', 'assumption_invalidated'),
);

Future<ProviderContainer> _containerWithLocale(Locale locale) async {
  SharedPreferences.setMockInitialValues(const <String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  await container.read(localeProvider.notifier).set(locale);
  return container;
}

void main() {
  test('Knowledge agent text follows English locale', () async {
    final container = await _containerWithLocale(const Locale('en'));

    expect(container.read(_agentReviewTitleProvider), 'Weekly review');
    expect(
      container.read(_agentContradictionProvider),
      'Detected 1 assumption_invalidated issue: detail',
    );
  });

  test('Knowledge agent text follows Chinese locale', () async {
    final container = await _containerWithLocale(const Locale('zh'));

    expect(container.read(_agentReviewTitleProvider), '本周复盘');
    expect(
      container.read(_agentContradictionProvider),
      '检出 1 处 assumption_invalidated：detail',
    );
  });
}
