/// Locale helpers for scheduled agents.
///
/// Agents run without a BuildContext, but they still persist user-visible
/// summaries, artifacts, actions, and local notifications. Read the app locale
/// preference directly so those surfaces follow the user's language setting
/// without widening the cross-domain AgentContext contract.
library;

import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/preferences/theme_preferences.dart';
import '../../../l10n/gen/app_localizations.dart';

AppLocalizations agentL10n(Ref ref) {
  return lookupAppLocalizations(agentLocale(ref));
}

Locale agentLocale(Ref ref) {
  Locale? preferred;
  try {
    preferred = ref.read(localeProvider);
  } on Object {
    return const Locale('en');
  }
  return supportedAgentLocale(preferred ?? PlatformDispatcher.instance.locale);
}

AppLocalizations defaultAgentL10n([Locale? locale]) {
  return lookupAppLocalizations(
    supportedAgentLocale(locale ?? const Locale('en')),
  );
}

Locale supportedAgentLocale(Locale locale) {
  return locale.languageCode == 'zh' ? const Locale('zh') : const Locale('en');
}

bool agentLocaleIsZh(AppLocalizations l10n) => l10n.localeName == 'zh';
