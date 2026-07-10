import 'dart:convert';
import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/features/finance/rebalance/data/rebalance_execution_codecs.dart';
import 'package:naviwealth/features/finance/rebalance/data/rebalance_execution_store.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_execution.dart';

import '../../../../core/persistence/test_database.dart';
import 'rebalance_execution_test_fixtures.dart';

void main() {
  group('session creation', () {
    test(
      'concurrent same-fingerprint creates converge on one active row',
      () async {
        final db = makeTestDatabase();
        addTearDown(db.close);
        final first = RebalanceExecutionStore(db, clock: () => testNow);
        final second = RebalanceExecutionStore(db, clock: () => testNow);

        final sessions = await Future.wait([
          first.createOrResume(ownerUserId: 'owner-a', plan: testPlan()),
          second.createOrResume(
            ownerUserId: 'owner-a',
            plan: testPlan(reverseCollections: true),
          ),
        ]);

        expect(sessions[0].id, sessions[1].id);
        expect(sessions[0].items, hasLength(2));
        expect(sessions[0].items.first.suggestion.isSell, isTrue);
        final count = await db.customSelect('''
        SELECT COUNT(*) AS n FROM rebalance_execution_sessions
        WHERE owner_user_id = 'owner-a' AND status = 'active'
      ''').getSingle();
        expect(count.read<int>('n'), 1);
      },
    );

    test(
      'two database connections converge after the winner commits all items',
      () async {
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
        addTearDown(() {
          driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
        });
        final dir = await Directory.systemTemp.createTemp('rebalance_race_');
        addTearDown(() async {
          if (await dir.exists()) await dir.delete(recursive: true);
        });
        final file = File('${dir.path}/naviwealth.db');
        final firstDb = AppDatabase(
          DatabaseConnection(
            NativeDatabase.createInBackground(file, logStatements: false),
          ),
        );
        addTearDown(firstDb.close);
        await firstDb.customSelect('SELECT 1').get();
        final secondDb = AppDatabase(
          DatabaseConnection(
            NativeDatabase.createInBackground(file, logStatements: false),
          ),
        );
        addTearDown(secondDb.close);
        await secondDb.customSelect('SELECT 1').get();
        await firstDb.customStatement('PRAGMA busy_timeout = 5000');
        await secondDb.customStatement('PRAGMA busy_timeout = 5000');
        final first = RebalanceExecutionStore(firstDb, clock: () => testNow);
        final second = RebalanceExecutionStore(secondDb, clock: () => testNow);

        final sessions = await Future.wait([
          first.createOrResume(ownerUserId: 'owner-a', plan: testPlan()),
          second.createOrResume(
            ownerUserId: 'owner-a',
            plan: testPlan(reverseCollections: true),
          ),
        ]);

        expect(sessions[0].id, sessions[1].id);
        expect(sessions[0].items, hasLength(2));
        expect(sessions[1].items, hasLength(2));
        final itemCount = await firstDb
            .customSelect(
              '''
          SELECT COUNT(*) AS n FROM rebalance_execution_items
          WHERE session_id = ?
        ''',
              variables: [Variable.withString(sessions[0].id)],
            )
            .getSingle();
        expect(itemCount.read<int>('n'), 2);
      },
    );

    test('same-fingerprint active decoder error is never swallowed', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final store = RebalanceExecutionStore(db, clock: () => testNow);
      final session = await store.createOrResume(
        ownerUserId: 'owner-a',
        plan: testPlan(),
      );
      final row = await db
          .customSelect(
            'SELECT suggestion_json FROM rebalance_execution_items WHERE id = ?',
            variables: [Variable.withString(session.items.first.id)],
          )
          .getSingle();
      final suggestion =
          jsonDecode(row.read<String>('suggestion_json'))
              as Map<String, Object?>;
      (suggestion['payload']! as Map<String, Object?>)['future'] = true;
      await db.customUpdate(
        'UPDATE rebalance_execution_items SET suggestion_json = ? WHERE id = ?',
        variables: [
          Variable.withString(jsonEncode(suggestion)),
          Variable.withString(session.items.first.id),
        ],
      );

      await expectLater(
        store.createOrResume(ownerUserId: 'owner-a', plan: testPlan()),
        throwsA(isA<RebalanceExecutionCodecError>()),
      );
    });

    test(
      'different fingerprint conflicts unless expected active is replaced',
      () async {
        final db = makeTestDatabase();
        addTearDown(db.close);
        final store = RebalanceExecutionStore(db, clock: () => testNow);
        final original = await store.createOrResume(
          ownerUserId: 'owner-a',
          plan: testPlan(),
        );

        await expectLater(
          store.createOrResume(
            ownerUserId: 'owner-a',
            plan: testPlan(buyAmount: Decimal.fromInt(101)),
          ),
          throwsA(isA<RebalanceExecutionConflict>()),
        );
        final replacement = await store.replaceActive(
          ownerUserId: 'owner-a',
          expectedSessionId: original.id,
          expectedFingerprint: original.planFingerprint,
          plan: testPlan(buyAmount: Decimal.fromInt(101)),
        );

        expect(replacement.id, isNot(original.id));
        expect(
          (await store.getSession(
            ownerUserId: 'owner-a',
            id: original.id,
          ))?.status,
          RebalanceExecutionSessionStatus.archived,
        );
        expect((await store.getActive('owner-a'))?.id, replacement.id);
      },
    );

    test(
      'archive old and create new roll back together on item failure',
      () async {
        final db = makeTestDatabase();
        addTearDown(db.close);
        final store = RebalanceExecutionStore(db, clock: () => testNow);
        final original = await store.createOrResume(
          ownerUserId: 'owner-a',
          plan: testPlan(),
        );
        await db.customStatement('''
        CREATE TRIGGER reject_rebalance_item
        BEFORE INSERT ON rebalance_execution_items
        BEGIN SELECT RAISE(ABORT, 'injected item failure'); END
      ''');

        await expectLater(
          store.replaceActive(
            ownerUserId: 'owner-a',
            expectedSessionId: original.id,
            expectedFingerprint: original.planFingerprint,
            plan: testPlan(buyAmount: Decimal.fromInt(101)),
          ),
          throwsA(anything),
        );

        final active = await store.getActive('owner-a');
        expect(active?.id, original.id);
        expect(active?.status, RebalanceExecutionSessionStatus.active);
      },
    );

    test(
      'replace rejects a stale expected active without archiving winner',
      () async {
        final db = makeTestDatabase();
        addTearDown(db.close);
        final store = RebalanceExecutionStore(db, clock: () => testNow);
        final original = await store.createOrResume(
          ownerUserId: 'owner-a',
          plan: testPlan(),
        );
        final winner = await store.replaceActive(
          ownerUserId: 'owner-a',
          expectedSessionId: original.id,
          expectedFingerprint: original.planFingerprint,
          plan: testPlan(buyAmount: Decimal.fromInt(101)),
        );

        await expectLater(
          store.replaceActive(
            ownerUserId: 'owner-a',
            expectedSessionId: original.id,
            expectedFingerprint: original.planFingerprint,
            plan: testPlan(buyAmount: Decimal.fromInt(102)),
          ),
          throwsA(isA<RebalanceExecutionConflict>()),
        );

        expect((await store.getActive('owner-a'))?.id, winner.id);
        expect(
          (await store.getSession(
            ownerUserId: 'owner-a',
            id: winner.id,
          ))?.status,
          RebalanceExecutionSessionStatus.active,
        );
      },
    );

    test('reopen skipped restores request-aware editable state', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final store = RebalanceExecutionStore(db, clock: () => testNow);
      final session = await store.createOrResume(
        ownerUserId: 'owner-a',
        plan: testPlan(reverseCollections: true),
      );
      final withoutRequest = session.items.first;
      await store.markSkipped(
        ownerUserId: 'owner-a',
        itemId: withoutRequest.id,
      );
      expect(
        (await store.reopenSkipped(
          ownerUserId: 'owner-a',
          itemId: withoutRequest.id,
        )).state,
        RebalanceExecutionItemState.needsDetails,
      );

      final withRequest = session.items.last;
      await store.saveRequest(
        ownerUserId: 'owner-a',
        expected: withRequest,
        request: testRequest(withRequest.id),
      );
      await store.markSkipped(ownerUserId: 'owner-a', itemId: withRequest.id);
      expect(
        (await store.reopenSkipped(
          ownerUserId: 'owner-a',
          itemId: withRequest.id,
        )).state,
        RebalanceExecutionItemState.ready,
      );
    });
  });

  test(
    'apply and Undo leases support renew, release, failure, and finalize',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final store = RebalanceExecutionStore(db, clock: () => testNow);
      final ready = await _readyFirst(store);

      final firstApply = await store.claimApply(
        ownerUserId: 'owner-a',
        itemId: ready.id,
        leaseDuration: const Duration(minutes: 5),
      );
      expect(firstApply, isNotNull);
      await expectLater(
        store.renewApply(
          ownerUserId: 'owner-a',
          itemId: ready.id,
          attemptToken: 'wrong',
          leaseDuration: const Duration(minutes: 5),
        ),
        throwsA(isA<RebalanceStaleAttempt>()),
      );
      expect(
        await store.renewApply(
          ownerUserId: 'owner-a',
          itemId: ready.id,
          attemptToken: firstApply!.token,
          leaseDuration: const Duration(minutes: 10),
        ),
        testNow.add(const Duration(minutes: 10)),
      );
      await store.releaseApply(
        ownerUserId: 'owner-a',
        itemId: ready.id,
        attemptToken: firstApply.token,
      );
      expect(
        (await store.getItem(ownerUserId: 'owner-a', id: ready.id))?.state,
        RebalanceExecutionItemState.ready,
      );

      final failedApply = (await store.claimApply(
        ownerUserId: 'owner-a',
        itemId: ready.id,
        leaseDuration: const Duration(minutes: 5),
      ))!;
      await expectLater(
        store.markApplyFailed(
          ownerUserId: 'owner-a',
          itemId: ready.id,
          attemptToken: failedApply.token,
          issue: RebalanceExecutionIssue(
            RebalanceExecutionIssueCode.undoUnavailable,
            'wrong phase',
          ),
        ),
        throwsA(isA<RebalanceExecutionInvariantError>()),
      );
      expect(
        (await store.getItem(ownerUserId: 'owner-a', id: ready.id))?.state,
        RebalanceExecutionItemState.applying,
      );
      await store.markApplyFailed(
        ownerUserId: 'owner-a',
        itemId: ready.id,
        attemptToken: failedApply.token,
        issue: RebalanceExecutionIssue(
          RebalanceExecutionIssueCode.applyUnavailable,
          'broker unavailable',
        ),
      );
      final failedItem = await store.getItem(
        ownerUserId: 'owner-a',
        id: ready.id,
      );
      expect(failedItem?.state, RebalanceExecutionItemState.applyFailed);
      expect(failedItem?.receipt, isNull);

      final finalApply = (await store.claimApply(
        ownerUserId: 'owner-a',
        itemId: ready.id,
        leaseDuration: const Duration(minutes: 5),
      ))!;
      final applied = await store.runApplyTransaction(
        ownerUserId: 'owner-a',
        itemId: ready.id,
        attemptToken: finalApply.token,
        mutate: (_, _) async => testReceipt(ready.id),
      );
      expect(applied.state, RebalanceExecutionItemState.applied);
      expect(applied.appliedSequence, 1);
      expect(
        await store.claimApply(
          ownerUserId: 'owner-a',
          itemId: ready.id,
          leaseDuration: const Duration(minutes: 5),
        ),
        isNull,
      );

      final firstUndo = (await store.claimUndo(
        ownerUserId: 'owner-a',
        itemId: ready.id,
        leaseDuration: const Duration(minutes: 5),
      ))!;
      await store.renewUndo(
        ownerUserId: 'owner-a',
        itemId: ready.id,
        attemptToken: firstUndo.token,
        leaseDuration: const Duration(minutes: 10),
      );
      await store.releaseUndo(
        ownerUserId: 'owner-a',
        itemId: ready.id,
        attemptToken: firstUndo.token,
      );

      final failedUndo = (await store.claimUndo(
        ownerUserId: 'owner-a',
        itemId: ready.id,
        leaseDuration: const Duration(minutes: 5),
      ))!;
      await expectLater(
        store.markUndoFailed(
          ownerUserId: 'owner-a',
          itemId: ready.id,
          attemptToken: failedUndo.token,
          issue: RebalanceExecutionIssue(
            RebalanceExecutionIssueCode.applyUnavailable,
            'wrong phase',
          ),
        ),
        throwsA(isA<RebalanceExecutionInvariantError>()),
      );
      expect(
        (await store.getItem(ownerUserId: 'owner-a', id: ready.id))?.state,
        RebalanceExecutionItemState.undoing,
      );
      await store.markUndoFailed(
        ownerUserId: 'owner-a',
        itemId: ready.id,
        attemptToken: failedUndo.token,
        issue: RebalanceExecutionIssue(
          RebalanceExecutionIssueCode.undoUnavailable,
          'version conflict',
        ),
      );
      final undoFailed = await store.getItem(
        ownerUserId: 'owner-a',
        id: ready.id,
      );
      expect(undoFailed?.state, RebalanceExecutionItemState.undoFailed);
      expect(undoFailed?.isEconomicallyApplied, isTrue);
      expect(undoFailed?.receipt, isNotNull);
      expect(
        await store.claimApply(
          ownerUserId: 'owner-a',
          itemId: ready.id,
          leaseDuration: const Duration(minutes: 5),
        ),
        isNull,
      );

      final finalUndo = (await store.claimUndo(
        ownerUserId: 'owner-a',
        itemId: ready.id,
        leaseDuration: const Duration(minutes: 5),
      ))!;
      final undone = await store.runUndoTransaction(
        ownerUserId: 'owner-a',
        itemId: ready.id,
        attemptToken: finalUndo.token,
        mutate: (_, _) async {},
      );
      expect(undone.state, RebalanceExecutionItemState.undone);
      expect(undone.receipt, isNotNull);
      expect(undone.appliedSequence, 1);
      expect(undone.isEconomicallyApplied, isFalse);
    },
  );

  test(
    'issue policy gates claims and review while clearing atomically',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final store = RebalanceExecutionStore(db, clock: () => testNow);
      var item = await _readyFirst(store);

      final editableAttempt = (await store.claimApply(
        ownerUserId: 'owner-a',
        itemId: item.id,
        leaseDuration: const Duration(minutes: 5),
      ))!;
      await store.markApplyFailed(
        ownerUserId: 'owner-a',
        itemId: item.id,
        attemptToken: editableAttempt.token,
        issue: RebalanceExecutionIssue(
          RebalanceExecutionIssueCode.priceRequired,
          List.filled(600, 'x').join(),
        ),
      );
      item = (await store.getItem(ownerUserId: 'owner-a', id: item.id))!;
      expect(item.issue?.code, RebalanceExecutionIssueCode.priceRequired);
      expect(item.issue?.debugMessage, hasLength(512));
      final persistedIssue = await _rawItem(db, item.id);
      expect(persistedIssue.read<String>('error'), hasLength(512));
      expect(
        await store.claimApply(
          ownerUserId: 'owner-a',
          itemId: item.id,
          leaseDuration: const Duration(minutes: 5),
        ),
        isNull,
      );

      item = await store.saveRequest(
        ownerUserId: 'owner-a',
        expected: item,
        request: testRequest(item.id),
      );
      expect(item.state, RebalanceExecutionItemState.ready);
      expect(item.issue, isNull);

      final fatalAttempt = (await store.claimApply(
        ownerUserId: 'owner-a',
        itemId: item.id,
        leaseDuration: const Duration(minutes: 5),
      ))!;
      await store.markApplyFailed(
        ownerUserId: 'owner-a',
        itemId: item.id,
        attemptToken: fatalAttempt.token,
        issue: RebalanceExecutionIssue(
          RebalanceExecutionIssueCode.internal,
          'database mismatch',
        ),
      );
      item = (await store.getItem(ownerUserId: 'owner-a', id: item.id))!;
      await expectLater(
        store.saveRequest(
          ownerUserId: 'owner-a',
          expected: item,
          request: testRequest(item.id),
        ),
        throwsA(isA<RebalanceExecutionConflict>()),
      );
      expect(
        await store.claimApply(
          ownerUserId: 'owner-a',
          itemId: item.id,
          leaseDuration: const Duration(minutes: 5),
        ),
        isNull,
      );

      final skipped = await store.markSkipped(
        ownerUserId: 'owner-a',
        itemId: item.id,
      );
      expect(skipped.state, RebalanceExecutionItemState.skipped);
      expect(skipped.issue, isNull);
    },
  );

  test('owner-B request cannot bind owner-A item', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = RebalanceExecutionStore(db, clock: () => testNow);
    final session = await store.createOrResume(
      ownerUserId: 'owner-a',
      plan: testPlan(),
    );
    final item = session.items.first;

    await expectLater(
      store.saveRequest(
        ownerUserId: 'owner-a',
        expected: item,
        request: testRequest(item.id, owner: 'owner-b'),
      ),
      throwsA(isA<RebalanceExecutionConflict>()),
    );

    final row = await _rawItem(db, item.id);
    expect(row.read<String>('state'), 'needsDetails');
    expect(row.read<String?>('request_json'), isNull);
    expect(row.read<String?>('attempt_token'), isNull);
  });

  test('owner-B receipt cannot finalize owner-A claim', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = RebalanceExecutionStore(db, clock: () => testNow);
    final ready = await _readyFirst(store);
    final claim = (await store.claimApply(
      ownerUserId: 'owner-a',
      itemId: ready.id,
      leaseDuration: const Duration(minutes: 5),
    ))!;
    final before = await _rawItem(db, ready.id);

    await expectLater(
      store.runApplyTransaction(
        ownerUserId: 'owner-a',
        itemId: ready.id,
        attemptToken: claim.token,
        mutate: (_, _) async => testReceipt(ready.id, owner: 'owner-b'),
      ),
      throwsA(isA<RebalanceExecutionConflict>()),
    );

    final after = await _rawItem(db, ready.id);
    expect(after.read<String>('state'), 'applying');
    expect(after.read<String>('attempt_token'), claim.token);
    expect(
      after.read<String>('lease_until_iso'),
      before.read<String>('lease_until_iso'),
    );
    expect(after.read<String?>('receipt_json'), isNull);
  });

  test(
    'finalize rejects a stored foreign-owner request without changing lease',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final store = RebalanceExecutionStore(db, clock: () => testNow);
      final ready = await _readyFirst(store);
      final claim = (await store.claimApply(
        ownerUserId: 'owner-a',
        itemId: ready.id,
        leaseDuration: const Duration(minutes: 5),
      ))!;
      final foreignRequest = RebalanceExecutionRequestCodec.encode(
        testRequest(ready.id, owner: 'owner-b'),
      );
      await db.customUpdate(
        'UPDATE rebalance_execution_items SET request_json = ? WHERE id = ?',
        variables: [
          Variable.withString(foreignRequest),
          Variable.withString(ready.id),
        ],
      );
      final before = await _rawItem(db, ready.id);

      await expectLater(
        store.runApplyTransaction(
          ownerUserId: 'owner-a',
          itemId: ready.id,
          attemptToken: claim.token,
          mutate: (_, _) async => testReceipt(ready.id),
        ),
        throwsA(isA<RebalanceExecutionConflict>()),
      );

      final after = await _rawItem(db, ready.id);
      expect(after.read<String>('state'), 'applying');
      expect(after.read<String>('attempt_token'), claim.token);
      expect(
        after.read<String>('lease_until_iso'),
        before.read<String>('lease_until_iso'),
      );
      expect(after.read<String>('request_json'), foreignRequest);
      expect(after.read<String?>('receipt_json'), isNull);
    },
  );

  test(
    'finalize CAS rejects request changed after pre-read and rolls back callback',
    () async {
      final db = _RecoveryRaceDatabase();
      addTearDown(db.close);
      final store = RebalanceExecutionStore(db, clock: () => testNow);
      await db.customStatement(
        'CREATE TABLE rebalance_tx_probe (id TEXT PRIMARY KEY)',
      );
      final ready = await _readyFirst(store);
      final claim = (await store.claimApply(
        ownerUserId: 'owner-a',
        itemId: ready.id,
        leaseDuration: const Duration(minutes: 5),
      ))!;
      final replacement = RebalanceExecutionRequestCodec.encode(
        testRequest(ready.id, owner: 'owner-b'),
      );
      db.beforeFinalizeCas = (database) => database
          .customUpdate(
            'UPDATE rebalance_execution_items SET request_json = ? WHERE id = ?',
            variables: [
              Variable.withString(replacement),
              Variable.withString(ready.id),
            ],
          )
          .then((_) {});

      await expectLater(
        store.runApplyTransaction(
          ownerUserId: 'owner-a',
          itemId: ready.id,
          attemptToken: claim.token,
          mutate: (_, _) async {
            await db.customInsert(
              "INSERT INTO rebalance_tx_probe VALUES ('request-cas')",
            );
            return testReceipt(ready.id);
          },
        ),
        throwsA(isA<RebalanceStaleAttempt>()),
      );

      final row = await _rawItem(db, ready.id);
      expect(await _probeRows(db), isEmpty);
      expect(row.read<String>('state'), 'applying');
      expect(row.read<String>('attempt_token'), claim.token);
      expect(row.read<String>('request_json'), ready.rawRequestJson);
      expect(row.read<String?>('receipt_json'), isNull);
    },
  );

  test(
    'expired lease can be reclaimed and old token cannot renew or finalize',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      var now = testNow;
      final store = RebalanceExecutionStore(db, clock: () => now);
      final ready = await _readyFirst(store);
      final old = (await store.claimApply(
        ownerUserId: 'owner-a',
        itemId: ready.id,
        leaseDuration: const Duration(minutes: 5),
      ))!;
      now = now.add(const Duration(minutes: 6));

      var expiredMutationCalled = false;
      await expectLater(
        store.runApplyTransaction(
          ownerUserId: 'owner-a',
          itemId: ready.id,
          attemptToken: old.token,
          mutate: (_, _) async {
            expiredMutationCalled = true;
            return testReceipt(ready.id);
          },
        ),
        throwsA(isA<RebalanceStaleAttempt>()),
      );
      expect(expiredMutationCalled, isFalse);

      final reclaimed = (await store.claimApply(
        ownerUserId: 'owner-a',
        itemId: ready.id,
        leaseDuration: const Duration(minutes: 5),
      ))!;
      expect(reclaimed.token, isNot(old.token));
      await expectLater(
        store.renewApply(
          ownerUserId: 'owner-a',
          itemId: ready.id,
          attemptToken: old.token,
          leaseDuration: const Duration(minutes: 5),
        ),
        throwsA(isA<RebalanceStaleAttempt>()),
      );
      var staleMutationCalled = false;
      await expectLater(
        store.runApplyTransaction(
          ownerUserId: 'owner-a',
          itemId: ready.id,
          attemptToken: old.token,
          mutate: (_, _) async {
            staleMutationCalled = true;
            return testReceipt(ready.id);
          },
        ),
        throwsA(isA<RebalanceStaleAttempt>()),
      );
      expect(staleMutationCalled, isFalse);
      final applied = await store.runApplyTransaction(
        ownerUserId: 'owner-a',
        itemId: ready.id,
        attemptToken: reclaimed.token,
        mutate: (_, _) async => testReceipt(ready.id),
      );
      expect(applied.state, RebalanceExecutionItemState.applied);
    },
  );

  test('dual controllers race for one lease and only one wins', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final first = RebalanceExecutionStore(db, clock: () => testNow);
    final second = RebalanceExecutionStore(db, clock: () => testNow);
    final ready = await _readyFirst(first);

    final claims = await Future.wait([
      first.claimApply(
        ownerUserId: 'owner-a',
        itemId: ready.id,
        leaseDuration: const Duration(minutes: 5),
      ),
      second.claimApply(
        ownerUserId: 'owner-a',
        itemId: ready.id,
        leaseDuration: const Duration(minutes: 5),
      ),
    ]);

    expect(claims.whereType<RebalanceExecutionAttempt>(), hasLength(1));
  });

  test(
    'applied sequence is allocated once and queried in reverse order',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final store = RebalanceExecutionStore(db, clock: () => testNow);
      final session = await store.createOrResume(
        ownerUserId: 'owner-a',
        plan: testPlan(),
      );

      for (final item in session.items) {
        await store.saveRequest(
          ownerUserId: 'owner-a',
          expected: item,
          request: testRequest(item.id),
        );
        final claim = (await store.claimApply(
          ownerUserId: 'owner-a',
          itemId: item.id,
          leaseDuration: const Duration(minutes: 5),
        ))!;
        await store.runApplyTransaction(
          ownerUserId: 'owner-a',
          itemId: item.id,
          attemptToken: claim.token,
          mutate: (_, _) async => testReceipt(item.id),
        );
      }

      final reverse = await store.listAppliedForUndo(
        ownerUserId: 'owner-a',
        sessionId: session.id,
      );
      expect(reverse.map((item) => item.appliedSequence), [2, 1]);
      expect(reverse.map((item) => item.id), [
        session.items[1].id,
        session.items[0].id,
      ]);
      final refreshed = await store.getActive('owner-a');
      expect(refreshed?.isComplete, isTrue);
      expect(refreshed?.status, RebalanceExecutionSessionStatus.active);
    },
  );

  test('undo claim enforces the database reverse-order barrier', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    var now = testNow;
    final first = RebalanceExecutionStore(db, clock: () => now);
    final second = RebalanceExecutionStore(db, clock: () => now);
    final session = await first.createOrResume(
      ownerUserId: 'owner-a',
      plan: testPlan(),
    );
    for (final item in session.items) {
      await first.saveRequest(
        ownerUserId: 'owner-a',
        expected: item,
        request: testRequest(item.id),
      );
      final apply = (await first.claimApply(
        ownerUserId: 'owner-a',
        itemId: item.id,
        leaseDuration: const Duration(minutes: 5),
      ))!;
      await first.runApplyTransaction(
        ownerUserId: 'owner-a',
        itemId: item.id,
        attemptToken: apply.token,
        mutate: (_, _) async => testReceipt(item.id),
      );
    }
    final lower = session.items.first;
    final higher = session.items.last;

    Future<void> expectLowerBlocked() async {
      expect(
        await second.claimUndo(
          ownerUserId: 'owner-a',
          itemId: lower.id,
          leaseDuration: const Duration(minutes: 5),
        ),
        isNull,
      );
    }

    await expectLowerBlocked(); // higher applied
    var highAttempt = (await first.claimUndo(
      ownerUserId: 'owner-a',
      itemId: higher.id,
      leaseDuration: const Duration(minutes: 5),
    ))!;
    await first.markUndoFailed(
      ownerUserId: 'owner-a',
      itemId: higher.id,
      attemptToken: highAttempt.token,
      issue: RebalanceExecutionIssue(
        RebalanceExecutionIssueCode.undoUnavailable,
        'injected',
      ),
    );
    await expectLowerBlocked(); // higher undoFailed

    highAttempt = (await first.claimUndo(
      ownerUserId: 'owner-a',
      itemId: higher.id,
      leaseDuration: const Duration(minutes: 5),
    ))!;
    await expectLowerBlocked(); // higher unexpired undoing
    now = now.add(const Duration(minutes: 6));
    await expectLowerBlocked(); // higher expired undoing still blocks

    await db.customUpdate(
      'UPDATE rebalance_execution_items '
      "SET state = 'recoveryBlocked', failure_code = 'recoveryCorrupt', "
      "error = 'injected', attempt_token = NULL, lease_until_iso = NULL, "
      'recovery_was_applied = 1 WHERE id = ?',
      variables: [Variable.withString(higher.id)],
    );
    await expectLowerBlocked();
    final undoList = await first.listAppliedForUndo(
      ownerUserId: 'owner-a',
      sessionId: session.id,
    );
    expect(undoList.first.id, higher.id);
    expect(undoList.first.state, RebalanceExecutionItemState.recoveryBlocked);

    await db.customUpdate(
      'UPDATE rebalance_execution_items '
      "SET state = 'undone', failure_code = NULL, error = NULL, "
      'recovery_was_applied = 0 WHERE id = ?',
      variables: [Variable.withString(higher.id)],
    );
    expect(
      await second.claimUndo(
        ownerUserId: 'owner-a',
        itemId: lower.id,
        leaseDuration: const Duration(minutes: 5),
      ),
      isNotNull,
    );
  });

  test(
    'corrupt applied receipt becomes recoveryBlocked and cannot be claimed',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final store = RebalanceExecutionStore(db, clock: () => testNow);
      final ready = await _readyFirst(store);
      final claim = (await store.claimApply(
        ownerUserId: 'owner-a',
        itemId: ready.id,
        leaseDuration: const Duration(minutes: 5),
      ))!;
      await store.runApplyTransaction(
        ownerUserId: 'owner-a',
        itemId: ready.id,
        attemptToken: claim.token,
        mutate: (_, _) async => testReceipt(ready.id),
      );
      await db.customUpdate(
        "UPDATE rebalance_execution_items SET receipt_json = '{broken' "
        'WHERE id = ?',
        variables: [Variable.withString(ready.id)],
      );

      final blocked = await store.getItem(ownerUserId: 'owner-a', id: ready.id);
      expect(blocked?.state, RebalanceExecutionItemState.recoveryBlocked);
      expect(blocked?.recoveryWasApplied, isTrue);
      expect(blocked?.isEconomicallyApplied, isTrue);
      expect(blocked?.rawReceiptJson, '{broken');
      expect(
        await store.claimApply(
          ownerUserId: 'owner-a',
          itemId: ready.id,
          leaseDuration: const Duration(minutes: 5),
        ),
        isNull,
      );
      expect(
        await store.claimUndo(
          ownerUserId: 'owner-a',
          itemId: ready.id,
          leaseDuration: const Duration(minutes: 5),
        ),
        isNull,
      );
      final persisted = await db
          .customSelect(
            'SELECT state FROM rebalance_execution_items WHERE id = ?',
            variables: [Variable.withString(ready.id)],
          )
          .getSingle();
      expect(persisted.read<String>('state'), 'recoveryBlocked');
    },
  );

  test('stale recovery snapshot preserves a newer attempt token', () async {
    final db = _RecoveryRaceDatabase();
    addTearDown(db.close);
    final store = RebalanceExecutionStore(db, clock: () => testNow);
    final ready = await _readyFirst(store);
    await db.customUpdate(
      "UPDATE rebalance_execution_items SET request_json = '{broken', "
      'updated_at_iso = ? WHERE id = ?',
      variables: [
        Variable.withString(
          testNow.add(const Duration(minutes: 1)).toIso8601String(),
        ),
        Variable.withString(ready.id),
      ],
    );
    final replacement = RebalanceExecutionRequestCodec.encode(
      testRequest(ready.id),
    );
    final replacementLease = testNow.add(const Duration(minutes: 10));
    db.beforeRecoveryCas = (database) => database
        .customUpdate(
          'UPDATE rebalance_execution_items '
          "SET state = 'applying', request_json = ?, attempt_token = 'new-token', "
          'lease_until_iso = ?, updated_at_iso = ? WHERE id = ?',
          variables: [
            Variable.withString(replacement),
            Variable.withString(replacementLease.toIso8601String()),
            Variable.withString(
              testNow.add(const Duration(minutes: 2)).toIso8601String(),
            ),
            Variable.withString(ready.id),
          ],
        )
        .then((_) {});

    final item = await store.getItem(ownerUserId: 'owner-a', id: ready.id);

    expect(item?.state, RebalanceExecutionItemState.applying);
    expect(item?.attemptToken, 'new-token');
    expect(item?.leaseUntil, replacementLease);
    final persisted = await _rawItem(db, ready.id);
    expect(persisted.read<String>('state'), 'applying');
    expect(persisted.read<String>('attempt_token'), 'new-token');
  });

  test('stale recovery snapshot preserves a newer undone row', () async {
    final db = _RecoveryRaceDatabase();
    addTearDown(db.close);
    final store = RebalanceExecutionStore(db, clock: () => testNow);
    final ready = await _readyFirst(store);
    final claim = (await store.claimApply(
      ownerUserId: 'owner-a',
      itemId: ready.id,
      leaseDuration: const Duration(minutes: 5),
    ))!;
    await store.runApplyTransaction(
      ownerUserId: 'owner-a',
      itemId: ready.id,
      attemptToken: claim.token,
      mutate: (_, _) async => testReceipt(ready.id),
    );
    await db.customUpdate(
      "UPDATE rebalance_execution_items SET receipt_json = '{broken', "
      'updated_at_iso = ? WHERE id = ?',
      variables: [
        Variable.withString(
          testNow.add(const Duration(minutes: 1)).toIso8601String(),
        ),
        Variable.withString(ready.id),
      ],
    );
    final replacement = TradeMutationReceiptCodec.encode(testReceipt(ready.id));
    db.beforeRecoveryCas = (database) => database
        .customUpdate(
          'UPDATE rebalance_execution_items '
          "SET state = 'undone', receipt_json = ?, updated_at_iso = ? WHERE id = ?",
          variables: [
            Variable.withString(replacement),
            Variable.withString(
              testNow.add(const Duration(minutes: 2)).toIso8601String(),
            ),
            Variable.withString(ready.id),
          ],
        )
        .then((_) {});

    final item = await store.getItem(ownerUserId: 'owner-a', id: ready.id);

    expect(item?.state, RebalanceExecutionItemState.undone);
    expect(item?.receipt, isNotNull);
    expect(item?.recoveryWasApplied, isFalse);
    final persisted = await _rawItem(db, ready.id);
    expect(persisted.read<String>('state'), 'undone');
    expect(persisted.read<String>('receipt_json'), replacement);
  });

  test('stale recovery snapshot re-reads a suggestion-only change', () async {
    final db = _RecoveryRaceDatabase();
    addTearDown(db.close);
    final store = RebalanceExecutionStore(db, clock: () => testNow);
    final ready = await _readyFirst(store);
    await db.customUpdate(
      "UPDATE rebalance_execution_items SET request_json = '{broken' "
      'WHERE id = ?',
      variables: [Variable.withString(ready.id)],
    );
    final replacement = RebalanceSuggestionCodec.encode(
      testPlan(buyAmount: Decimal.fromInt(101)).trades.last,
    );
    db.beforeRecoveryCas = (database) => database
        .customUpdate(
          'UPDATE rebalance_execution_items SET suggestion_json = ? WHERE id = ?',
          variables: [
            Variable.withString(replacement),
            Variable.withString(ready.id),
          ],
        )
        .then((_) {});

    final item = await store.getItem(ownerUserId: 'owner-a', id: ready.id);

    expect(item?.state, RebalanceExecutionItemState.recoveryBlocked);
    expect(item?.suggestion.isBuy, isTrue);
    expect(item?.suggestion.amount.amount, Decimal.fromInt(101));
    expect(db.recoveryCasCount, 2);
    final persisted = await _rawItem(db, ready.id);
    expect(persisted.read<String>('state'), 'recoveryBlocked');
    expect(persisted.read<String>('suggestion_json'), replacement);
  });

  test('stale recovery snapshot re-checks an issue-only change', () async {
    final db = _RecoveryRaceDatabase();
    addTearDown(db.close);
    final store = RebalanceExecutionStore(db, clock: () => testNow);
    final ready = await _readyFirst(store);
    await db.customUpdate(
      "UPDATE rebalance_execution_items SET request_json = '{broken' "
      'WHERE id = ?',
      variables: [Variable.withString(ready.id)],
    );
    late final String latestError;
    try {
      RebalanceExecutionRequestCodec.decode('{broken');
      fail('corrupt request must fail');
    } on RebalanceExecutionCodecError catch (error) {
      latestError = error.toString();
    }
    db.beforeRecoveryCas = (database) => database
        .customUpdate(
          "UPDATE rebalance_execution_items SET state = 'applyFailed', "
          "failure_code = 'internal', error = ? WHERE id = ?",
          variables: [
            Variable.withString(latestError),
            Variable.withString(ready.id),
          ],
        )
        .then((_) {});

    final item = await store.getItem(ownerUserId: 'owner-a', id: ready.id);

    expect(item?.state, RebalanceExecutionItemState.recoveryBlocked);
    expect(item?.issue?.debugMessage, latestError);
    expect(db.recoveryCasCount, 2);
    final persisted = await _rawItem(db, ready.id);
    expect(persisted.read<String>('state'), 'recoveryBlocked');
    expect(persisted.read<String>('error'), latestError);
  });

  test('recovery diagnostics are bounded before persistence', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = RebalanceExecutionStore(db, clock: () => testNow);
    final ready = await _readyFirst(store);
    final envelope = jsonDecode(ready.rawRequestJson!) as Map<String, Object?>;
    final payload = envelope['payload']! as Map<String, Object?>;
    for (var index = 0; index < 160; index++) {
      payload['unexpected_field_${index.toString().padLeft(3, '0')}'] = index;
    }
    await db.customUpdate(
      'UPDATE rebalance_execution_items SET request_json = ? WHERE id = ?',
      variables: [
        Variable.withString(jsonEncode(envelope)),
        Variable.withString(ready.id),
      ],
    );

    final blocked = await store.getItem(ownerUserId: 'owner-a', id: ready.id);

    expect(blocked?.state, RebalanceExecutionItemState.recoveryBlocked);
    final persisted = await _rawItem(db, ready.id);
    expect(persisted.read<String>('error'), hasLength(512));
  });

  test('corrupt suggestion fails closed without any recovery write', () async {
    final db = _RecoveryRaceDatabase();
    addTearDown(db.close);
    final store = RebalanceExecutionStore(db, clock: () => testNow);
    final ready = await _readyFirst(store);
    await db.customUpdate(
      "UPDATE rebalance_execution_items SET suggestion_json = '{broken' "
      'WHERE id = ?',
      variables: [Variable.withString(ready.id)],
    );
    final before = await _rawItem(db, ready.id);

    await expectLater(
      store.getItem(ownerUserId: 'owner-a', id: ready.id),
      throwsA(isA<RebalanceExecutionCodecError>()),
    );

    final after = await _rawItem(db, ready.id);
    expect(db.recoveryCasCount, 0);
    expect(after.read<String>('state'), before.read<String>('state'));
    expect(
      after.read<String>('suggestion_json'),
      before.read<String>('suggestion_json'),
    );
    expect(
      after.read<String>('request_json'),
      before.read<String>('request_json'),
    );
    expect(after.read<String?>('error'), before.read<String?>('error'));
    expect(
      after.read<int>('recovery_was_applied'),
      before.read<int>('recovery_was_applied'),
    );
    expect(
      after.read<String>('updated_at_iso'),
      before.read<String>('updated_at_iso'),
    );
  });

  test(
    'owner isolation and archived sessions fail closed for actions',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final store = RebalanceExecutionStore(db, clock: () => testNow);
      final ready = await _readyFirst(store);

      expect(await store.getActive('owner-b'), isNull);
      expect(await store.getItem(ownerUserId: 'owner-b', id: ready.id), isNull);
      await expectLater(
        store.claimApply(
          ownerUserId: 'owner-b',
          itemId: ready.id,
          leaseDuration: const Duration(minutes: 5),
        ),
        throwsA(isA<RebalanceExecutionNotFound>()),
      );

      await store.archive(ownerUserId: 'owner-a', sessionId: ready.sessionId);
      await expectLater(
        store.claimApply(
          ownerUserId: 'owner-a',
          itemId: ready.id,
          leaseDuration: const Duration(minutes: 5),
        ),
        throwsA(isA<RebalanceExecutionConflict>()),
      );
      await expectLater(
        store.saveRequest(
          ownerUserId: 'owner-a',
          expected: ready,
          request: testRequest(ready.id),
        ),
        throwsA(isA<RebalanceExecutionConflict>()),
      );
    },
  );

  group('store-owned atomic mutation transactions', () {
    test('apply callback write and finalization commit together', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final store = RebalanceExecutionStore(db, clock: () => testNow);
      await _createProbeTable(db);
      final ready = await _readyFirst(store);
      final claim = (await store.claimApply(
        ownerUserId: 'owner-a',
        itemId: ready.id,
        leaseDuration: const Duration(minutes: 5),
      ))!;

      final applied = await store.runApplyTransaction(
        ownerUserId: 'owner-a',
        itemId: ready.id,
        attemptToken: claim.token,
        mutate: (_, claimed) async {
          expect(claimed.id, ready.id);
          expect(claimed.state, RebalanceExecutionItemState.applying);
          expect(claimed.attemptToken, claim.token);
          expect(claimed.request, isNotNull);
          await db.customInsert(
            "INSERT INTO rebalance_tx_probe VALUES ('apply', 'written')",
          );
          return testReceipt(ready.id);
        },
      );

      expect(applied.state, RebalanceExecutionItemState.applied);
      expect(applied.receipt, isNotNull);
      expect((await _probeRows(db)).single.read<String>('value'), 'written');
    });

    test(
      'apply callback failure rolls back writes and preserves claim',
      () async {
        final db = makeTestDatabase();
        addTearDown(db.close);
        final store = RebalanceExecutionStore(db, clock: () => testNow);
        await _createProbeTable(db);
        final ready = await _readyFirst(store);
        final claim = (await store.claimApply(
          ownerUserId: 'owner-a',
          itemId: ready.id,
          leaseDuration: const Duration(minutes: 5),
        ))!;
        final before = await _rawItem(db, ready.id);

        await expectLater(
          store.runApplyTransaction(
            ownerUserId: 'owner-a',
            itemId: ready.id,
            attemptToken: claim.token,
            mutate: (_, _) async {
              await db.customInsert(
                "INSERT INTO rebalance_tx_probe VALUES ('callback', 'written')",
              );
              throw StateError('injected mutation failure');
            },
          ),
          throwsA(isA<StateError>()),
        );
        final after = await _rawItem(db, ready.id);
        expect(await _probeRows(db), isEmpty);
        expect(after.read<String>('state'), before.read<String>('state'));
        expect(
          after.read<String>('attempt_token'),
          before.read<String>('attempt_token'),
        );
        expect(
          after.read<String>('lease_until_iso'),
          before.read<String>('lease_until_iso'),
        );
        expect(after.read<String?>('receipt_json'), isNull);
      },
    );

    test(
      'invalid receipt codec, owner, and transaction roll back writes',
      () async {
        final db = makeTestDatabase();
        addTearDown(db.close);
        final store = RebalanceExecutionStore(db, clock: () => testNow);
        await _createProbeTable(db);
        final ready = await _readyFirst(store);
        final claim = (await store.claimApply(
          ownerUserId: 'owner-a',
          itemId: ready.id,
          leaseDuration: const Duration(minutes: 5),
        ))!;

        await expectLater(
          store.runApplyTransaction(
            ownerUserId: 'owner-a',
            itemId: ready.id,
            attemptToken: claim.token,
            mutate: (_, _) async {
              await db.customInsert(
                "INSERT INTO rebalance_tx_probe VALUES ('codec', 'written')",
              );
              return testReceipt(ready.id, entryDate: DateTime(2026, 7, 10));
            },
          ),
          throwsA(isA<RebalanceExecutionCodecError>()),
        );
        await expectLater(
          store.runApplyTransaction(
            ownerUserId: 'owner-a',
            itemId: ready.id,
            attemptToken: claim.token,
            mutate: (_, _) async {
              await db.customInsert(
                "INSERT INTO rebalance_tx_probe VALUES ('owner', 'written')",
              );
              return testReceipt(ready.id, owner: 'owner-b');
            },
          ),
          throwsA(isA<RebalanceExecutionConflict>()),
        );
        await expectLater(
          store.runApplyTransaction(
            ownerUserId: 'owner-a',
            itemId: ready.id,
            attemptToken: claim.token,
            mutate: (_, _) async {
              await db.customInsert(
                "INSERT INTO rebalance_tx_probe VALUES ('tx', 'written')",
              );
              return testReceipt('different-transaction');
            },
          ),
          throwsA(isA<RebalanceExecutionInvariantError>()),
        );

        expect(await _probeRows(db), isEmpty);
        final item = await store.getItem(ownerUserId: 'owner-a', id: ready.id);
        expect(item?.state, RebalanceExecutionItemState.applying);
        expect(item?.attemptToken, claim.token);
        expect(item?.receipt, isNull);
      },
    );

    test(
      'lease expiry at final apply CAS rolls back callback writes',
      () async {
        final db = makeTestDatabase();
        addTearDown(db.close);
        var now = testNow;
        final store = RebalanceExecutionStore(db, clock: () => now);
        await _createProbeTable(db);
        final ready = await _readyFirst(store);
        final claim = (await store.claimApply(
          ownerUserId: 'owner-a',
          itemId: ready.id,
          leaseDuration: const Duration(minutes: 5),
        ))!;

        await expectLater(
          store.runApplyTransaction(
            ownerUserId: 'owner-a',
            itemId: ready.id,
            attemptToken: claim.token,
            mutate: (_, _) async {
              await db.customInsert(
                "INSERT INTO rebalance_tx_probe VALUES ('expired', 'written')",
              );
              now = now.add(const Duration(minutes: 6));
              return testReceipt(ready.id);
            },
          ),
          throwsA(isA<RebalanceStaleAttempt>()),
        );

        expect(await _probeRows(db), isEmpty);
        final item = await store.getItem(ownerUserId: 'owner-a', id: ready.id);
        expect(item?.state, RebalanceExecutionItemState.applying);
        expect(item?.attemptToken, claim.token);
        expect(item?.receipt, isNull);
      },
    );

    test(
      'undo failure and stale final CAS roll back reversal writes',
      () async {
        final db = makeTestDatabase();
        addTearDown(db.close);
        var now = testNow;
        final store = RebalanceExecutionStore(db, clock: () => now);
        await _createProbeTable(db);
        final ready = await _readyFirst(store);
        final apply = (await store.claimApply(
          ownerUserId: 'owner-a',
          itemId: ready.id,
          leaseDuration: const Duration(minutes: 5),
        ))!;
        await store.runApplyTransaction(
          ownerUserId: 'owner-a',
          itemId: ready.id,
          attemptToken: apply.token,
          mutate: (_, _) async {
            await db.customInsert(
              "INSERT INTO rebalance_tx_probe VALUES ('effect', 'applied')",
            );
            return testReceipt(ready.id);
          },
        );
        final undo = (await store.claimUndo(
          ownerUserId: 'owner-a',
          itemId: ready.id,
          leaseDuration: const Duration(minutes: 5),
        ))!;

        await expectLater(
          store.runUndoTransaction(
            ownerUserId: 'owner-a',
            itemId: ready.id,
            attemptToken: undo.token,
            mutate: (_, _) async {
              await db.customUpdate(
                "DELETE FROM rebalance_tx_probe WHERE id = 'effect'",
              );
              throw StateError('injected reversal failure');
            },
          ),
          throwsA(isA<StateError>()),
        );
        expect((await _probeRows(db)).single.read<String>('value'), 'applied');
        expect(
          (await store.getItem(ownerUserId: 'owner-a', id: ready.id))?.state,
          RebalanceExecutionItemState.undoing,
        );

        await expectLater(
          store.runUndoTransaction(
            ownerUserId: 'owner-a',
            itemId: ready.id,
            attemptToken: undo.token,
            mutate: (_, claimed) async {
              expect(claimed.receipt, isNotNull);
              expect(claimed.appliedSequence, 1);
              await db.customUpdate(
                "DELETE FROM rebalance_tx_probe WHERE id = 'effect'",
              );
              now = now.add(const Duration(minutes: 6));
            },
          ),
          throwsA(isA<RebalanceStaleAttempt>()),
        );
        expect((await _probeRows(db)).single.read<String>('value'), 'applied');
        final item = await store.getItem(ownerUserId: 'owner-a', id: ready.id);
        expect(item?.state, RebalanceExecutionItemState.undoing);
        expect(item?.attemptToken, undo.token);
        expect(item?.receipt, isNotNull);
      },
    );

    test('undo final CAS binds exact request and receipt snapshots', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final store = RebalanceExecutionStore(db, clock: () => testNow);
      await _createProbeTable(db);
      final ready = await _readyFirst(store);
      final apply = (await store.claimApply(
        ownerUserId: 'owner-a',
        itemId: ready.id,
        leaseDuration: const Duration(minutes: 5),
      ))!;
      await store.runApplyTransaction(
        ownerUserId: 'owner-a',
        itemId: ready.id,
        attemptToken: apply.token,
        mutate: (_, _) async {
          await db.customInsert(
            "INSERT INTO rebalance_tx_probe VALUES ('effect', 'applied')",
          );
          return testReceipt(ready.id);
        },
      );
      final undo = (await store.claimUndo(
        ownerUserId: 'owner-a',
        itemId: ready.id,
        leaseDuration: const Duration(minutes: 5),
      ))!;
      final before = await _rawItem(db, ready.id);
      final replacementRequest = RebalanceExecutionRequestCodec.encode(
        testRequest(ready.id, tradeDate: testNow.add(const Duration(days: 1))),
      );

      await expectLater(
        store.runUndoTransaction(
          ownerUserId: 'owner-a',
          itemId: ready.id,
          attemptToken: undo.token,
          mutate: (_, _) async {
            await db.customUpdate(
              "DELETE FROM rebalance_tx_probe WHERE id = 'effect'",
            );
            await db.customUpdate(
              'UPDATE rebalance_execution_items SET request_json = ? '
              'WHERE id = ?',
              variables: [
                Variable.withString(replacementRequest),
                Variable.withString(ready.id),
              ],
            );
          },
        ),
        throwsA(isA<RebalanceStaleAttempt>()),
      );
      var after = await _rawItem(db, ready.id);
      expect((await _probeRows(db)).single.read<String>('value'), 'applied');
      expect(
        after.read<String>('request_json'),
        before.read<String>('request_json'),
      );
      expect(
        after.read<String>('receipt_json'),
        before.read<String>('receipt_json'),
      );

      final replacementReceipt = TradeMutationReceiptCodec.encode(
        testReceipt(ready.id, entryDate: testNow.add(const Duration(days: 1))),
      );
      await expectLater(
        store.runUndoTransaction(
          ownerUserId: 'owner-a',
          itemId: ready.id,
          attemptToken: undo.token,
          mutate: (_, _) async {
            await db.customUpdate(
              "DELETE FROM rebalance_tx_probe WHERE id = 'effect'",
            );
            await db.customUpdate(
              'UPDATE rebalance_execution_items SET receipt_json = ? '
              'WHERE id = ?',
              variables: [
                Variable.withString(replacementReceipt),
                Variable.withString(ready.id),
              ],
            );
          },
        ),
        throwsA(isA<RebalanceStaleAttempt>()),
      );
      after = await _rawItem(db, ready.id);
      expect((await _probeRows(db)).single.read<String>('value'), 'applied');
      expect(after.read<String>('state'), 'undoing');
      expect(after.read<String>('attempt_token'), undo.token);
      expect(
        after.read<String>('request_json'),
        before.read<String>('request_json'),
      );
      expect(
        after.read<String>('receipt_json'),
        before.read<String>('receipt_json'),
      );
    });

    test('undo final SQL failure rolls back reversal and execution', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final store = RebalanceExecutionStore(db, clock: () => testNow);
      await _createProbeTable(db);
      final ready = await _readyFirst(store);
      final apply = (await store.claimApply(
        ownerUserId: 'owner-a',
        itemId: ready.id,
        leaseDuration: const Duration(minutes: 5),
      ))!;
      await store.runApplyTransaction(
        ownerUserId: 'owner-a',
        itemId: ready.id,
        attemptToken: apply.token,
        mutate: (_, _) async {
          await db.customInsert(
            "INSERT INTO rebalance_tx_probe VALUES ('effect', 'applied')",
          );
          return testReceipt(ready.id);
        },
      );
      final undo = (await store.claimUndo(
        ownerUserId: 'owner-a',
        itemId: ready.id,
        leaseDuration: const Duration(minutes: 5),
      ))!;
      final before = await _rawItem(db, ready.id);
      await db.customStatement('''
      CREATE TRIGGER reject_rebalance_undo
      BEFORE UPDATE OF state ON rebalance_execution_items
      WHEN OLD.state = 'undoing' AND NEW.state = 'undone'
      BEGIN SELECT RAISE(ABORT, 'undo constraint'); END
    ''');

      await expectLater(
        store.runUndoTransaction(
          ownerUserId: 'owner-a',
          itemId: ready.id,
          attemptToken: undo.token,
          mutate: (_, _) async {
            await db.customUpdate(
              "DELETE FROM rebalance_tx_probe WHERE id = 'effect'",
            );
          },
        ),
        throwsA(anything),
      );

      final after = await _rawItem(db, ready.id);
      expect((await _probeRows(db)).single.read<String>('value'), 'applied');
      expect(after.read<String>('state'), before.read<String>('state'));
      expect(
        after.read<String>('attempt_token'),
        before.read<String>('attempt_token'),
      );
      expect(
        after.read<String>('request_json'),
        before.read<String>('request_json'),
      );
      expect(
        after.read<String>('receipt_json'),
        before.read<String>('receipt_json'),
      );
    });

    test('apply final SQL failure rolls back callback writes', () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final store = RebalanceExecutionStore(db, clock: () => testNow);
      await _createProbeTable(db);
      final ready = await _readyFirst(store);
      final claim = (await store.claimApply(
        ownerUserId: 'owner-a',
        itemId: ready.id,
        leaseDuration: const Duration(minutes: 5),
      ))!;

      await db.customStatement('''
      CREATE TRIGGER reject_rebalance_receipt
      BEFORE UPDATE OF receipt_json ON rebalance_execution_items
      WHEN NEW.receipt_json IS NOT NULL
      BEGIN SELECT RAISE(ABORT, 'receipt constraint'); END
    ''');
      await expectLater(
        store.runApplyTransaction(
          ownerUserId: 'owner-a',
          itemId: ready.id,
          attemptToken: claim.token,
          mutate: (_, _) async {
            await db.customInsert(
              "INSERT INTO rebalance_tx_probe VALUES ('sql', 'written')",
            );
            return testReceipt(ready.id);
          },
        ),
        throwsA(anything),
      );
      expect(await _probeRows(db), isEmpty);
      expect(
        (await store.getItem(ownerUserId: 'owner-a', id: ready.id))?.state,
        RebalanceExecutionItemState.applying,
      );
    });
  });
}

