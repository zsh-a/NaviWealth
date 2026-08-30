import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_confirm_service.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_draft_store.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_external_confirmation_coordinator.dart';
import 'package:naviwealth/features/finance/ingest/domain/ingest_models.dart';

import '../../../../core/persistence/test_database.dart';

IngestDraft _draft({
  String id = 'external-1',
  IngestTransactionKind kind = IngestTransactionKind.transfer,
}) => IngestDraft(
  draftId: id,
  ownerUserId: 'u1',
  createdAt: DateTime.utc(2026, 8, 30, 9),
  sourceKind: IngestSourceKind.csv,
  parsed: ParsedTransaction(
    description: kind == IngestTransactionKind.trade
        ? 'Buy AAPL'
        : 'Transfer to savings',
    amountMinor: -125000,
    currency: 'CNY',
    occurredAt: DateTime.utc(2026, 8, 29),
    kind: kind,
  ),
  verdict: DedupVerdict.newTxn,
  status: DraftStatus.pending,
);

class _FailingTransitionStore implements IngestDraftBatchLifecycleStore {
  _FailingTransitionStore(this.delegate, {required this.failAt});

  final IngestDraftStore delegate;
  final int failAt;
  int calls = 0;

  @override
  Future<T> runBatch<T>(Future<T> Function() action) =>
      delegate.runBatch(action);

  @override
  Future<IngestLifecycleMutationResult> transition(
    IngestLifecycleTransition transition,
  ) {
    calls++;
    if (calls == failAt) {
      return Future.value(
        const IngestLifecycleMutationResult(
          IngestLifecycleMutationOutcome.conflict,
        ),
      );
    }
    return delegate.transition(transition);
  }
}

Future<int> _probeCount(AppDatabase db) async {
  final row = await db
      .customSelect('SELECT COUNT(*) AS n FROM ingest_external_probe')
      .getSingle();
  return row.read<int>('n');
}

