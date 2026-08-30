/// Durable confirmation protocol for ingest rows whose final write is owned by
/// a typed form (currently transfer and trade).
///
/// The form's repository mutation and the ingest lifecycle transitions share
/// one outer Drift transaction. The persisted reservation fields make the
/// operation explicit and CAS-protected, while SQLite atomicity guarantees a
/// process death cannot leave only one side committed.
library;

import 'package:uuid/uuid.dart';

import '../../../../core/ai/composition/proposal_apply_state.dart';
import '../domain/ingest_models.dart';
import 'ingest_confirm_service.dart';

enum IngestExternalKind {
  transfer('transfer'),
  trade('trade');

  const IngestExternalKind(this.wire);

  final String wire;
}

/// Typed receipt plus the confirmed ingest revision needed by atomic Undo.
final class IngestExternalCommit<T> {
  const IngestExternalCommit({
    required this.item,
    required this.receipt,
    required this.kind,
    required this.operationToken,
  });

  final ConfirmedIngestItem item;
  final T receipt;
  final IngestExternalKind kind;
  final String operationToken;
}

class IngestExternalConfirmationCoordinator {
  IngestExternalConfirmationCoordinator({
    required IngestDraftBatchLifecycleStore store,
    Uuid uuid = const Uuid(),
    DateTime Function()? clock,
  }) : _store = store,
       _uuid = uuid,
       _clock = clock ?? DateTime.now;

  final IngestDraftBatchLifecycleStore _store;
  final Uuid _uuid;
  final DateTime Function() _clock;

  /// Confirms [draft] and commits its typed domain mutation atomically.
  ///
  /// [apply] receives the durable operation token. Trade uses it as its
  /// transaction id and transfer uses it as its journal-entry id, making the
  /// persisted reservation an idempotency identity as well as a CAS guard.
  Future<IngestExternalCommit<T>> confirm<T>(
    IngestDraft draft, {
    required IngestExternalKind kind,
    required Future<T> Function(String operationToken) apply,
    required String Function(T receipt) entityId,
    String? operationToken,
  }) {
    final token = operationToken ?? _uuid.v4();
    if (token.trim().isEmpty) {
      throw ArgumentError.value(operationToken, 'operationToken');
    }
    return _store.runBatch(() async {
      var revision = await _requireApplied(
        IngestLifecycleTransition(
          ownerUserId: draft.ownerUserId,
          draftId: draft.draftId,
          expectedStatus: DraftStatus.pending,
          expectedRevision: draft.revision,
          nextStatus: DraftStatus.confirming,
          nextOperationToken: token,
        ),
      );
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

      final receipt = await apply(token);
      final appliedEntityId = entityId(receipt).trim();
      if (appliedEntityId.isEmpty) {
        throw StateError('External ingest commit returned an empty entity id.');
      }
      final applyState = ProposalApplyState(
        status: ProposalApplyStatus.applied,
        appliedEntityId: appliedEntityId,
        appliedTable: 'journal_entries',
        appliedAt: _clock().toUtc(),
        undoData: <String, Object?>{
          'ingest_external_kind': kind.wire,
          'operation_token': token,
        },
        shortLabel: draft.parsed.description,
      );

      // Keep the existing durable continuation shape even though the outer
      // transaction normally makes it unobservable. This preserves one
      // lifecycle protocol for diagnostics and future non-SQLite adapters.
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
          nextRecoveryApplyState: applyState,
        ),
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

      return IngestExternalCommit<T>(
        item: ConfirmedIngestItem(
          draft: draft.copyWith(
            status: DraftStatus.confirmed,
            revision: revision,
          ),
          applyState: applyState,
        ),
        receipt: receipt,
        kind: kind,
        operationToken: token,
      );
    });
  }

  /// Reverses the typed mutation and returns the draft to review atomically.
  Future<void> undo<T>(
    IngestExternalCommit<T> commit, {
    required Future<void> Function(T receipt) undoMutation,
  }) {
    final draft = commit.item.draft;
    final undoToken = _uuid.v4();
    return _store.runBatch(() async {
      var revision = await _requireApplied(
        IngestLifecycleTransition(
          ownerUserId: draft.ownerUserId,
          draftId: draft.draftId,
          expectedStatus: DraftStatus.confirmed,
          expectedRevision: draft.revision,
          nextStatus: DraftStatus.confirming,
          nextOperationToken: undoToken,
        ),
      );
      revision = await _requireApplied(
        IngestLifecycleTransition(
          ownerUserId: draft.ownerUserId,
          draftId: draft.draftId,
          expectedStatus: DraftStatus.confirming,
          expectedRevision: revision,
          expectedOperationToken: undoToken,
          nextStatus: DraftStatus.confirming,
          nextOperationToken: undoToken,
          nextInvocationStarted: true,
        ),
      );
      await undoMutation(commit.receipt);
      await _requireApplied(
        IngestLifecycleTransition(
          ownerUserId: draft.ownerUserId,
          draftId: draft.draftId,
          expectedStatus: DraftStatus.confirming,
          expectedRevision: revision,
          expectedOperationToken: undoToken,
          expectedInvocationStarted: true,
          nextStatus: DraftStatus.pending,
        ),
      );
    });
  }

  Future<int> _requireApplied(IngestLifecycleTransition transition) async {
    final result = await _store.transition(transition);
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
}
