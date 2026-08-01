/// §5.10.10 / S5a step ⑦ — confirmation.
///
/// A confirmed draft is turned into an expense or income
/// [ReadyProposalPlan] and pushed through the **existing**
/// [ProposalApplier]. That is the whole point: ingest reuses the one
/// audited write path (repository → Drift → OpLog → AiTouch) instead of
/// inventing a parallel one, and the AI is never the final writer —
/// the user's tap is (§5.10.6). Only after the apply succeeds is the
/// draft marked `confirmed`. Pre-invocation failures release the draft;
/// post-invocation ambiguity is fail-closed for manual recovery.
library;

import 'package:uuid/uuid.dart';

import '../../../../core/ai/composition/proposal_applier.dart';
import '../../../../core/ai/composition/proposal_apply_state.dart';
import '../../../../core/ai/composition/proposal_plan.dart';
import '../../ai_tools/local_skills/txn_classifier.dart'
    show expenseCategorySlugForHint;
import '../domain/ingest_models.dart';
import '../domain/minor_unit_amount.dart';

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
  lifecycleConflict,
  manualRecoveryRequired,
}

enum IngestRecovery { retryOperation, finalizeApplied, restoreDraft }

abstract interface class IngestDraftLifecycleStore {
  Future<IngestLifecycleMutationResult> transition(
    IngestLifecycleTransition transition,
  );
}

/// Optional capability for stores that can group a bounded confirmation
/// chunk into one durable transaction and coalesce their change notification.
///
/// The confirmation service keeps supporting lightweight/fake lifecycle
/// stores; production [IngestDraftStore] opts into this capability.
abstract interface class IngestDraftBatchLifecycleStore
    implements IngestDraftLifecycleStore {
  Future<T> runBatch<T>(Future<T> Function() action);
}

enum IngestLifecycleMutationOutcome { applied, conflict, notFound }

class IngestLifecycleMutationResult {
  const IngestLifecycleMutationResult(this.outcome, {this.revision});

  final IngestLifecycleMutationOutcome outcome;
  final int? revision;
}

class IngestLifecycleTransition {
  const IngestLifecycleTransition({
    required this.ownerUserId,
    required this.draftId,
    required this.expectedStatus,
    required this.expectedRevision,
    required this.nextStatus,
    this.expectedRecoveryKind,
    this.expectedOperationToken,
    this.expectedInvocationStarted = false,
    this.nextRecoveryKind,
    this.nextRecoveryApplyState,
    this.nextOperationToken,
    this.nextInvocationStarted = false,
  });

  final String ownerUserId;
  final String draftId;
  final DraftStatus expectedStatus;
  final int expectedRevision;
  final String? expectedRecoveryKind;
  final String? expectedOperationToken;
  final bool expectedInvocationStarted;
  final DraftStatus nextStatus;
  final String? nextRecoveryKind;
  final ProposalApplyState? nextRecoveryApplyState;
  final String? nextOperationToken;
  final bool nextInvocationStarted;
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

  bool get isOrdinaryPending =>
      draft.status == DraftStatus.pending &&
      pendingFinalize == null &&
      !recoveryUnreadable;

  bool get canBatchConfirm =>
      isOrdinaryPending &&
      draft.verdict == DedupVerdict.newTxn &&
      draft.parsed.kind != IngestTransactionKind.transfer &&
      draft.parsed.kind != IngestTransactionKind.trade;

  bool get canBatchDismiss => isOrdinaryPending;
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

class IngestBatchMutationResult<T> {
  const IngestBatchMutationResult({
    required this.succeeded,
    required this.failures,
  });

  final List<T> succeeded;
  final List<IngestBatchItemFailure<T>> failures;
}

typedef IngestProgressCallback = void Function(int completed, int total);

class IngestConfirmService {
  IngestConfirmService({
    required this.applier,
    required this.store,
    Uuid uuid = const Uuid(),
  }) : _uuid = uuid;

  final ProposalApplier applier;
  final IngestDraftLifecycleStore store;
  final Uuid _uuid;

  /// Keeps transactions short enough for mobile SQLite while reducing a
  /// 100-row confirmation from 100 outer commits to four.
  static const int confirmationChunkSize = 25;

