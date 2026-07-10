import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../domain/rebalance_execution.dart';

/// User-facing copy for persisted execution issues.
///
/// Deliberately resolves from the stable issue code only. The persisted debug
/// message is diagnostic data and must never cross into the UI.
extension RebalanceExecutionIssuePresentation on RebalanceExecutionIssue {
  String userMessage(AppLocalizations l10n) => switch (code) {
    RebalanceExecutionIssueCode.priceRequired =>
      l10n.rebalanceExecutionIssuePriceRequired,
    RebalanceExecutionIssueCode.invalidReview =>
      l10n.rebalanceExecutionIssueInvalidReview,
    RebalanceExecutionIssueCode.staleReview =>
      l10n.rebalanceExecutionIssueStaleReview,
    RebalanceExecutionIssueCode.holdingsChanged =>
      l10n.rebalanceExecutionIssueHoldingsChanged,
    RebalanceExecutionIssueCode.ownerChanged =>
      l10n.rebalanceExecutionIssueOwnerChanged,
    RebalanceExecutionIssueCode.applyUnavailable =>
      l10n.rebalanceExecutionIssueApplyUnavailable,
    RebalanceExecutionIssueCode.undoUnavailable =>
      l10n.rebalanceExecutionIssueUndoUnavailable,
    RebalanceExecutionIssueCode.internal ||
    RebalanceExecutionIssueCode.unknown => l10n.rebalanceExecutionIssueUnsafe,
    RebalanceExecutionIssueCode.recoveryCorrupt =>
      l10n.rebalanceExecutionIssueRecoveryCorrupt,
    RebalanceExecutionIssueCode.legacyApplyFailure =>
      l10n.rebalanceExecutionIssueLegacyApplyFailure,
    RebalanceExecutionIssueCode.legacyUndoFailure =>
      l10n.rebalanceExecutionIssueLegacyUndoFailure,
  };
}
