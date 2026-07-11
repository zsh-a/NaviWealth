import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/composition/proposal_applier.dart';
import 'package:naviwealth/core/ai/composition/proposal_apply_state.dart';
import 'package:naviwealth/core/ai/composition/proposal_plan.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_confirm_service.dart';
import 'package:naviwealth/features/finance/ingest/domain/ingest_models.dart';

IngestDraft _draft({
  String id = 'd1',
  String? categoryHint,
  int amountMinor = -3850,
  DraftStatus status = DraftStatus.pending,
  DedupVerdict verdict = DedupVerdict.newTxn,
}) => IngestDraft(
  draftId: id,
  ownerUserId: 'u1',
  createdAt: DateTime.utc(2026, 5, 10),
  sourceKind: IngestSourceKind.csv,
  parsed: ParsedTransaction(
    description: 'Starbucks Coffee',
    amountMinor: amountMinor,
    currency: 'CNY',
    occurredAt: DateTime.utc(2026, 5, 10),
    categoryHint: categoryHint,
  ),
  verdict: verdict,
  status: status,
);

ProposalApplyState _applied(String id) => ProposalApplyState(
  status: ProposalApplyStatus.applied,
  appliedEntityId: id,
  appliedTable: 'journal_entries',
  appliedAt: DateTime.utc(2026, 5, 10),
  undoData: <String, Object?>{'source': 'ingest'},
  shortLabel: 'Imported expense',
);

class _FakeApplier implements ProposalApplier {
  _FakeApplier({required this.onApply, this.onUndo});

  final Future<ProposalApplyState> Function(ReadyProposalPlan plan) onApply;
  final Future<void> Function(ProposalApplyState state)? onUndo;
  final List<ReadyProposalPlan> appliedPlans = [];
  final List<ProposalApplyState> undoneStates = [];

  @override
  Future<ProposalApplyState> apply(ReadyProposalPlan plan) async {
    appliedPlans.add(plan);
    return onApply(plan);
  }

  @override
  Future<void> undo(ProposalApplyState state) async {
    undoneStates.add(state);
    await onUndo?.call(state);
  }
}

class _FakeLifecycleStore implements IngestDraftLifecycleStore {
  final List<(String, DraftStatus)> updates = [];
  bool Function(String draftId, DraftStatus status)? shouldThrow;
  int _revision = 0;

  @override
  Future<IngestLifecycleMutationResult> transition(
    IngestLifecycleTransition transition,
  ) async {
    updates.add((transition.draftId, transition.nextStatus));
    if (shouldThrow?.call(transition.draftId, transition.nextStatus) ?? false) {
      throw StateError('store unavailable');
    }
    _revision++;
    return IngestLifecycleMutationResult(
      IngestLifecycleMutationOutcome.applied,
      revision: _revision,
    );
  }
}

