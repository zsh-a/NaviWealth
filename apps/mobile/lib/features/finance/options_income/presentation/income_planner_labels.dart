/// Presentation helpers that turn Income Planner domain enums into their
/// localized display labels.
///
/// Lives in `presentation/` (not `domain/`) so the domain enum stays free
/// of `AppLocalizations` — same separation as the ledger uses for account
/// kind labels.
library;

import 'package:naviwealth/l10n/gen/app_localizations.dart';
import '../domain/options_strategy_profile.dart';
import '../domain/trade_journal_entry.dart';

String tradeJournalStatusLabel(
  AppLocalizations l10n,
  TradeJournalStatus status,
) {
  switch (status) {
    case TradeJournalStatus.open:
      return l10n.incomePlannerJournalStatusOpen;
    case TradeJournalStatus.closed:
      return l10n.incomePlannerJournalStatusClosed;
    case TradeJournalStatus.assigned:
      return l10n.incomePlannerJournalStatusAssigned;
    case TradeJournalStatus.expired:
      return l10n.incomePlannerJournalStatusExpired;
  }
}

String optionsStrategyKindShortLabel(
  AppLocalizations l10n,
  OptionsStrategyKind kind,
) {
  switch (kind) {
    case OptionsStrategyKind.cashSecuredPut:
      return l10n.incomePlannerChipCashSecuredPut;
    case OptionsStrategyKind.coveredCall:
      return l10n.incomePlannerChipCoveredCall;
  }
}

String optionsStrategyModeLabel(
  AppLocalizations l10n,
  OptionsStrategyMode mode,
) {
  switch (mode) {
    case OptionsStrategyMode.conservative:
      return l10n.incomePlannerProfileModeConservative;
    case OptionsStrategyMode.balanced:
      return l10n.incomePlannerProfileModeBalanced;
    case OptionsStrategyMode.aggressive:
      return l10n.incomePlannerProfileModeAggressive;
    case OptionsStrategyMode.custom:
      return l10n.incomePlannerProfileModeCustom;
  }
}
