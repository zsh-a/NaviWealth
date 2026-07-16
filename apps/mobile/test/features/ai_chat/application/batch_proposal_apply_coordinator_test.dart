import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/composition/proposal_applier.dart';
import 'package:naviwealth/core/ai/composition/proposal_apply_state.dart';
import 'package:naviwealth/core/ai/composition/proposal_plan.dart';
import 'package:naviwealth/features/ai_chat/application/batch_proposal_apply_coordinator.dart';

ReadyProposalPlan _child(int index) => ReadyProposalPlan(
  proposalId: 'child-$index',
  kind: 'expense',
  summaryZh: 'Child $index',
  payload: <String, Object?>{'index': index},
);

BatchProposalPlan _plan() => BatchProposalPlan(
  proposalId: 'batch-1',
  kind: 'batch',
  summaryZh: 'Batch',
  children: [_child(0), _child(1), _child(2)],
);

ProposalApplyState _applied(int index) => ProposalApplyState(
  status: ProposalApplyStatus.applied,
  appliedEntityId: 'entity-$index',
  appliedTable: 'journal_entries',
  appliedAt: DateTime.utc(2026, 1, 1),
);

class _FakeApplier implements ProposalApplier {
  final List<int> appliedIndexes = <int>[];
  final List<String> undoneIds = <String>[];
  int? failApplyAt;
  bool failUndo = false;

  @override
  Future<ProposalApplyState> apply(ReadyProposalPlan plan) async {
    final index = plan.payload['index']! as int;
    if (index == failApplyAt) throw ProposalApplyException('child failed');
    appliedIndexes.add(index);
    return _applied(index);
  }

  @override
  Future<void> undo(ProposalApplyState state) async {
    if (failUndo) throw ProposalApplyException('undo failed');
    undoneIds.add(state.appliedEntityId!);
  }
}

void main() {
  test('persists child-level progress before final applied state', () async {
    final applier = _FakeApplier();
    final persisted = <ProposalApplyState>[];
    final coordinator = BatchProposalApplyCoordinator(
      applier: applier,
      persist: (state) async => persisted.add(state),
    );

    final result = await coordinator.execute(
      _plan(),
      finalize: (children, at) async => ProposalApplyState(
        status: ProposalApplyStatus.applied,
        appliedTable: 'batch',
        appliedAt: at,
      ),
    );

    expect(result.status, ProposalApplyStatus.applied);
    expect(applier.appliedIndexes, [0, 1, 2]);
    expect(
      persisted
          .take(4)
          .map(
            (state) =>
                BatchProposalProgress.fromState(state, total: 3).completed,
          ),
      [0, 1, 2, 3],
    );
    expect(persisted.last.status, ProposalApplyStatus.applied);
  });

  test(
    'child failure rolls back prior children and leaves a safe retry',
    () async {
      final applier = _FakeApplier()..failApplyAt = 1;
      final persisted = <ProposalApplyState>[];
      final coordinator = BatchProposalApplyCoordinator(
        applier: applier,
        persist: (state) async => persisted.add(state),
      );

      final result = await coordinator.execute(
        _plan(),
        finalize: (_, _) async => throw StateError('not reached'),
      );
      final progress = BatchProposalProgress.fromState(result, total: 3);

      expect(result.status, ProposalApplyStatus.errored);
      expect(progress.completed, 1);
      expect(progress.failedIndex, 1);
      expect(progress.rollbackComplete, isTrue);
      expect(progress.requiresRecovery, isFalse);
      expect(applier.undoneIds, ['entity-0']);
    },
  );

  test('rollback debt blocks retry and explicit recovery clears it', () async {
    final applier = _FakeApplier()
      ..failApplyAt = 1
      ..failUndo = true;
    final persisted = <ProposalApplyState>[];
    final coordinator = BatchProposalApplyCoordinator(
      applier: applier,
      persist: (state) async => persisted.add(state),
    );

    final failed = await coordinator.execute(
      _plan(),
      finalize: (_, _) async => throw StateError('not reached'),
    );
    expect(
      BatchProposalProgress.fromState(failed, total: 3).requiresRecovery,
      isTrue,
    );

    applier.failUndo = false;
    final recovered = await coordinator.recover(failed, total: 3);
    final progress = BatchProposalProgress.fromState(recovered, total: 3);
    expect(progress.requiresRecovery, isFalse);
    expect(progress.rollbackComplete, isTrue);
    expect(applier.undoneIds, ['entity-0']);
    expect(
      BatchProposalProgress.fromState(
        persisted[persisted.length - 2],
        total: 3,
      ).recovering,
      isTrue,
    );
  });

  test('recovery is a no-op while a batch is still applying', () async {
    final child = _applied(0);
    final applying = ProposalApplyState(
      status: ProposalApplyStatus.applying,
      undoData: BatchProposalProgress(
        completed: 1,
        total: 3,
        remainingChildren: <ProposalApplyState>[child],
      ).toJson(),
    );
    final applier = _FakeApplier();
    final persisted = <ProposalApplyState>[];
    final result = await BatchProposalApplyCoordinator(
      applier: applier,
      persist: (state) async => persisted.add(state),
    ).recover(applying, total: 3);

    expect(result, same(applying));
    expect(applier.undoneIds, isEmpty);
    expect(persisted, isEmpty);
  });

  test(
    'finalization failure compensates all children in reverse order',
    () async {
      final applier = _FakeApplier();
      final coordinator = BatchProposalApplyCoordinator(
        applier: applier,
        persist: (_) async {},
      );

      final result = await coordinator.execute(
        _plan(),
        finalize: (_, _) async => throw StateError('undo stack unavailable'),
      );

      expect(result.status, ProposalApplyStatus.errored);
      expect(applier.undoneIds, ['entity-2', 'entity-1', 'entity-0']);
      expect(
        BatchProposalProgress.fromState(result, total: 3).rollbackComplete,
        isTrue,
      );
    },
  );
}
