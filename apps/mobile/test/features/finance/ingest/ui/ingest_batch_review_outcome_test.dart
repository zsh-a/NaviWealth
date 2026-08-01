import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/composition/proposal_apply_state.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_confirm_service.dart';
import 'package:naviwealth/features/finance/ingest/domain/ingest_models.dart';
import 'package:naviwealth/features/finance/ingest/ui/ingest_batch_review_outcome.dart';

IngestDraft _draft(String id) => IngestDraft(
  draftId: id,
  ownerUserId: 'u1',
  createdAt: DateTime.utc(2026, 8, 1),
  sourceKind: IngestSourceKind.csv,
  parsed: ParsedTransaction(
    description: id,
    amountMinor: -100,
    currency: 'CNY',
    occurredAt: DateTime.utc(2026, 8, 1),
  ),
  verdict: DedupVerdict.newTxn,
  status: DraftStatus.pending,
);

ConfirmedIngestItem _confirmed(String id) => ConfirmedIngestItem(
  draft: _draft(id),
  applyState: ProposalApplyState(
    status: ProposalApplyStatus.applied,
    appliedEntityId: 'entry-$id',
  ),
);

IngestBatchItemFailure<IngestDraft> _failure(
  String id, {
  required IngestRecovery recovery,
  ConfirmedIngestItem? item,
}) => IngestBatchItemFailure<IngestDraft>(
  item: _draft(id),
  error: IngestConfirmException(
    IngestConfirmError.lifecycleWriteFailed,
    'failed',
    recovery: recovery,
    item: item,
  ),
);

void main() {
  test('projects confirmed drafts into immutable undo state', () {
    final outcome = IngestBatchReviewOutcome.from(
      IngestBatchConfirmResult(
        confirmed: <ConfirmedIngestItem>[_confirmed('one'), _confirmed('two')],
        failures: const <IngestBatchItemFailure<IngestDraft>>[],
      ),
    );

    expect(outcome.confirmedDraftIds, <String>{'one', 'two'});
    expect(outcome.canUndo, isTrue);
    expect(outcome.hasFailures, isFalse);
    expect(outcome.needsManualFinalize, isFalse);
  });

  test('separates manual finalization from retryable failures', () {
    final pending = _confirmed('pending-finalize');
    final outcome = IngestBatchReviewOutcome.from(
      IngestBatchConfirmResult(
        confirmed: const <ConfirmedIngestItem>[],
        failures: <IngestBatchItemFailure<IngestDraft>>[
          _failure(
            'pending-finalize',
            recovery: IngestRecovery.finalizeApplied,
            item: pending,
          ),
          _failure('retry', recovery: IngestRecovery.retryOperation),
          _failure('restore', recovery: IngestRecovery.restoreDraft),
        ],
      ),
    );

    expect(outcome.pendingFinalizeByDraftId, <String, ConfirmedIngestItem>{
      'pending-finalize': pending,
    });
    expect(
      outcome.retryFailures.map((failure) => failure.item.draftId),
      <String>['retry', 'restore'],
    );
    expect(outcome.failureCount, 3);
    expect(outcome.needsManualFinalize, isTrue);
    expect(outcome.canUndo, isFalse);
  });

  test('keeps malformed finalize failures visible as retry failures', () {
    final outcome = IngestBatchReviewOutcome.from(
      IngestBatchConfirmResult(
        confirmed: const <ConfirmedIngestItem>[],
        failures: <IngestBatchItemFailure<IngestDraft>>[
          _failure('missing-item', recovery: IngestRecovery.finalizeApplied),
        ],
      ),
    );

    expect(outcome.pendingFinalizeByDraftId, isEmpty);
    expect(outcome.retryFailures, hasLength(1));
    expect(outcome.hasFailures, isTrue);
  });
}
