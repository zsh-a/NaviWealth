/// §5.10.10 / S5a step ⑦ — confirmation.
///
/// A confirmed draft is turned into a `ProposalKind.expense`
/// [ReadyProposalPlan] and pushed through the **existing**
/// [ProposalApplier]. That is the whole point: ingest reuses the one
/// audited write path (repository → Drift → OpLog → AiTouch) instead of
/// inventing a parallel one, and the AI is never the final writer —
/// the user's tap is (§5.10.6). Only after the apply succeeds is the
/// draft marked `confirmed`; a failed apply leaves it `pending` so the
/// user can retry or edit.
library;

import 'package:decimal/decimal.dart';

import '../../../../core/ai/composition/proposal_applier.dart';
import '../../../../core/ai/composition/proposal_apply_state.dart';
import '../../../../core/ai/composition/proposal_plan.dart';
import '../../ai_tools/local_skills/txn_classifier.dart'
    show expenseCategorySlugForHint;
import '../domain/ingest_models.dart';

class IngestConfirmException implements Exception {
  const IngestConfirmException(
    this.code,
    this.message, {
    this.recovery = IngestRecovery.retryOperation,
    this.item,
  });

  final IngestConfirmError code;
  final String message;
  final IngestRecovery recovery;
  final ConfirmedIngestItem? item;

  @override
  String toString() => 'IngestConfirmException: $message';
}

enum IngestConfirmError {
  accountRequired,
  applyFailed,
  lifecycleWriteFailed,
  undoFailed,
  dismissFailed,
  restoreFailed,
}

enum IngestRecovery { retryOperation, finalizeApplied, restoreDraft }

abstract interface class IngestDraftLifecycleStore {
  Future<void> updateStatus(String draftId, DraftStatus status);

  Future<void> markNeedsFinalize(ConfirmedIngestItem item);
}

class ConfirmedIngestItem {
  const ConfirmedIngestItem({required this.draft, required this.applyState});

  final IngestDraft draft;
  final ProposalApplyState applyState;

  String get entityId => applyState.appliedEntityId!;
}

class IngestReviewItem {
  const IngestReviewItem({
    required this.draft,
    this.pendingFinalize,
    this.recoveryUnreadable = false,
  });

  final IngestDraft draft;
  final ConfirmedIngestItem? pendingFinalize;
  final bool recoveryUnreadable;

  bool get blocksApply => pendingFinalize != null || recoveryUnreadable;
}

class IngestBatchItemFailure<T> {
  const IngestBatchItemFailure({required this.item, required this.error});

  final T item;
  final IngestConfirmException error;
}

class IngestBatchConfirmResult {
  const IngestBatchConfirmResult({
    required this.confirmed,
    required this.failures,
  });

  final List<ConfirmedIngestItem> confirmed;
  final List<IngestBatchItemFailure<IngestDraft>> failures;

  int get completed => confirmed.length + failures.length;
}

class IngestBatchUndoResult {
  const IngestBatchUndoResult({required this.restored, required this.failures});

  final List<ConfirmedIngestItem> restored;
  final List<IngestBatchItemFailure<ConfirmedIngestItem>> failures;

  int get completed => restored.length + failures.length;
}

typedef IngestProgressCallback = void Function(int completed, int total);

class IngestConfirmService {
  IngestConfirmService({required this.applier, required this.store});

  final ProposalApplier applier;
  final IngestDraftLifecycleStore store;

