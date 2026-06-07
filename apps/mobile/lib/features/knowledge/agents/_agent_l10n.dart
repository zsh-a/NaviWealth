/// Locale helpers for KnowledgeOS agents.
///
/// Agents run without a BuildContext, but they still emit user-visible
/// summaries (agent run result, memory title/summary, local notifications).
/// Read the app locale preference directly so those surfaces follow the user
/// setting without widening the cross-domain AgentContext contract.
library;

import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/preferences/theme_preferences.dart';
import '../../../l10n/gen/app_localizations.dart';

AppLocalizations knowledgeAgentL10n(Ref ref) {
  final preferred = ref.read(localeProvider);
  final system = PlatformDispatcher.instance.locale;
  final locale = preferred ?? system;
  final supported = locale.languageCode == 'zh'
      ? const Locale('zh')
      : const Locale('en');
  return lookupAppLocalizations(supported);
}
