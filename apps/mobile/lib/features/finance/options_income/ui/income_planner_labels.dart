/// UI helpers that turn Income Planner domain enums into their
/// localized display labels.
///
/// Lives in `ui/` (not `domain/`) so the domain enum stays free
/// of `AppLocalizations` — same separation as the ledger uses for account
/// kind labels. Every income surface (planner, wheel lifecycle, strategy
/// overview) reads these single-copy tables instead of keeping local
/// switches that drift apart.
library;

import 'package:flutter/widgets.dart' show IconData;
import 'package:forui/forui.dart';

import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../domain/leaps_call_position.dart';
import '../domain/options_opportunity.dart';
import '../domain/options_strategy_profile.dart';
import '../domain/trade_journal_entry.dart';
import '../domain/wheel_lifecycle.dart';

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

String opportunityStrategyShortLabel(
  AppLocalizations l10n,
  OpportunityStrategy strategy,
) => switch (strategy) {
  OpportunityStrategy.cashSecuredPut => l10n.incomePlannerChipCashSecuredPut,
  OpportunityStrategy.coveredCall => l10n.incomePlannerChipCoveredCall,
  OpportunityStrategy.leapsCall => l10n.incomePlannerChipLeaps,
};

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

String wheelStageLabel(AppLocalizations l10n, WheelStage stage) =>
    switch (stage) {
      WheelStage.between => l10n.planWheelStageBetween,
      WheelStage.cashWaiting => l10n.planWheelStageCashWaiting,
      WheelStage.shortPut => l10n.planWheelStageShortPut,
      WheelStage.putExpired => l10n.planWheelStagePutExpired,
      WheelStage.putAssigned => l10n.planWheelStagePutAssigned,
      WheelStage.sharesHeld => l10n.planWheelStageSharesHeld,
      WheelStage.shortCall => l10n.planWheelStageShortCall,
      WheelStage.mixedOpen => l10n.planWheelStageMixedOpen,
      WheelStage.callExpired => l10n.planWheelStageCallExpired,
      WheelStage.callCalled => l10n.planWheelStageCallCalled,
    };

IconData wheelStageIcon(WheelStage stage) => switch (stage) {
  WheelStage.between => FLucideIcons.circle,
  WheelStage.cashWaiting => FLucideIcons.wallet,
  WheelStage.shortPut => FLucideIcons.arrowDownLeft,
  WheelStage.putExpired => FLucideIcons.circleCheck,
  WheelStage.putAssigned => FLucideIcons.logIn,
  WheelStage.sharesHeld => FLucideIcons.package,
  WheelStage.shortCall => FLucideIcons.arrowUpRight,
  WheelStage.mixedOpen => FLucideIcons.layers3,
  WheelStage.callExpired => FLucideIcons.circleCheck,
  WheelStage.callCalled => FLucideIcons.logOut,
};

String wheelNextActionLabel(
  AppLocalizations l10n,
  WheelNextAction action,
) => switch (action) {
  WheelNextAction.reviewOpenPositions => l10n.incomePlannerWheelNextReviewOpen,
  WheelNextAction.waitForPut => l10n.incomePlannerWheelNextWaitPut,
  WheelNextAction.recordPutOutcome => l10n.incomePlannerWheelNextRecordPut,
  WheelNextAction.scanCoveredCall => l10n.incomePlannerWheelNextScanCall,
  WheelNextAction.waitForCall => l10n.incomePlannerWheelNextWaitCall,
  WheelNextAction.recordCallOutcome => l10n.incomePlannerWheelNextRecordCall,
  WheelNextAction.startNewPut => l10n.incomePlannerWheelNextStartPut,
};

String leapsCallStatusLabel(AppLocalizations l10n, LeapsCallStatus status) =>
    switch (status) {
      LeapsCallStatus.open => l10n.leapsOverlayStatusOpen,
      LeapsCallStatus.closed => l10n.leapsOverlayStatusClosed,
      LeapsCallStatus.exercised => l10n.leapsOverlayStatusExercised,
      LeapsCallStatus.expired => l10n.leapsOverlayStatusExpired,
    };