  /// Apply [draft] as an expense paid from [fromAccountId]. Returns the
  /// applied state. Throws [IngestConfirmException] on failure
  /// (the draft stays pending).
  Future<ConfirmedIngestItem> confirm(
    IngestDraft draft, {
    required String fromAccountId,
  }) async {
    if (fromAccountId.isEmpty) {
      throw const IngestConfirmException(
        IngestConfirmError.accountRequired,
        'Select an account before recording this entry.',
      );
    }
    final plan = expensePlanFor(draft, fromAccountId: fromAccountId);

    final ProposalApplyState state;
    try {
      state = await applier.apply(plan);
    } on ProposalApplyException {
      throw const IngestConfirmException(
        IngestConfirmError.applyFailed,
        'Could not record this entry.',
      );
    } catch (_) {
      throw const IngestConfirmException(
        IngestConfirmError.applyFailed,
        'Could not record this entry.',
      );
    }
    if (state.status != ProposalApplyStatus.applied ||
        state.appliedEntityId == null) {
      throw const IngestConfirmException(
        IngestConfirmError.applyFailed,
        'Could not record this entry.',
      );
    }

    try {
      await store.updateStatus(draft.draftId, DraftStatus.confirmed);
    } catch (_) {
      final item = ConfirmedIngestItem(draft: draft, applyState: state);
      try {
        await applier.undo(state);
      } catch (_) {
        try {
          await store.markNeedsFinalize(item);
        } catch (_) {
          // Keep the typed continuation in memory even if persistence is
          // temporarily unavailable. The UI blocks re-apply for this page
          // lifetime and offers the same finalize-only recovery action.
        }
        throw IngestConfirmException(
          IngestConfirmError.lifecycleWriteFailed,
          'The entry was recorded but its review state was not finalized.',
          recovery: IngestRecovery.finalizeApplied,
          item: item,
        );
      }
      throw const IngestConfirmException(
        IngestConfirmError.lifecycleWriteFailed,
        'The entry could not be finalized.',
      );
    }
    return ConfirmedIngestItem(draft: draft, applyState: state);
  }

  /// Finalize only the draft lifecycle after an applied write could not be
  /// compensated. This continuation never re-applies the ledger write.
  Future<void> finalizeApplied(ConfirmedIngestItem item) async {
    try {
      await store.updateStatus(item.draft.draftId, DraftStatus.confirmed);
    } catch (_) {
      throw IngestConfirmException(
        IngestConfirmError.lifecycleWriteFailed,
        'The recorded entry still needs review-state reconciliation.',
        recovery: IngestRecovery.finalizeApplied,
        item: item,
      );
    }
  }

  /// Drop [draft] from the queue without writing anything.
  Future<void> dismiss(IngestDraft draft) async {
    try {
      await store.updateStatus(draft.draftId, DraftStatus.dismissed);
    } catch (_) {
      throw const IngestConfirmException(
        IngestConfirmError.dismissFailed,
        'Could not dismiss this entry.',
      );
    }
  }

  /// Put a dismissed draft back in the review queue.
  Future<void> restore(IngestDraft draft) async {
    try {
      await store.updateStatus(draft.draftId, DraftStatus.pending);
    } catch (_) {
      throw const IngestConfirmException(
        IngestConfirmError.restoreFailed,
        'Could not restore this entry.',
      );
    }
  }

  /// Reverse the original apply and return its draft to the review queue.
  Future<void> undoConfirmed(ConfirmedIngestItem item) async {
    try {
      await applier.undo(item.applyState);
    } catch (_) {
      throw const IngestConfirmException(
        IngestConfirmError.undoFailed,
        'Could not undo this entry.',
      );
    }
    await resumeUndo(item);
  }

  /// Resume an undo whose ledger compensation already succeeded. Retrying
  /// this continuation only restores the draft; it never invokes undo twice.
  Future<void> resumeUndo(ConfirmedIngestItem item) async {
    try {
      await store.updateStatus(item.draft.draftId, DraftStatus.pending);
    } catch (_) {
      throw IngestConfirmException(
        IngestConfirmError.restoreFailed,
        'The entry was undone but could not be restored to review.',
        recovery: IngestRecovery.restoreDraft,
        item: item,
      );
    }
  }