  /// Apply [draft] against the selected statement account. For expenses it
  /// is the paying account; for income it is the destination account.
  /// Failures before invocation release the reservation; failures after
  /// invocation starts require explicit manual recovery.
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
    final plan = planFor(draft, accountId: fromAccountId);
    final token = _uuid.v4();
    late int revision;
    try {
      revision = await _requireApplied(
        IngestLifecycleTransition(
          ownerUserId: draft.ownerUserId,
          draftId: draft.draftId,
          expectedStatus: DraftStatus.pending,
          expectedRevision: draft.revision,
          nextStatus: DraftStatus.confirming,
          nextOperationToken: token,
        ),
      );
    } on IngestConfirmException {
      rethrow;
    } catch (_) {
      throw const IngestConfirmException(
        IngestConfirmError.lifecycleWriteFailed,
        'Could not reserve this review item for recording.',
      );
    }

    try {
      revision = await _requireApplied(
        IngestLifecycleTransition(
          ownerUserId: draft.ownerUserId,
          draftId: draft.draftId,
          expectedStatus: DraftStatus.confirming,
          expectedRevision: revision,
          expectedOperationToken: token,
          nextStatus: DraftStatus.confirming,
          nextOperationToken: token,
          nextInvocationStarted: true,
        ),
      );
    } on IngestConfirmException {
      await _releaseBeforeInvocation(draft, token, revision);
      rethrow;
    } catch (_) {
      await _releaseBeforeInvocation(draft, token, revision);
      throw const IngestConfirmException(
        IngestConfirmError.lifecycleWriteFailed,
        'Could not start recording this review item.',
      );
    }

    final ProposalApplyState state;
    try {
      state = await applier.apply(plan);
    } on ProposalApplyException {
      await _markInvocationAmbiguous(draft, token, revision);
      throw const IngestConfirmException(
        IngestConfirmError.manualRecoveryRequired,
        'Recording may have started. Review it manually before retrying.',
      );
    } catch (_) {
      await _markInvocationAmbiguous(draft, token, revision);
      throw const IngestConfirmException(
        IngestConfirmError.manualRecoveryRequired,
        'Recording may have started. Review it manually before retrying.',
      );
    }
    if (state.status != ProposalApplyStatus.applied ||
        state.appliedEntityId == null) {
      await _markInvocationAmbiguous(draft, token, revision);
      throw const IngestConfirmException(
        IngestConfirmError.manualRecoveryRequired,
        'Recording returned an uncertain result. Review it manually.',
      );
    }

    var item = ConfirmedIngestItem(draft: draft, applyState: state);
    try {
      revision = await _requireApplied(
        IngestLifecycleTransition(
          ownerUserId: draft.ownerUserId,
          draftId: draft.draftId,
          expectedStatus: DraftStatus.confirming,
          expectedRevision: revision,
          expectedOperationToken: token,
          expectedInvocationStarted: true,
          nextStatus: DraftStatus.pending,
          nextRecoveryKind: 'finalize_applied',
          nextRecoveryApplyState: state,
        ),
      );
      item = ConfirmedIngestItem(
        draft: draft.copyWith(revision: revision),
        applyState: state,
      );
      revision = await _requireApplied(
        IngestLifecycleTransition(
          ownerUserId: draft.ownerUserId,
          draftId: draft.draftId,
          expectedStatus: DraftStatus.pending,
          expectedRevision: revision,
          expectedRecoveryKind: 'finalize_applied',
          nextStatus: DraftStatus.confirmed,
        ),
      );
      item = ConfirmedIngestItem(
        draft: draft.copyWith(
          status: DraftStatus.confirmed,
          revision: revision,
        ),
        applyState: state,
      );
    } catch (_) {
      throw IngestConfirmException(
        IngestConfirmError.lifecycleWriteFailed,
        'The entry was recorded but its review state was not finalized.',
        recovery: IngestRecovery.finalizeApplied,
        item: item,
      );
    }
    return item;
  }

