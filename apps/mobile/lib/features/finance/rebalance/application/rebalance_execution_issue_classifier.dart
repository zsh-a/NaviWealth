import 'package:naviwealth/features/finance/data/market/exceptions.dart';
import 'package:naviwealth/features/finance/investment/application/trade_entry_submission_service.dart';
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_entry_errors.dart';

import '../domain/rebalance_execution.dart';
import 'rebalance_trade_validation.dart';

final class ClassifiedRebalanceExecutionIssue {
  const ClassifiedRebalanceExecutionIssue({
    required this.issue,
    required this.stopBatch,
  });

  final RebalanceExecutionIssue issue;
  RebalanceRecoveryAction get recoveryAction => issue.recoveryAction;
  final bool stopBatch;
}

ClassifiedRebalanceExecutionIssue classifyRebalanceExecutionIssue(
  Object error, {
  required RebalanceExecutionPhase phase,
}) {
  if (phase == RebalanceExecutionPhase.undo) {
    return _classified(
      RebalanceExecutionIssueCode.undoUnavailable,
      error,
      stop: true,
    );
  }

  if (error is TradeEntryException) {
    return switch (error.code) {
      TradeEntryErrorCode.priceUnavailable =>
        _temporaryMarketFailure(error.cause)
            ? _classified(RebalanceExecutionIssueCode.applyUnavailable, error)
            : _classified(RebalanceExecutionIssueCode.priceRequired, error),
      TradeEntryErrorCode.insufficientHoldings => _classified(
        RebalanceExecutionIssueCode.holdingsChanged,
        error,
      ),
      TradeEntryErrorCode.quantityNotPositive ||
      TradeEntryErrorCode.quantityScaleExceeded ||
      TradeEntryErrorCode.amountNegative ||
      TradeEntryErrorCode.currencyMismatch ||
      TradeEntryErrorCode.fieldRequired => _classified(
        RebalanceExecutionIssueCode.invalidReview,
        error,
      ),
    };
  }

  if (error is RebalanceTradeValidationError) {
    return switch (error.code) {
      RebalanceTradeValidationCode.staleSnapshot => _classified(
        RebalanceExecutionIssueCode.staleReview,
        error,
      ),
      RebalanceTradeValidationCode.ownerMismatch => _classified(
        RebalanceExecutionIssueCode.ownerChanged,
        error,
        stop: true,
      ),
      RebalanceTradeValidationCode.accountInvalid ||
      RebalanceTradeValidationCode.cashAccountInvalid ||
      RebalanceTradeValidationCode.assetInvalid ||
      RebalanceTradeValidationCode.unsupportedAsset => _classified(
        RebalanceExecutionIssueCode.invalidReview,
        error,
      ),
      RebalanceTradeValidationCode.missingRequest ||
      RebalanceTradeValidationCode.identityMismatch ||
      RebalanceTradeValidationCode.directionMismatch ||
      RebalanceTradeValidationCode.assetTargetMismatch ||
      RebalanceTradeValidationCode.categoryMismatch => _classified(
        RebalanceExecutionIssueCode.internal,
        error,
        stop: true,
      ),
    };
  }

  if (error is TradeSubmissionContractError) {
    return switch (error.code) {
      TradeSubmissionContractErrorCode.ownerChanged => _classified(
        RebalanceExecutionIssueCode.ownerChanged,
        error,
        stop: true,
      ),
      TradeSubmissionContractErrorCode.accountInvalid ||
      TradeSubmissionContractErrorCode.cashAccountInvalid ||
      TradeSubmissionContractErrorCode.assetInvalid => _classified(
        RebalanceExecutionIssueCode.invalidReview,
        error,
      ),
      TradeSubmissionContractErrorCode.insufficientFreshHoldings ||
      TradeSubmissionContractErrorCode.backdatedSell => _classified(
        RebalanceExecutionIssueCode.holdingsChanged,
        error,
      ),
      TradeSubmissionContractErrorCode.databaseMismatch ||
      TradeSubmissionContractErrorCode.identityMismatch ||
      TradeSubmissionContractErrorCode.externalResolutionInTransaction =>
        _classified(RebalanceExecutionIssueCode.internal, error, stop: true),
    };
  }

  if (error is NetworkException ||
      error is RateLimitException ||
      error is ProviderUnavailableException) {
    return _classified(RebalanceExecutionIssueCode.applyUnavailable, error);
  }

  return _classified(RebalanceExecutionIssueCode.unknown, error, stop: true);
}

bool _temporaryMarketFailure(Object? error) {
  var current = error;
  for (var depth = 0; current != null && depth < 8; depth++) {
    if (current is NetworkException ||
        current is RateLimitException ||
        current is ProviderUnavailableException) {
      return true;
    }
    current = switch (current) {
      TradeEntryException exception => exception.cause,
      MarketDataException exception => exception.cause,
      _ => null,
    };
  }
  return false;
}

ClassifiedRebalanceExecutionIssue _classified(
  RebalanceExecutionIssueCode code,
  Object error, {
  bool stop = false,
}) => ClassifiedRebalanceExecutionIssue(
  issue: RebalanceExecutionIssue(code, error.toString()),
  stopBatch: stop,
);
