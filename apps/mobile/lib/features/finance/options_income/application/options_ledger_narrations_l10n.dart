/// Locale-aware [OptionsLedgerNarrations] backed by AppLocalizations.
library;

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:naviwealth/core/ai/agents/agent_l10n.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import 'options_ledger_narrations.dart';

final optionsLedgerNarrationsProvider = Provider<OptionsLedgerNarrations>((
  ref,
) {
  final locale = supportedAgentLocale(
    ref.watch(localeProvider) ?? PlatformDispatcher.instance.locale,
  );
  return LocalizedOptionsLedgerNarrations(lookupAppLocalizations(locale));
});

class LocalizedOptionsLedgerNarrations implements OptionsLedgerNarrations {
  const LocalizedOptionsLedgerNarrations(this._l10n);

  final AppLocalizations _l10n;

  @override
  String premium(String optionSymbol) =>
      _l10n.optionsLedgerPremium(optionSymbol);

  @override
  String closeDebit(String optionSymbol) =>
      _l10n.optionsLedgerCloseDebit(optionSymbol);

  @override
  String putAssigned(String symbol) => _l10n.optionsLedgerPutAssigned(symbol);

  @override
  String callAssigned(String symbol) => _l10n.optionsLedgerCallAssigned(symbol);

  @override
  String leapsOpen(String optionSymbol) =>
      _l10n.optionsLedgerLeapsOpen(optionSymbol);

  @override
  String leapsClose(String optionSymbol) =>
      _l10n.optionsLedgerLeapsClose(optionSymbol);

  @override
  String leapsExercise(String optionSymbol) =>
      _l10n.optionsLedgerLeapsExercise(optionSymbol);

  @override
  String leapsExpired(String optionSymbol) =>
      _l10n.optionsLedgerLeapsExpired(optionSymbol);
}
