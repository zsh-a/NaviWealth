import '../data/ingest_confirm_service.dart';
import '../domain/ingest_models.dart';

/// Immutable page-facing projection of a batch confirmation result.
///
/// The confirmation service reports operation-level failures. The review UI
/// additionally needs to distinguish applied ledger writes that still require
/// lifecycle finalization from failures that remain safe to retry.
class IngestBatchReviewOutcome {
  IngestBatchReviewOutcome._({
    required this.confirmed,
    required this.confirmedDraftIds,
    required this.pendingFinalizeByDraftId,
    required this.retryFailures,
    required this.failureCount,
  });

  factory IngestBatchReviewOutcome.from(IngestBatchConfirmResult result) {
    final pendingFinalize = <String, ConfirmedIngestItem>{};
    final retryFailures = <IngestBatchItemFailure<IngestDraft>>[];
    for (final failure in result.failures) {
      final item = failure.error.item;
      if (failure.error.recovery == IngestRecovery.finalizeApplied &&
          item != null) {
        pendingFinalize[item.draft.draftId] = item;
      } else {
        retryFailures.add(failure);
      }
    }
    final confirmed = List<ConfirmedIngestItem>.unmodifiable(result.confirmed);
    return IngestBatchReviewOutcome._(
      confirmed: confirmed,
      confirmedDraftIds: Set<String>.unmodifiable(
        confirmed.map((item) => item.draft.draftId),
      ),
      pendingFinalizeByDraftId: Map<String, ConfirmedIngestItem>.unmodifiable(
        pendingFinalize,
      ),
      retryFailures: List<IngestBatchItemFailure<IngestDraft>>.unmodifiable(
        retryFailures,
      ),
      failureCount: result.failures.length,
    );
  }

  final List<ConfirmedIngestItem> confirmed;
  final Set<String> confirmedDraftIds;
  final Map<String, ConfirmedIngestItem> pendingFinalizeByDraftId;
  final List<IngestBatchItemFailure<IngestDraft>> retryFailures;
  final int failureCount;

  bool get hasFailures => failureCount > 0;
  bool get needsManualFinalize => pendingFinalizeByDraftId.isNotEmpty;
  bool get canUndo => confirmed.isNotEmpty;
}
