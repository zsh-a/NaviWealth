import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/composition/proposal_applier.dart';
import 'package:naviwealth/core/ai/composition/proposal_apply_state.dart';
import 'package:naviwealth/core/ai/composition/proposal_plan.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_confirm_service.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_draft_store.dart';
import 'package:naviwealth/features/finance/ingest/domain/ingest_models.dart';

import '../../../../core/persistence/test_database.dart';

IngestDraft _draft(
  String id, {
  DedupVerdict verdict = DedupVerdict.newTxn,
  DraftStatus status = DraftStatus.pending,
}) => IngestDraft(
  draftId: id,
  ownerUserId: 'u1',
  createdAt: DateTime.utc(2026, 5, 10, 9),
  sourceKind: IngestSourceKind.csv,
  parsed: ParsedTransaction(
    description: 'Coffee $id',
    amountMinor: -3800,
    currency: 'CNY',
    occurredAt: DateTime.utc(2026, 5, 10),
    categoryHint: 'coffee',
  ),
  verdict: verdict,
  status: status,
  originLabel: '粘贴文本',
);

class _ControlledApplier implements ProposalApplier {
  _ControlledApplier(this.onApply);

  final Future<ProposalApplyState> Function() onApply;
  int applyCalls = 0;

  @override
  Future<ProposalApplyState> apply(ReadyProposalPlan plan) {
    applyCalls++;
    return onApply();
  }

  @override
  Future<void> undo(ProposalApplyState state) async {}
}

ProposalApplyState _appliedState() => ProposalApplyState(
  status: ProposalApplyStatus.applied,
  appliedEntityId: 'entry-d1',
  appliedTable: 'journal_entries',
  appliedAt: DateTime.utc(2026, 5, 10, 10),
);

