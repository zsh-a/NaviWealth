/// Durable orchestration for a [BatchProposalPlan].
///
/// Progress and any rollback debt are persisted in
/// [ProposalApplyState.undoData] after every child. This keeps a partial
/// failure retry-safe: the UI cannot re-apply the batch while an earlier
/// child still needs compensation.
library;

import '../../../core/ai/composition/proposal_applier.dart';
import '../../../core/ai/composition/proposal_apply_state.dart';
import '../../../core/ai/composition/proposal_plan.dart';

typedef BatchProposalStateWriter = Future<void> Function(
  ProposalApplyState state,
);
typedef BatchProposalFinalizer = Future<ProposalApplyState> Function(
  List<ProposalApplyState> children,
  DateTime appliedAt,
);

final class BatchProposalProgress {
  const BatchProposalProgress({
    required this.completed,
    required this.total,
    this.failedIndex,
    this.rollbackComplete = false,
    this.recovering = false,
    this.remainingChildren = const <ProposalApplyState>[],
  });

  factory BatchProposalProgress.fromState(
    ProposalApplyState state, {
    required int total,
  }) {
    final data = state.undoData;
    if (data == null || data['batch_progress'] != true) {
      return BatchProposalProgress(completed: 0, total: total);
    }
    final rawChildren = data['children'];
    final children = <ProposalApplyState>[
      if (rawChildren is List)
        for (final raw in rawChildren)
          if (raw is Map)
            ProposalApplyState.fromJson(
              raw.map((key, value) => MapEntry(key.toString(), value)),
            ),
    ];
    return BatchProposalProgress(
      completed: (data['completed'] as num?)?.toInt() ?? 0,
      total: (data['total'] as num?)?.toInt() ?? total,
      failedIndex: (data['failed_index'] as num?)?.toInt(),
      rollbackComplete: data['rollback_complete'] == true,
      recovering: data['recovering'] == true,
      remainingChildren: children,
    );
  }

  final int completed;
  final int total;
  final int? failedIndex;
  final bool rollbackComplete;
  final bool recovering;
  final List<ProposalApplyState> remainingChildren;

  bool get requiresRecovery => remainingChildren.isNotEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    'batch_progress': true,
    'completed': completed,
    'total': total,
    if (failedIndex != null) 'failed_index': failedIndex,
    'rollback_complete': rollbackComplete,
    'recovering': recovering,
    'children': [for (final child in remainingChildren) child.toJson()],
  };
}

final class BatchProposalApplyCoordinator {
  const BatchProposalApplyCoordinator({
    required this.applier,
    required this.persist,
  });

  final ProposalApplier applier;
  final BatchProposalStateWriter persist;

  Future<ProposalApplyState> execute(
    BatchProposalPlan plan, {
    required BatchProposalFinalizer finalize,
  }) async {
    final applied = <ProposalApplyState>[];
    try {
      await persist(_applyingState(plan.children.length, applied));
      for (final child in plan.children) {
        final childState = await applier.apply(child);
        if (childState.status != ProposalApplyStatus.applied) {
          throw ProposalApplyException(
            childState.errorMessage ?? 'batch child did not apply',
          );
        }
        applied.add(childState);
        await persist(_applyingState(plan.children.length, applied));
      }
      final finalState = await finalize(
        List<ProposalApplyState>.unmodifiable(applied),
        DateTime.now().toUtc(),
      );
      await persist(finalState);
      return finalState;
    } on Object catch (error) {
      final remaining = await _rollback(applied);
      final state = _failureState(
        error: error,
        total: plan.children.length,
        completed: applied.length,
        remaining: remaining,
      );
      await persist(state);
      return state;
    }
  }

  Future<ProposalApplyState> recover(
    ProposalApplyState state, {
    required int total,
  }) async {
    final progress = BatchProposalProgress.fromState(state, total: total);
    if (state.status != ProposalApplyStatus.errored ||
        !progress.requiresRecovery) {
      return state;
    }
    await persist(
      ProposalApplyState(
        status: ProposalApplyStatus.applying,
        errorMessage: state.errorMessage,
        undoData: BatchProposalProgress(
          completed: progress.completed,
          total: progress.total,
          failedIndex: progress.failedIndex,
          recovering: true,
          remainingChildren: progress.remainingChildren,
        ).toJson(),
      ),
    );
    final remaining = await _rollback(progress.remainingChildren);
    final recovered = ProposalApplyState(
      status: ProposalApplyStatus.errored,
      errorMessage: state.errorMessage,
      undoData: BatchProposalProgress(
        completed: progress.completed,
        total: progress.total,
        failedIndex: progress.failedIndex,
        rollbackComplete: remaining.isEmpty,
        remainingChildren: remaining,
      ).toJson(),
    );
    await persist(recovered);
    return recovered;
  }

  ProposalApplyState _applyingState(
    int total,
    List<ProposalApplyState> applied,
  ) {
    return ProposalApplyState(
      status: ProposalApplyStatus.applying,
      undoData: BatchProposalProgress(
        completed: applied.length,
        total: total,
        remainingChildren: applied,
      ).toJson(),
    );
  }

  ProposalApplyState _failureState({
    required Object error,
    required int total,
    required int completed,
    required List<ProposalApplyState> remaining,
  }) {
    return ProposalApplyState(
      status: ProposalApplyStatus.errored,
      errorMessage: error is ProposalApplyException
          ? error.message
          : error.toString(),
      undoData: BatchProposalProgress(
        completed: completed,
        total: total,
        failedIndex: completed < total ? completed : null,
        rollbackComplete: remaining.isEmpty,
        remainingChildren: remaining,
      ).toJson(),
    );
  }

  Future<List<ProposalApplyState>> _rollback(
    List<ProposalApplyState> children,
  ) async {
    final failed = <ProposalApplyState>[];
    for (final child in children.reversed) {
      try {
        await applier.undo(child);
      } on Object {
        failed.add(child);
      }
    }
    return failed.reversed.toList(growable: false);
  }
}