Future<void> _createProbeTable(AppDatabase db) => db.customStatement(
  'CREATE TABLE rebalance_tx_probe '
  '(id TEXT PRIMARY KEY, value TEXT NOT NULL)',
);

Future<List<QueryRow>> _probeRows(AppDatabase db) =>
    db.customSelect('SELECT * FROM rebalance_tx_probe ORDER BY id').get();

Future<RebalanceExecutionItem> _readyFirst(
  RebalanceExecutionStore store,
) async {
  final session = await store.createOrResume(
    ownerUserId: 'owner-a',
    plan: testPlan(),
  );
  final item = session.items.first;
  return store.saveRequest(
    ownerUserId: 'owner-a',
    expected: item,
    request: testRequest(item.id),
  );
}

Future<QueryRow> _rawItem(AppDatabase db, String id) => db
    .customSelect(
      'SELECT * FROM rebalance_execution_items WHERE id = ?',
      variables: [Variable.withString(id)],
    )
    .getSingle();

final class _RecoveryRaceDatabase extends AppDatabase {
  _RecoveryRaceDatabase()
    : super(DatabaseConnection(NativeDatabase.memory(logStatements: false)));

  Future<void> Function(_RecoveryRaceDatabase database)? beforeRecoveryCas;
  Future<void> Function(_RecoveryRaceDatabase database)? beforeFinalizeCas;
  int recoveryCasCount = 0;
  bool _insideRecoveryHook = false;

  @override
  Future<int> customUpdate(
    String query, {
    List<Variable> variables = const [],
    Set<ResultSetImplementation<dynamic, dynamic>>? updates,
    UpdateKind? updateKind,
  }) async {
    final isRecoveryCas = query.contains("SET state = 'recoveryBlocked'");
    if (isRecoveryCas) recoveryCasCount++;
    final hook = beforeRecoveryCas;
    if (!_insideRecoveryHook && hook != null && isRecoveryCas) {
      beforeRecoveryCas = null;
      _insideRecoveryHook = true;
      try {
        await hook(this);
      } finally {
        _insideRecoveryHook = false;
      }
    }
    final finalizeHook = beforeFinalizeCas;
    if (!_insideRecoveryHook &&
        finalizeHook != null &&
        query.contains("SET state = 'applied'")) {
      beforeFinalizeCas = null;
      _insideRecoveryHook = true;
      try {
        await finalizeHook(this);
      } finally {
        _insideRecoveryHook = false;
      }
    }
    return super.customUpdate(
      query,
      variables: variables,
      updates: updates,
      updateKind: updateKind,
    );
  }
}