void main() {
  test(
    'putAll + listByStatus round-trips and preserves parsed fields',
    () async {
      final db = makeTestDatabase();
      final store = IngestDraftStore(db, ownerUserId: 'u1');

      await store.putAll([_draft('d1'), _draft('d2')]);
      final pending = await store.listByStatus(DraftStatus.pending);

      expect(pending, hasLength(2));
      final d = pending.firstWhere((x) => x.draftId == 'd1');
      expect(d.parsed.amountMinor, -3800);
      expect(d.parsed.categoryHint, 'coffee');
      expect(d.parsed.currency, 'CNY');
      expect(d.sourceKind, IngestSourceKind.csv);
      expect(d.originLabel, '粘贴文本');
      await db.close();
    },
  );

  test('owner-scoped CAS moves a draft out of the pending queue', () async {
    final db = makeTestDatabase();
    final store = IngestDraftStore(db, ownerUserId: 'u1');
    await store.putAll([_draft('d1'), _draft('d2')]);

    final result = await store.transition(
      const IngestLifecycleTransition(
        ownerUserId: 'u1',
        draftId: 'd1',
        expectedStatus: DraftStatus.pending,
        expectedRevision: 0,
        nextStatus: DraftStatus.confirmed,
      ),
    );

    expect(result.outcome, IngestLifecycleMutationOutcome.applied);
    expect(await store.countByStatus(DraftStatus.pending), 1);
    expect(await store.countByStatus(DraftStatus.confirmed), 1);
    final pending = await store.listByStatus(DraftStatus.pending);
    expect(pending.single.draftId, 'd2');
    await db.close();
  });

  test('owner partitioning isolates drafts', () async {
    final db = makeTestDatabase();
    final mine = IngestDraftStore(db, ownerUserId: 'u1');
    final theirs = IngestDraftStore(db, ownerUserId: 'u2');
    await mine.putAll([_draft('d1')]);

    expect(await theirs.listByStatus(DraftStatus.pending), isEmpty);
    expect(await mine.listByStatus(DraftStatus.pending), hasLength(1));
    await db.close();
  });

  test('watchByStatus yields the initial pending snapshot', () async {
    final db = makeTestDatabase();
    final store = IngestDraftStore(db, ownerUserId: 'u1');
    await store.putAll([_draft('d1'), _draft('d2')]);

    final initial = await store.watchByStatus(DraftStatus.pending).first;
    expect(initial.map((d) => d.draftId), containsAll(<String>['d1', 'd2']));

    store.dispose();
    await db.close();
  });

  test('pending recovery round-trips across store recreation', () async {
    final db = makeTestDatabase();
    final store = IngestDraftStore(db, ownerUserId: 'u1');
    final draft = _draft('d1');
    await store.putAll([draft]);
    final state = ProposalApplyState(
      status: ProposalApplyStatus.applied,
      appliedEntityId: 'entry-d1',
      appliedTable: 'journal_entries',
      appliedAt: DateTime.utc(2026, 5, 10, 10),
      undoData: const {'source': 'ingest'},
    );

    final marked = await store.transition(
      IngestLifecycleTransition(
        ownerUserId: 'u1',
        draftId: draft.draftId,
        expectedStatus: DraftStatus.pending,
        expectedRevision: 0,
        nextStatus: DraftStatus.pending,
        nextRecoveryKind: 'finalize_applied',
        nextRecoveryApplyState: state,
      ),
    );
    expect(marked.outcome, IngestLifecycleMutationOutcome.applied);

    final reopened = IngestDraftStore(db, ownerUserId: 'u1');
    final review = await reopened.listPendingReviewItems();
    expect(review.single.draft.draftId, 'd1');
    expect(review.single.pendingFinalize?.applyState.toJson(), state.toJson());

    final finalized = await reopened.transition(
      IngestLifecycleTransition(
        ownerUserId: 'u1',
        draftId: 'd1',
        expectedStatus: DraftStatus.pending,
        expectedRevision: review.single.draft.revision,
        expectedRecoveryKind: 'finalize_applied',
        nextStatus: DraftStatus.confirmed,
      ),
    );
    expect(finalized.outcome, IngestLifecycleMutationOutcome.applied);
    expect(await reopened.listPendingReviewItems(), isEmpty);
    await db.close();
  });

  test('corrupt recovery stays fail-closed', () async {
    final db = makeTestDatabase();
    final store = IngestDraftStore(db, ownerUserId: 'u1');
    await store.putAll([_draft('d1')]);
    await db.customStatement(
      'UPDATE ingest_drafts SET recovery_kind = ?, '
      'recovery_apply_state_json = ? WHERE draft_id = ?',
      ['finalize_applied', '{not-json', 'd1'],
    );

    final review = await store.listPendingReviewItems();
    expect(review.single.blocksApply, isTrue);
    expect(review.single.recoveryUnreadable, isTrue);
    expect(review.single.pendingFinalize, isNull);

    await db.customStatement(
      'UPDATE ingest_drafts SET recovery_kind = ? WHERE draft_id = ?',
      ['unknown_recovery', 'd1'],
    );
    final unknown = await store.listPendingReviewItems();
    expect(unknown.single.blocksApply, isTrue);
    expect(unknown.single.recoveryUnreadable, isTrue);
    await db.close();
  });

  test(
    'pruneSettledBefore drops only old confirmed and dismissed rows',
    () async {
      final db = makeTestDatabase();
      final store = IngestDraftStore(db, ownerUserId: 'u1');
      await store.putAll([
        _draft('old-confirmed', status: DraftStatus.confirmed),
        _draft('old-dismissed', status: DraftStatus.dismissed),
        _draft('pending-keep'),
        _draft('confirming-keep', status: DraftStatus.confirming),
      ]);

      await store.pruneSettledBefore(DateTime.utc(2026, 5, 11));

      expect(await store.countByStatus(DraftStatus.confirmed), 0);
      expect(await store.countByStatus(DraftStatus.dismissed), 0);
      expect(await store.countByStatus(DraftStatus.pending), 1);
      expect(await store.countByStatus(DraftStatus.confirming), 1);
      await db.close();
    },
  );

  test(
    'CAS reports stale conflict and cross-owner notFound privately',
    () async {
      final db = makeTestDatabase();
      final mine = IngestDraftStore(db, ownerUserId: 'u1');
      final theirs = IngestDraftStore(db, ownerUserId: 'u2');
      await mine.putAll([_draft('d1')]);

      final applied = await mine.transition(
        const IngestLifecycleTransition(
          ownerUserId: 'u1',
          draftId: 'd1',
          expectedStatus: DraftStatus.pending,
          expectedRevision: 0,
          nextStatus: DraftStatus.dismissed,
        ),
      );
      final stale = await mine.transition(
        const IngestLifecycleTransition(
          ownerUserId: 'u1',
          draftId: 'd1',
          expectedStatus: DraftStatus.pending,
          expectedRevision: 0,
          nextStatus: DraftStatus.confirmed,
        ),
      );
      final privateMiss = await theirs.transition(
        const IngestLifecycleTransition(
          ownerUserId: 'u2',
          draftId: 'd1',
          expectedStatus: DraftStatus.dismissed,
          expectedRevision: 1,
          nextStatus: DraftStatus.pending,
        ),
      );

      expect(applied.outcome, IngestLifecycleMutationOutcome.applied);
      expect(stale.outcome, IngestLifecycleMutationOutcome.conflict);
      expect(privateMiss.outcome, IngestLifecycleMutationOutcome.notFound);
      await db.close();
    },
  );

  test(
    'ordinary transition excludes recovery and stale operation tokens',
    () async {
      final db = makeTestDatabase();
      final store = IngestDraftStore(db, ownerUserId: 'u1');
      await store.putAll([_draft('d1')]);
      await db.customStatement(
        'UPDATE ingest_drafts SET recovery_kind = ?, revision = 4 '
        'WHERE draft_id = ?',
        ['confirm_ambiguous', 'd1'],
      );

      final ordinary = await store.transition(
        const IngestLifecycleTransition(
          ownerUserId: 'u1',
          draftId: 'd1',
          expectedStatus: DraftStatus.pending,
          expectedRevision: 4,
          nextStatus: DraftStatus.dismissed,
        ),
      );
      final staleToken = await store.transition(
        const IngestLifecycleTransition(
          ownerUserId: 'u1',
          draftId: 'd1',
          expectedStatus: DraftStatus.pending,
          expectedRevision: 4,
          expectedRecoveryKind: 'confirm_ambiguous',
          expectedOperationToken: 'wrong',
          nextStatus: DraftStatus.dismissed,
        ),
      );

      expect(ordinary.outcome, IngestLifecycleMutationOutcome.conflict);
      expect(staleToken.outcome, IngestLifecycleMutationOutcome.conflict);
      expect((await store.listPendingReviewItems()).single.blocksApply, isTrue);
      await db.close();
    },
  );

  test(
    'concurrent confirm reserves once and invokes the applier once',
    () async {
      final db = makeTestDatabase();
      final store = IngestDraftStore(db, ownerUserId: 'u1');
      final draft = _draft('d1');
      await store.putAll([draft]);
      final gate = Completer<ProposalApplyState>();
      final applier = _ControlledApplier(() => gate.future);
      final service = IngestConfirmService(applier: applier, store: store);

      final first = service.confirm(draft, fromAccountId: 'account-1');
      await Future<void>.delayed(Duration.zero);
      final second = service.confirm(draft, fromAccountId: 'account-1');
      await expectLater(
        second,
        throwsA(
          isA<IngestConfirmException>().having(
            (error) => error.code,
            'code',
            IngestConfirmError.lifecycleConflict,
          ),
        ),
      );
      expect(applier.applyCalls, 1);
      expect((await store.listPendingReviewItems()).single.blocksApply, isTrue);

      gate.complete(_appliedState());
      await first;
      expect(await store.countByStatus(DraftStatus.confirmed), 1);
      await db.close();
    },
  );

  test(
    'post-invocation failure persists fail-closed manual recovery',
    () async {
      final db = makeTestDatabase();
      final store = IngestDraftStore(db, ownerUserId: 'u1');
      final draft = _draft('d1');
      await store.putAll([draft]);
      final service = IngestConfirmService(
        applier: _ControlledApplier(() => throw StateError('unknown outcome')),
        store: store,
      );

      await expectLater(
        service.confirm(draft, fromAccountId: 'account-1'),
        throwsA(
          isA<IngestConfirmException>().having(
            (error) => error.code,
            'code',
            IngestConfirmError.manualRecoveryRequired,
          ),
        ),
      );
      final review = (await store.listPendingReviewItems()).single;
      expect(review.draft.status, DraftStatus.pending);
      expect(review.recoveryUnreadable, isTrue);
      expect(review.canBatchConfirm, isFalse);
      expect(review.canBatchDismiss, isFalse);
      await db.close();
    },
  );
}