  /// Confirm every still-pending, non-duplicate draft. Duplicates are
  /// left for the user to decide on explicitly. Every eligible draft is
  /// attempted, so one malformed item never blocks the rest of the batch.
  Future<IngestBatchConfirmResult> confirmAllFresh(
    List<IngestDraft> drafts, {
    required String fromAccountId,
    IngestProgressCallback? onProgress,
  }) async {
    if (fromAccountId.isEmpty) {
      throw const IngestConfirmException(
        IngestConfirmError.accountRequired,
        'Select an account before recording these entries.',
      );
    }
    final eligible = drafts
        .where(
          (draft) =>
              draft.status == DraftStatus.pending &&
              draft.verdict == DedupVerdict.newTxn,
        )
        .toList(growable: false);
    final confirmed = <ConfirmedIngestItem>[];
    final failures = <IngestBatchItemFailure<IngestDraft>>[];
    for (var index = 0; index < eligible.length; index++) {
      final draft = eligible[index];
      try {
        confirmed.add(await confirm(draft, fromAccountId: fromAccountId));
      } on IngestConfirmException catch (error) {
        failures.add(IngestBatchItemFailure(item: draft, error: error));
      }
      onProgress?.call(index + 1, eligible.length);
    }
    return IngestBatchConfirmResult(confirmed: confirmed, failures: failures);
  }

  /// Undo all successfully confirmed items, continuing after item failures.
  Future<IngestBatchUndoResult> undoAllConfirmed(
    List<ConfirmedIngestItem> items, {
    IngestProgressCallback? onProgress,
  }) async {
    final restored = <ConfirmedIngestItem>[];
    final failures = <IngestBatchItemFailure<ConfirmedIngestItem>>[];
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      try {
        await undoConfirmed(item);
        restored.add(item);
      } on IngestConfirmException catch (error) {
        failures.add(IngestBatchItemFailure(item: item, error: error));
      }
      onProgress?.call(index + 1, items.length);
    }
    return IngestBatchUndoResult(restored: restored, failures: failures);
  }

  /// Retry only the unfinished continuation for each failed batch undo.
  /// Items whose ledger undo already succeeded resume at draft restoration;
  /// all other failures retry the original undo safely.
  Future<IngestBatchUndoResult> retryUndoFailures(
    List<IngestBatchItemFailure<ConfirmedIngestItem>> failedItems, {
    IngestProgressCallback? onProgress,
  }) async {
    final restored = <ConfirmedIngestItem>[];
    final failures = <IngestBatchItemFailure<ConfirmedIngestItem>>[];
    for (var index = 0; index < failedItems.length; index++) {
      final failed = failedItems[index];
      try {
        if (failed.error.recovery == IngestRecovery.restoreDraft) {
          await resumeUndo(failed.item);
        } else {
          await undoConfirmed(failed.item);
        }
        restored.add(failed.item);
      } on IngestConfirmException catch (error) {
        failures.add(IngestBatchItemFailure(item: failed.item, error: error));
      }
      onProgress?.call(index + 1, failedItems.length);
    }
    return IngestBatchUndoResult(restored: restored, failures: failures);
  }

  /// Pure mapping draft → `propose_expense`-shaped plan. Extracted so
  /// the wire contract with [ProposalApplier] can be unit-tested without
  /// spinning up every repository.
  static ReadyProposalPlan expensePlanFor(
    IngestDraft draft, {
    required String fromAccountId,
  }) {
    final amount = _minorToDecimalString(draft.parsed.amountMinor.abs());
    final category = expenseCategorySlugForHint(draft.parsed.categoryHint);
    return ReadyProposalPlan(
      proposalId: draft.draftId,
      kind: 'expense',
      summaryZh:
          '记录支出 ${_shortDesc(draft.parsed.description)} '
          '${draft.parsed.currency} $amount',
      payload: <String, Object?>{
        'account_id': fromAccountId,
        'amount': amount,
        'currency': draft.parsed.currency,
        'date': draft.parsed.occurredAt.toUtc().toIso8601String(),
        'note': draft.parsed.description,
        'category': category,
      },
    );
  }

  static String _minorToDecimalString(int absMinor) {
    final whole = absMinor ~/ 100;
    final frac = (absMinor % 100).toString().padLeft(2, '0');
    // Round-trips through Decimal exactly; ProposalApplier re-parses it.
    return Decimal.parse('$whole.$frac').toString();
  }

  static String _shortDesc(String s) =>
      s.length <= 24 ? s : '${s.substring(0, 23)}…';
}