void main() {
  group('IngestConfirmService.expensePlanFor', () {
    test('maps a draft to a propose_expense-shaped ready plan', () {
      final plan = IngestConfirmService.expensePlanFor(
        _draft(categoryHint: 'coffee'),
        fromAccountId: 'acct-cash',
      );

      expect(plan.kind, 'expense');
      expect(plan.proposalId, 'd1');
      expect(plan.payload['account_id'], 'acct-cash');
      expect(plan.payload['currency'], 'CNY');
      expect(plan.payload['category'], 'coffee');
      expect(plan.payload['note'], 'Starbucks Coffee');
      expect(plan.payload['date'], '2026-05-10T00:00:00.000Z');
      // Amount is positive (sign handled by the JE builder) and exact.
      expect(
        Decimal.parse(plan.payload['amount']! as String),
        Decimal.parse('38.50'),
      );
    });

    test('defaults the category to "other" when unclassified', () {
      final plan = IngestConfirmService.expensePlanFor(
        _draft(),
        fromAccountId: 'acct-cash',
      );
      expect(plan.payload['category'], 'other');
    });

    test('sanitizes unknown category hints to "other"', () {
      final plan = IngestConfirmService.expensePlanFor(
        _draft(categoryHint: 'weird:model:label'),
        fromAccountId: 'acct-cash',
      );
      expect(plan.payload['category'], 'other');
    });

    test('amount minor → decimal handles sub-yuan and round values', () {
      expect(
        Decimal.parse(
          IngestConfirmService.expensePlanFor(
                _draft(amountMinor: -5),
                fromAccountId: 'a',
              ).payload['amount']!
              as String,
        ),
        Decimal.parse('0.05'),
      );
      expect(
        Decimal.parse(
          IngestConfirmService.expensePlanFor(
                _draft(amountMinor: -10000),
                fromAccountId: 'a',
              ).payload['amount']!
              as String,
        ),
        Decimal.parse('100.00'),
      );
    });
  });

  group('IngestConfirmService lifecycle', () {
    test('confirm returns the draft and complete applied state', () async {
      final state = _applied('entry-1');
      final applier = _FakeApplier(onApply: (_) async => state);
      final store = _FakeLifecycleStore();
      final service = IngestConfirmService(applier: applier, store: store);

      final result = await service.confirm(
        _draft(),
        fromAccountId: 'acct-cash',
      );

      expect(result.draft.draftId, 'd1');
      expect(identical(result.applyState, state), isTrue);
      expect(result.entityId, 'entry-1');
      expect(store.updates, <(String, DraftStatus)>[
        ('d1', DraftStatus.confirming),
        ('d1', DraftStatus.confirming),
        ('d1', DraftStatus.pending),
        ('d1', DraftStatus.confirmed),
      ]);
    });

    test('normalizes apply failures into manual recovery', () async {
      final applier = _FakeApplier(
        onApply: (_) => throw StateError('database internals'),
      );
      final store = _FakeLifecycleStore();
      final service = IngestConfirmService(applier: applier, store: store);

      await expectLater(
        service.confirm(_draft(), fromAccountId: 'acct-cash'),
        throwsA(
          isA<IngestConfirmException>()
              .having(
                (error) => error.code,
                'code',
                IngestConfirmError.manualRecoveryRequired,
              )
              .having(
                (error) => error.message,
                'message',
                'Recording may have started. Review it manually before retrying.',
              ),
        ),
      );
      expect(store.updates.last, ('d1', DraftStatus.pending));
    });

    test('never compensates or reapplies after invocation has begun', () async {
      final state = _applied('entry-1');
      final applier = _FakeApplier(onApply: (_) async => state);
      final store = _FakeLifecycleStore()
        ..shouldThrow = (_, status) => status == DraftStatus.confirmed;
      final service = IngestConfirmService(applier: applier, store: store);

      await expectLater(
        service.confirm(_draft(), fromAccountId: 'acct-cash'),
        throwsA(
          isA<IngestConfirmException>()
              .having(
                (error) => error.code,
                'code',
                IngestConfirmError.lifecycleWriteFailed,
              )
              .having(
                (error) => error.recovery,
                'recovery',
                IngestRecovery.finalizeApplied,
              ),
        ),
      );
      expect(applier.undoneStates, isEmpty);
    });

    test(
      'returns a finalize-only continuation when finalization fails',
      () async {
        final state = _applied('entry-1');
        final applier = _FakeApplier(onApply: (_) async => state);
        final store = _FakeLifecycleStore()
          ..shouldThrow = (_, status) => status == DraftStatus.confirmed;
        final service = IngestConfirmService(applier: applier, store: store);

        final error = await service
            .confirm(_draft(), fromAccountId: 'acct-cash')
            .then<IngestConfirmException>(
              (_) => throw StateError('confirmation should fail'),
              onError: (Object error, StackTrace _) =>
                  error as IngestConfirmException,
            );

        expect(error.recovery, IngestRecovery.finalizeApplied);
        expect(error.item?.applyState, same(state));
        expect(applier.appliedPlans, hasLength(1));

        store.shouldThrow = null;
        await service.finalizeApplied(error.item!);
        expect(applier.appliedPlans, hasLength(1));
        expect(store.updates.last, ('d1', DraftStatus.confirmed));
      },
    );

    test('dismiss and restore own the draft status transitions', () async {
      final store = _FakeLifecycleStore();
      final service = IngestConfirmService(
        applier: _FakeApplier(onApply: (_) async => _applied('unused')),
        store: store,
      );
      final draft = _draft();

      await service.dismiss(draft);
      await service.restore(draft);

      expect(store.updates, <(String, DraftStatus)>[
        ('d1', DraftStatus.dismissed),
        ('d1', DraftStatus.pending),
      ]);
    });

    test('mixed batch continues and reports progress per fresh item', () async {
      final applier = _FakeApplier(
        onApply: (plan) async {
          if (plan.proposalId == 'bad') {
            throw ProposalApplyException('Rejected expense');
          }
          return _applied('entry-${plan.proposalId}');
        },
      );
      final store = _FakeLifecycleStore();
      final service = IngestConfirmService(applier: applier, store: store);
      final progress = <(int, int)>[];

      final result = await service.confirmAllFresh(
        <IngestReviewItem>[
          IngestReviewItem(draft: _draft(id: 'good-1')),
          IngestReviewItem(
            draft: _draft(id: 'duplicate', verdict: DedupVerdict.duplicate),
          ),
          IngestReviewItem(draft: _draft(id: 'bad')),
          IngestReviewItem(
            draft: _draft(id: 'settled', status: DraftStatus.dismissed),
          ),
          IngestReviewItem(draft: _draft(id: 'good-2')),
        ],
        fromAccountId: 'acct-cash',
        onProgress: (completed, total) => progress.add((completed, total)),
      );

      expect(result.confirmed.map((item) => item.draft.draftId), [
        'good-1',
        'good-2',
      ]);
      expect(result.failures.single.item.draftId, 'bad');
      expect(result.completed, 3);
      expect(progress, [(1, 3), (2, 3), (3, 3)]);
    });

    test('raw lifecycle failure does not abort later batch items', () async {
      final applier = _FakeApplier(
        onApply: (plan) async => _applied('entry-${plan.proposalId}'),
      );
      final store = _FakeLifecycleStore()
        ..shouldThrow = (id, status) =>
            id == 'bad' && status == DraftStatus.confirming;
      final service = IngestConfirmService(applier: applier, store: store);
      final progress = <(int, int)>[];

      final result = await service.confirmAllFresh(
        [
          IngestReviewItem(draft: _draft(id: 'bad')),
          IngestReviewItem(draft: _draft(id: 'good')),
        ],
        fromAccountId: 'acct-cash',
        onProgress: (completed, total) => progress.add((completed, total)),
      );

      expect(result.failures.single.item.draftId, 'bad');
      expect(result.confirmed.single.draft.draftId, 'good');
      expect(applier.appliedPlans.single.proposalId, 'good');
      expect(progress, [(1, 2), (2, 2)]);
    });

    test(
      'raw invocation-marker failure releases and continues the batch',
      () async {
        var badConfirmingWrites = 0;
        final applier = _FakeApplier(
          onApply: (plan) async => _applied('entry-${plan.proposalId}'),
        );
        final store = _FakeLifecycleStore()
          ..shouldThrow = (id, status) {
            if (id != 'bad' || status != DraftStatus.confirming) return false;
            badConfirmingWrites += 1;
            return badConfirmingWrites == 2;
          };
        final service = IngestConfirmService(applier: applier, store: store);

        final result = await service.confirmAllFresh([
          IngestReviewItem(draft: _draft(id: 'bad')),
          IngestReviewItem(draft: _draft(id: 'good')),
        ], fromAccountId: 'acct-cash');

        expect(result.failures.single.item.draftId, 'bad');
        expect(
          result.failures.single.error.code,
          IngestConfirmError.lifecycleWriteFailed,
        );
        expect(result.confirmed.single.draft.draftId, 'good');
        expect(applier.appliedPlans.single.proposalId, 'good');
        expect(
          store.updates.where((update) => update.$1 == 'bad').map((e) => e.$2),
          [DraftStatus.confirming, DraftStatus.confirming, DraftStatus.pending],
        );
      },
    );

    test('batch dismiss returns exact per-id partial outcomes', () async {
      final store = _FakeLifecycleStore()
        ..shouldThrow = (id, status) =>
            id == 'bad' && status == DraftStatus.dismissed;
      final service = IngestConfirmService(
        applier: _FakeApplier(onApply: (_) async => _applied('unused')),
        store: store,
      );

      final result = await service.dismissSelected([
        IngestReviewItem(draft: _draft(id: 'good')),
        IngestReviewItem(draft: _draft(id: 'bad')),
        IngestReviewItem(
          draft: _draft(id: 'recovery'),
          recoveryUnreadable: true,
        ),
      ]);

      expect(result.succeeded.map((item) => item.draft.draftId), ['good']);
      expect(result.failures.map((failure) => failure.item.draft.draftId), [
        'bad',
      ]);
      expect(store.updates.map((update) => update.$1), ['good', 'bad']);
    });

    test('batch finalize attempts only typed finalize continuations', () async {
      final state = _applied('entry');
      final store = _FakeLifecycleStore()
        ..shouldThrow = (id, status) =>
            id == 'bad' && status == DraftStatus.confirmed;
      final service = IngestConfirmService(
        applier: _FakeApplier(onApply: (_) async => state),
        store: store,
      );
      IngestReviewItem pending(String id) {
        final draft = _draft(id: id);
        return IngestReviewItem(
          draft: draft,
          pendingFinalize: ConfirmedIngestItem(draft: draft, applyState: state),
        );
      }

      final result = await service.finalizeSelected([
        pending('good'),
        pending('bad'),
        IngestReviewItem(draft: _draft(id: 'ordinary')),
      ]);

      expect(result.succeeded.map((item) => item.draft.draftId), ['good']);
      expect(result.failures.map((failure) => failure.item.draft.draftId), [
        'bad',
      ]);
    });

    test('batch undo continues after an item failure', () async {
      final first = ConfirmedIngestItem(
        draft: _draft(id: 'one'),
        applyState: _applied('entry-one'),
      );
      final second = ConfirmedIngestItem(
        draft: _draft(id: 'two'),
        applyState: _applied('entry-two'),
      );
      final applier = _FakeApplier(
        onApply: (_) async => _applied('unused'),
        onUndo: (state) async {
          if (state.appliedEntityId == 'entry-two') {
            throw StateError('cannot undo second');
          }
        },
      );
      final store = _FakeLifecycleStore();
      final service = IngestConfirmService(applier: applier, store: store);
      final progress = <(int, int)>[];

      final result = await service.undoAllConfirmed([
        first,
        second,
      ], onProgress: (completed, total) => progress.add((completed, total)));

      expect(result.restored, [first]);
      expect(result.failures.single.item, same(second));
      expect(result.failures.single.error.code, IngestConfirmError.undoFailed);
      expect(store.updates, [('one', DraftStatus.pending)]);
      expect(progress, [(1, 2), (2, 2)]);
    });

    test(
      'retry after undo restore failure does not invoke undo twice',
      () async {
        final item = ConfirmedIngestItem(
          draft: _draft(id: 'one'),
          applyState: _applied('entry-one'),
        );
        final applier = _FakeApplier(onApply: (_) async => _applied('unused'));
        final store = _FakeLifecycleStore()
          ..shouldThrow = (_, status) => status == DraftStatus.pending;
        final service = IngestConfirmService(applier: applier, store: store);

        final error = await service
            .undoConfirmed(item)
            .then<IngestConfirmException>(
              (_) => throw StateError(
                'undo should fail while restoring the draft',
              ),
              onError: (Object error, StackTrace _) =>
                  error as IngestConfirmException,
            );

        expect(error.recovery, IngestRecovery.restoreDraft);
        expect(error.item, same(item));
        expect(applier.undoneStates, [item.applyState]);

        store.shouldThrow = null;
        final retried = await service.retryUndoFailures([
          IngestBatchItemFailure(item: item, error: error),
        ]);
        expect(retried.restored, [item]);
        expect(retried.failures, isEmpty);
        expect(applier.undoneStates, [item.applyState]);
        expect(store.updates.last, ('one', DraftStatus.pending));
      },
    );
  });
}
