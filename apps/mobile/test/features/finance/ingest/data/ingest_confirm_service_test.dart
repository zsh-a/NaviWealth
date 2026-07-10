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
  final List<ConfirmedIngestItem> recoveryItems = [];
  bool Function(String draftId, DraftStatus status)? shouldThrow;

  @override
  Future<void> markNeedsFinalize(ConfirmedIngestItem item) async {
    recoveryItems.add(item);
  }

  @override
  Future<void> updateStatus(String draftId, DraftStatus status) async {
    updates.add((draftId, status));
    if (shouldThrow?.call(draftId, status) ?? false) {
      throw StateError('store unavailable');
    }
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
        ('d1', DraftStatus.confirmed),
      ]);
    });

    test('normalizes apply failures and leaves the draft pending', () async {
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
                IngestConfirmError.applyFailed,
              )
              .having(
                (error) => error.message,
                'message',
                'Could not record this entry.',
              ),
        ),
      );
      expect(store.updates, isEmpty);
    });

    test('undoes an applied entry when marking confirmed fails', () async {
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
                IngestRecovery.retryOperation,
              ),
        ),
      );
      expect(applier.undoneStates, <ProposalApplyState>[state]);
    });

    test('reports when status-write compensation also fails', () async {
      final state = _applied('entry-1');
      final applier = _FakeApplier(
        onApply: (_) async => state,
        onUndo: (_) => throw StateError('undo unavailable'),
      );
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
      expect(store.recoveryItems.single.applyState, same(state));
      expect(applier.appliedPlans, hasLength(1));

      store.shouldThrow = null;
      await service.finalizeApplied(error.item!);
      expect(applier.appliedPlans, hasLength(1));
      expect(store.updates.last, ('d1', DraftStatus.confirmed));
    });

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
        [
          _draft(id: 'good-1'),
          _draft(id: 'duplicate', verdict: DedupVerdict.duplicate),
          _draft(id: 'bad'),
          _draft(id: 'settled', status: DraftStatus.dismissed),
          _draft(id: 'good-2'),
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
