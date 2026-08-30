import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/data/market/exceptions.dart';
import 'package:naviwealth/features/finance/investment/application/trade_entry_submission_service.dart';
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_entry_errors.dart';
import 'package:naviwealth/features/finance/rebalance/application/rebalance_execution_issue_classifier.dart';
import 'package:naviwealth/features/finance/rebalance/application/rebalance_trade_validation.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_execution.dart';

void main() {
  group('classifyRebalanceExecutionIssue', () {
    test('price unavailable is editable and apply may continue', () {
      final result = classifyRebalanceExecutionIssue(
        TradeEntryException(
          TradeEntryErrorCode.priceUnavailable,
          'No quote was available.',
        ),
        phase: RebalanceExecutionPhase.apply,
      );

      expect(result.issue.code, RebalanceExecutionIssueCode.priceRequired);
      expect(result.recoveryAction, RebalanceRecoveryAction.enterPrice);
      expect(result.stopBatch, isFalse);
    });

    test('only explicit temporary market failures are retryable', () {
      final result = classifyRebalanceExecutionIssue(
        TradeEntryException(
          TradeEntryErrorCode.priceUnavailable,
          'No quote was available.',
          cause: const NetworkException('offline'),
        ),
        phase: RebalanceExecutionPhase.apply,
      );

      expect(result.issue.code, RebalanceExecutionIssueCode.applyUnavailable);
      expect(result.recoveryAction, RebalanceRecoveryAction.retryApply);
      expect(result.stopBatch, isFalse);
    });

    test('unknown apply errors are fatal and not retryable', () {
      final result = classifyRebalanceExecutionIssue(
        StateError('unexpected'),
        phase: RebalanceExecutionPhase.apply,
      );

      expect(result.issue.code, RebalanceExecutionIssueCode.unknown);
      expect(result.recoveryAction, RebalanceRecoveryAction.none);
      expect(result.stopBatch, isTrue);
    });

    test('every undo business failure stops and retries undo', () {
      final result = classifyRebalanceExecutionIssue(
        StateError('undo failed'),
        phase: RebalanceExecutionPhase.undo,
      );

      expect(result.issue.code, RebalanceExecutionIssueCode.undoUnavailable);
      expect(result.recoveryAction, RebalanceRecoveryAction.retryUndo);
      expect(result.stopBatch, isTrue);
    });

    test('trade entry validation and holdings families stay editable', () {
      final invalid = classifyRebalanceExecutionIssue(
        TradeEntryException(TradeEntryErrorCode.currencyMismatch, 'currency'),
        phase: RebalanceExecutionPhase.apply,
      );
      final holdings = classifyRebalanceExecutionIssue(
        TradeEntryException(
          TradeEntryErrorCode.insufficientHoldings,
          'holdings',
        ),
        phase: RebalanceExecutionPhase.apply,
      );

      expect(invalid.issue.code, RebalanceExecutionIssueCode.invalidReview);
      expect(invalid.recoveryAction, RebalanceRecoveryAction.editReview);
      expect(holdings.issue.code, RebalanceExecutionIssueCode.holdingsChanged);
      expect(holdings.stopBatch, isFalse);
    });

    test(
      'rebalance validation distinguishes stale, owner, edit, and internal',
      () {
        ClassifiedRebalanceExecutionIssue classify(
          RebalanceTradeValidationCode code,
        ) => classifyRebalanceExecutionIssue(
          RebalanceTradeValidationError(code, code.name),
          phase: RebalanceExecutionPhase.apply,
        );

        expect(
          classify(RebalanceTradeValidationCode.staleSnapshot).issue.code,
          RebalanceExecutionIssueCode.staleReview,
        );
        expect(
          classify(RebalanceTradeValidationCode.ownerMismatch).issue.code,
          RebalanceExecutionIssueCode.ownerChanged,
        );
        expect(
          classify(RebalanceTradeValidationCode.ownerMismatch).stopBatch,
          isTrue,
        );
        expect(
          classify(RebalanceTradeValidationCode.accountInvalid).recoveryAction,
          RebalanceRecoveryAction.editReview,
        );
        expect(
          classify(RebalanceTradeValidationCode.identityMismatch).issue.code,
          RebalanceExecutionIssueCode.internal,
        );
      },
    );

    test(
      'submission contracts distinguish owner, edit, holdings, and internal',
      () {
        ClassifiedRebalanceExecutionIssue classify(
          TradeSubmissionContractErrorCode code,
        ) => classifyRebalanceExecutionIssue(
          TradeSubmissionContractError(code, code.name),
          phase: RebalanceExecutionPhase.apply,
        );

        expect(
          classify(TradeSubmissionContractErrorCode.ownerChanged).issue.code,
          RebalanceExecutionIssueCode.ownerChanged,
        );
        expect(
          classify(TradeSubmissionContractErrorCode.accountInvalid)
              .recoveryAction,
          RebalanceRecoveryAction.editReview,
        );
        expect(
          classify(TradeSubmissionContractErrorCode.insufficientFreshHoldings)
              .issue
              .code,
          RebalanceExecutionIssueCode.holdingsChanged,
        );
        expect(
          classify(TradeSubmissionContractErrorCode.databaseMismatch)
              .issue
              .code,
          RebalanceExecutionIssueCode.internal,
        );
        expect(
          classify(
            TradeSubmissionContractErrorCode.externalResolutionInTransaction,
          ).stopBatch,
          isTrue,
        );
      },
    );

    test('non-temporary market errors remain unknown and fatal', () {
      final result = classifyRebalanceExecutionIssue(
        const SymbolNotFoundException('missing'),
        phase: RebalanceExecutionPhase.apply,
      );

      expect(result.issue.code, RebalanceExecutionIssueCode.unknown);
      expect(result.recoveryAction, RebalanceRecoveryAction.none);
      expect(result.stopBatch, isTrue);
    });

    test(
      'unknown persisted codes degrade safely and debug text is bounded',
      () {
        final issue = RebalanceExecutionIssue.fromWire(
          code: 'futureCode',
          debugMessage: List.filled(600, 'x').join(),
        );

        expect(issue.code, RebalanceExecutionIssueCode.unknown);
        expect(issue.recoveryAction, RebalanceRecoveryAction.none);
        expect(issue.debugMessage, hasLength(512));
      },
    );
  });
}