  /// Finalize only the draft lifecycle after an applied write could not be
  /// compensated. This continuation never re-applies the ledger write.
  Future<void> finalizeApplied(ConfirmedIngestItem item) async {
    try {
      await _requireApplied(
        IngestLifecycleTransition(
          ownerUserId: item.draft.ownerUserId,
          draftId: item.draft.draftId,
          expectedStatus: DraftStatus.pending,
          expectedRevision: item.draft.revision,
          expectedRecoveryKind: 'finalize_applied',
          nextStatus: DraftStatus.confirmed,
        ),
      );
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
  Future<IngestDraft> dismiss(IngestDraft draft) async {
    try {
      final revision = await _requireApplied(
        IngestLifecycleTransition(
          ownerUserId: draft.ownerUserId,
          draftId: draft.draftId,
          expectedStatus: DraftStatus.pending,
          expectedRevision: draft.revision,
          nextStatus: DraftStatus.dismissed,
        ),
      );
      return draft.copyWith(status: DraftStatus.dismissed, revision: revision);
    } catch (_) {
      throw const IngestConfirmException(
        IngestConfirmError.dismissFailed,
        'Could not dismiss this entry.',
      );
    }
  }

  /// Put a dismissed draft back in the review queue.
  Future<IngestDraft> restore(IngestDraft draft) async {
    try {
      final revision = await _requireApplied(
        IngestLifecycleTransition(
          ownerUserId: draft.ownerUserId,
          draftId: draft.draftId,
          expectedStatus: DraftStatus.dismissed,
          expectedRevision: draft.revision,
          nextStatus: DraftStatus.pending,
        ),
      );
      return draft.copyWith(status: DraftStatus.pending, revision: revision);
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
      await _requireApplied(
        IngestLifecycleTransition(
          ownerUserId: item.draft.ownerUserId,
          draftId: item.draft.draftId,
          expectedStatus: DraftStatus.confirmed,
          expectedRevision: item.draft.revision,
          nextStatus: DraftStatus.pending,
        ),
      );
    } catch (_) {
      throw IngestConfirmException(
        IngestConfirmError.restoreFailed,
        'The entry was undone but could not be restored to review.',
        recovery: IngestRecovery.restoreDraft,
        item: item,
      );
    }
  }

  Future<int> _requireApplied(IngestLifecycleTransition transition) async {
    final result = await store.transition(transition);
    if (result.outcome == IngestLifecycleMutationOutcome.applied) {
      return result.revision!;
    }
    throw IngestConfirmException(
      IngestConfirmError.lifecycleConflict,
      result.outcome == IngestLifecycleMutationOutcome.notFound
          ? 'This review item is no longer available.'
          : 'This review item changed. Refresh before continuing.',
    );
  }

  Future<void> _releaseBeforeInvocation(
    IngestDraft draft,
    String token,
    int revision,
  ) async {
    try {
      await store.transition(
        IngestLifecycleTransition(
          ownerUserId: draft.ownerUserId,
          draftId: draft.draftId,
          expectedStatus: DraftStatus.confirming,
          expectedRevision: revision,
          expectedOperationToken: token,
          nextStatus: DraftStatus.pending,
        ),
      );
    } catch (_) {
      // A failed release leaves the draft in the fail-closed confirming state.
    }
  }

  Future<void> _markInvocationAmbiguous(
    IngestDraft draft,
    String token,
    int revision,
  ) async {
    try {
      await store.transition(
        IngestLifecycleTransition(
          ownerUserId: draft.ownerUserId,
          draftId: draft.draftId,
          expectedStatus: DraftStatus.confirming,
          expectedRevision: revision,
          expectedOperationToken: token,
          expectedInvocationStarted: true,
          nextStatus: DraftStatus.pending,
          nextRecoveryKind: 'confirm_ambiguous',
        ),
      );
    } catch (_) {
      // A failed marker write keeps the confirming reservation fail-closed.
    }
  }

  /// Confirm every still-pending, non-duplicate draft. Duplicates are
  /// left for the user to decide on explicitly. Every eligible draft is
  /// attempted, so one malformed item never blocks the rest of the batch.
  Future<IngestBatchConfirmResult> confirmAllFresh(
    List<IngestReviewItem> items, {
    required String fromAccountId,
    IngestProgressCallback? onProgress,
  }) async {
    if (fromAccountId.isEmpty) {
      throw const IngestConfirmException(
        IngestConfirmError.accountRequired,
        'Select an account before recording these entries.',
      );
    }
    final eligible = items
        .where((item) => item.canBatchConfirm)
        .map((item) => item.draft)
        .toList(growable: false);
    final confirmed = <ConfirmedIngestItem>[];
    final failures = <IngestBatchItemFailure<IngestDraft>>[];
    for (
      var chunkStart = 0;
      chunkStart < eligible.length;
      chunkStart += confirmationChunkSize
    ) {
      final chunkEnd = chunkStart + confirmationChunkSize < eligible.length
          ? chunkStart + confirmationChunkSize
          : eligible.length;
      await _runBatch(() async {
        for (var index = chunkStart; index < chunkEnd; index++) {
          final draft = eligible[index];
          try {
            confirmed.add(await confirm(draft, fromAccountId: fromAccountId));
          } on IngestConfirmException catch (error) {
            failures.add(IngestBatchItemFailure(item: draft, error: error));
          }
          onProgress?.call(index + 1, eligible.length);
        }
      });
    }
    return IngestBatchConfirmResult(confirmed: confirmed, failures: failures);
  }

  Future<T> _runBatch<T>(Future<T> Function() action) {
    final lifecycleStore = store;
    if (lifecycleStore is IngestDraftBatchLifecycleStore) {
      return lifecycleStore.runBatch(action);
    }
    return action();
  }

  Future<IngestBatchMutationResult<IngestReviewItem>> dismissSelected(
    List<IngestReviewItem> items, {
    IngestProgressCallback? onProgress,
  }) async {
    final eligible = items.where((item) => item.canBatchDismiss).toList();
    final succeeded = <IngestReviewItem>[];
    final failures = <IngestBatchItemFailure<IngestReviewItem>>[];
    for (var index = 0; index < eligible.length; index++) {
      final item = eligible[index];
      try {
        final dismissed = await dismiss(item.draft);
        succeeded.add(IngestReviewItem(draft: dismissed));
      } on IngestConfirmException catch (error) {
        failures.add(IngestBatchItemFailure(item: item, error: error));
      }
      onProgress?.call(index + 1, eligible.length);
    }
    return IngestBatchMutationResult(succeeded: succeeded, failures: failures);
  }

  Future<IngestBatchMutationResult<IngestDraft>> restoreSelected(
    List<IngestDraft> drafts, {
    IngestProgressCallback? onProgress,
  }) async {
    final eligible = drafts
        .where((draft) => draft.status == DraftStatus.dismissed)
        .toList();
    final succeeded = <IngestDraft>[];
    final failures = <IngestBatchItemFailure<IngestDraft>>[];
    for (var index = 0; index < eligible.length; index++) {
      final draft = eligible[index];
      try {
        succeeded.add(await restore(draft));
      } on IngestConfirmException catch (error) {
        failures.add(IngestBatchItemFailure(item: draft, error: error));
      }
      onProgress?.call(index + 1, eligible.length);
    }
    return IngestBatchMutationResult(succeeded: succeeded, failures: failures);
  }

  Future<IngestBatchMutationResult<IngestReviewItem>> finalizeSelected(
    List<IngestReviewItem> items, {
    IngestProgressCallback? onProgress,
  }) async {
    final eligible = items
        .where((item) => item.pendingFinalize != null)
        .toList();
    final succeeded = <IngestReviewItem>[];
    final failures = <IngestBatchItemFailure<IngestReviewItem>>[];
    for (var index = 0; index < eligible.length; index++) {
      final item = eligible[index];
      try {
        await finalizeApplied(item.pendingFinalize!);
        succeeded.add(item);
      } on IngestConfirmException catch (error) {
        failures.add(IngestBatchItemFailure(item: item, error: error));
      }
      onProgress?.call(index + 1, eligible.length);
    }
    return IngestBatchMutationResult(succeeded: succeeded, failures: failures);
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
    final amount = formatAbsoluteMinorUnitAmount(draft.parsed.amountMinor);
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

  static ReadyProposalPlan incomePlanFor(
    IngestDraft draft, {
    required String toAccountId,
  }) {
    final amount = formatAbsoluteMinorUnitAmount(draft.parsed.amountMinor);
    final category = switch (draft.parsed.categoryHint) {
      'salary' || 'dividend' || 'interest' => draft.parsed.categoryHint!,
      _ => 'other',
    };
    return ReadyProposalPlan(
      proposalId: draft.draftId,
      kind: 'income',
      summaryZh:
          '记录收入 ${_shortDesc(draft.parsed.description)} '
          '${draft.parsed.currency} $amount',
      payload: <String, Object?>{
        'account_id': toAccountId,
        'amount': amount,
        'currency': draft.parsed.currency,
        'date': draft.parsed.occurredAt.toUtc().toIso8601String(),
        'note': draft.parsed.description,
        'category': category,
      },
    );
  }

  static ReadyProposalPlan planFor(
    IngestDraft draft, {
    required String accountId,
  }) => switch (draft.parsed.kind) {
    IngestTransactionKind.expense => expensePlanFor(
      draft,
      fromAccountId: accountId,
    ),
    IngestTransactionKind.income => incomePlanFor(
      draft,
      toAccountId: accountId,
    ),
    IngestTransactionKind.transfer => throw StateError(
      'Transfer drafts must use the atomic transfer form.',
    ),
    IngestTransactionKind.trade => throw StateError(
      'Trade drafts must use the typed trade form.',
    ),
  };

  static String _shortDesc(String s) =>
      s.length <= 24 ? s : '${s.substring(0, 23)}…';
}