void main() {
  test(
    'confirm persists typed write and final lifecycle in one transaction',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      await db.customStatement(
        'CREATE TABLE ingest_external_probe (id TEXT PRIMARY KEY)',
      );
      final store = IngestDraftStore(db, ownerUserId: 'u1');
      addTearDown(store.dispose);
      final draft = _draft();
      await store.putAll([draft]);
      final coordinator = IngestExternalConfirmationCoordinator(
        store: store,
        clock: () => DateTime.utc(2026, 8, 30, 10),
      );

      final commit = await coordinator.confirm<String>(
        draft,
        kind: IngestExternalKind.transfer,
        apply: (operationToken) async {
          await db.customStatement(
            'INSERT INTO ingest_external_probe (id) VALUES (?)',
            [operationToken],
          );
          return operationToken;
        },
        entityId: (receipt) => receipt,
      );

      expect(commit.receipt, commit.operationToken);
      expect(commit.item.draft.status, DraftStatus.confirmed);
      expect(commit.item.draft.revision, 4);
      expect(commit.item.entityId, commit.operationToken);
      expect(commit.item.applyState.undoData, {
        'ingest_external_kind': 'transfer',
        'operation_token': commit.operationToken,
      });
      expect(await _probeCount(db), 1);
      expect(await store.countByStatus(DraftStatus.pending), 0);
      expect(await store.countByStatus(DraftStatus.confirmed), 1);
    },
  );

  test(
    'business failure rolls back reservation and partial typed write',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      await db.customStatement(
        'CREATE TABLE ingest_external_probe (id TEXT PRIMARY KEY)',
      );
      final store = IngestDraftStore(db, ownerUserId: 'u1');
      addTearDown(store.dispose);
      final draft = _draft();
      await store.putAll([draft]);
      final coordinator = IngestExternalConfirmationCoordinator(store: store);

      await expectLater(
        coordinator.confirm<String>(
          draft,
          kind: IngestExternalKind.transfer,
          apply: (operationToken) async {
            await db.customStatement(
              'INSERT INTO ingest_external_probe (id) VALUES (?)',
              [operationToken],
            );
            throw StateError('repository failed after write');
          },
          entityId: (receipt) => receipt,
        ),
        throwsStateError,
      );

      expect(await _probeCount(db), 0);
      final pending = (await store.listByStatus(DraftStatus.pending)).single;
      expect(pending.revision, 0);
      expect(
        (await store.listPendingReviewItems()).single.isOrdinaryPending,
        isTrue,
      );
    },
  );

  test(
    'final lifecycle conflict rolls back the already-applied typed write',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      await db.customStatement(
        'CREATE TABLE ingest_external_probe (id TEXT PRIMARY KEY)',
      );
      final store = IngestDraftStore(db, ownerUserId: 'u1');
      addTearDown(store.dispose);
      final draft = _draft();
      await store.putAll([draft]);
      final failingStore = _FailingTransitionStore(store, failAt: 4);
      final coordinator = IngestExternalConfirmationCoordinator(
        store: failingStore,
      );

      await expectLater(
        coordinator.confirm<String>(
          draft,
          kind: IngestExternalKind.transfer,
          apply: (operationToken) async {
            await db.customStatement(
              'INSERT INTO ingest_external_probe (id) VALUES (?)',
              [operationToken],
            );
            return operationToken;
          },
          entityId: (receipt) => receipt,
        ),
        throwsA(
          isA<IngestConfirmException>().having(
            (error) => error.code,
            'code',
            IngestConfirmError.lifecycleConflict,
          ),
        ),
      );

      expect(await _probeCount(db), 0);
      final pending = (await store.listByStatus(DraftStatus.pending)).single;
      expect(pending.revision, 0);
    },
  );

  test(
    'stale retry is rejected before applying the typed write again',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      await db.customStatement(
        'CREATE TABLE ingest_external_probe (id TEXT PRIMARY KEY)',
      );
      final store = IngestDraftStore(db, ownerUserId: 'u1');
      addTearDown(store.dispose);
      final draft = _draft(kind: IngestTransactionKind.trade);
      await store.putAll([draft]);
      final coordinator = IngestExternalConfirmationCoordinator(store: store);
      var applyCalls = 0;

      Future<String> apply(String operationToken) async {
        applyCalls++;
        await db.customStatement(
          'INSERT INTO ingest_external_probe (id) VALUES (?)',
          [operationToken],
        );
        return operationToken;
      }

      await coordinator.confirm<String>(
        draft,
        kind: IngestExternalKind.trade,
        apply: apply,
        entityId: (receipt) => receipt,
      );
      await expectLater(
        coordinator.confirm<String>(
          draft,
          kind: IngestExternalKind.trade,
          apply: apply,
          entityId: (receipt) => receipt,
        ),
        throwsA(isA<IngestConfirmException>()),
      );

      expect(applyCalls, 1);
      expect(await _probeCount(db), 1);
    },
  );

  test(
    'undo atomically reverses typed write and restores review row',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      await db.customStatement(
        'CREATE TABLE ingest_external_probe (id TEXT PRIMARY KEY)',
      );
      final store = IngestDraftStore(db, ownerUserId: 'u1');
      addTearDown(store.dispose);
      final draft = _draft();
      await store.putAll([draft]);
      final coordinator = IngestExternalConfirmationCoordinator(store: store);
      final commit = await coordinator.confirm<String>(
        draft,
        kind: IngestExternalKind.transfer,
        apply: (operationToken) async {
          await db.customStatement(
            'INSERT INTO ingest_external_probe (id) VALUES (?)',
            [operationToken],
          );
          return operationToken;
        },
        entityId: (receipt) => receipt,
      );

      await coordinator.undo<String>(
        commit,
        undoMutation: (receipt) => db.customStatement(
          'DELETE FROM ingest_external_probe WHERE id = ?',
          [receipt],
        ),
      );

      expect(await _probeCount(db), 0);
      final pending = (await store.listByStatus(DraftStatus.pending)).single;
      expect(pending.revision, 7);
      expect(
        (await store.listPendingReviewItems()).single.isOrdinaryPending,
        isTrue,
      );
    },
  );

  test(
    'undo failure rolls back compensation and keeps draft confirmed',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      await db.customStatement(
        'CREATE TABLE ingest_external_probe (id TEXT PRIMARY KEY)',
      );
      final store = IngestDraftStore(db, ownerUserId: 'u1');
      addTearDown(store.dispose);
      final draft = _draft();
      await store.putAll([draft]);
      final coordinator = IngestExternalConfirmationCoordinator(store: store);
      final commit = await coordinator.confirm<String>(
        draft,
        kind: IngestExternalKind.transfer,
        apply: (operationToken) async {
          await db.customStatement(
            'INSERT INTO ingest_external_probe (id) VALUES (?)',
            [operationToken],
          );
          return operationToken;
        },
        entityId: (receipt) => receipt,
      );

      await expectLater(
        coordinator.undo<String>(
          commit,
          undoMutation: (receipt) async {
            await db.customStatement(
              'DELETE FROM ingest_external_probe WHERE id = ?',
              [receipt],
            );
            throw StateError('undo failed after write');
          },
        ),
        throwsStateError,
      );

      expect(await _probeCount(db), 1);
      final confirmed = (await store.listByStatus(DraftStatus.confirmed))
          .single;
      expect(confirmed.revision, 4);
    },
  );
}
