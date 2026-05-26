// Multi-device sync E2E suite (sync v2, row-state).
//
// These tests wire a v2 `SyncEngine` per `device_id` against a shared
// in-memory backend (`FakeSyncApiClient`) and run the production
// `RowApplier` against a real in-memory Drift DB per device. They assert
// end-to-end convergence of the row-state protocol — first sync, offline
// batch replay, per-row LWW, and tombstones — across every layer the data
// passes through: dirty pointer → push → server LWW + seq → pull → applier.

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/errors.dart';
import 'package:naviwealth/core/sync/hlc.dart';

import '_cluster.dart';

Map<String, Object?> _account({required String name, String currency = 'USD'}) {
  return <String, Object?>{
    'type': 'cash',
    'name': name,
    'currency': currency,
    'category': 'asset',
  };
}

Map<String, Object?> _journalEntry({required String narration}) {
  return <String, Object?>{
    // date stored as epoch-seconds INTEGER.
    'date': 1_777_000_000,
    'narration': narration,
  };
}

void main() {
  group('multi-device sync E2E (v2)', () {
    // Scenario 1: single-device write becomes visible on the peer.
    test(
      'single-device write becomes visible on a peer within one cycle',
      () async {
        final cluster = SyncCluster();
        addTearDown(cluster.disposeAll);
        final iphone = cluster.addDevice(
          'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        );
        final mac = cluster.addDevice('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');

        await iphone.writeRow(
          table: 'accounts',
          rowId: 'A1',
          columns: _account(name: 'Cash'),
        );

        cluster.advanceAllClocks(const Duration(seconds: 30));
        await cluster.syncAll();

        expect(await mac.isVisible('accounts', 'A1'), isTrue);
        final macRow = await mac.lookup('accounts', 'A1');
        expect(macRow!['name'], 'Cash');
        expect(await cluster.isConverged('accounts'), isTrue);
      },
    );

    // Scenario 2: offline batch edit replays and reaches the peer.
    test('offline batch edit replays and reaches the peer', () async {
      final cluster = SyncCluster();
      addTearDown(cluster.disposeAll);
      final iphone = cluster.addDevice('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
      final mac = cluster.addDevice('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');

      iphone.offline = true;

      const minute = Duration(minutes: 1);
      await iphone.writeRow(
        table: 'accounts',
        rowId: 'A1',
        columns: _account(name: 'Wallet'),
      );
      iphone.advanceClock(minute);
      await iphone.writeRow(
        table: 'accounts',
        rowId: 'A2',
        columns: _account(name: 'Bank'),
      );
      iphone.advanceClock(minute);
      await iphone.writeRow(
        table: 'accounts',
        rowId: 'A3',
        columns: _account(name: 'Brokerage'),
      );
      iphone.advanceClock(minute);
      // Update A1.
      await iphone.writeRow(
        table: 'accounts',
        rowId: 'A1',
        columns: _account(name: 'Wallet (cash)'),
      );
      iphone.advanceClock(minute);
      // Delete A3.
      await iphone.writeRow(
        table: 'accounts',
        rowId: 'A3',
        columns: _account(name: 'Brokerage'),
        deleted: true,
      );

      expect(await iphone.pendingDepth(), 5, reason: 'five ops queued offline');

      // Reconnect.
      iphone.offline = false;
      cluster.advanceAllClocks(const Duration(seconds: 30));
      await cluster.syncAll();

      expect(
        await iphone.pendingDepth(),
        0,
        reason: 'outbox drained on reconnect',
      );

      final macA1 = await mac.lookup('accounts', 'A1');
      final macA2 = await mac.lookup('accounts', 'A2');
      expect(macA1!['name'], 'Wallet (cash)');
      expect(macA2!['name'], 'Bank');
      expect(
        await mac.isVisible('accounts', 'A3'),
        isFalse,
        reason: 'tombstone propagated to the peer',
      );
      expect(await cluster.isConverged('accounts'), isTrue);
    });

    // Scenario 3: concurrent same-row writes converge under LWW.
    test('concurrent same-row writes converge to a single value', () async {
      final cluster = SyncCluster();
      addTearDown(cluster.disposeAll);
      final iphone = cluster.addDevice('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
      final web = cluster.addDevice('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');

      // Both devices already know about A1.
      await iphone.writeRow(
        table: 'accounts',
        rowId: 'A1',
        columns: _account(name: 'Cash'),
      );
      cluster.advanceAllClocks(const Duration(seconds: 30));
      await cluster.syncAll();
      expect((await web.lookup('accounts', 'A1'))!['name'], 'Cash');

      // Both edit A1 before either has synced. The web write happens later
      // on the wall clock, so its HLC wins LWW.
      iphone.advanceClock(const Duration(seconds: 1));
      await iphone.writeRow(
        table: 'accounts',
        rowId: 'A1',
        columns: _account(name: 'Cash (iPhone)'),
      );
      web.advanceClock(const Duration(seconds: 2));
      await web.writeRow(
        table: 'accounts',
        rowId: 'A1',
        columns: _account(name: 'Cash (Web)'),
      );

      cluster.advanceAllClocks(const Duration(seconds: 30));
      await cluster.syncAll();

      final iphoneName = (await iphone.lookup('accounts', 'A1'))!['name'];
      final webName = (await web.lookup('accounts', 'A1'))!['name'];
      expect(
        iphoneName,
        equals(webName),
        reason: 'LWW must converge to a single value across devices',
      );
      expect({'Cash (iPhone)', 'Cash (Web)'}, contains(iphoneName));
      expect(await cluster.isConverged('accounts'), isTrue);
    });

    // Scenario 4: a tombstone hides on the peer and does not resurrect.
    test('tombstone hides on the peer and never resurrects', () async {
      final cluster = SyncCluster();
      addTearDown(cluster.disposeAll);
      final iphone = cluster.addDevice('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
      final mac = cluster.addDevice('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');

      await iphone.writeRow(
        table: 'accounts',
        rowId: 'A1',
        columns: _account(name: 'Cash'),
      );
      cluster.advanceAllClocks(const Duration(seconds: 30));
      await cluster.syncAll();
      expect(await mac.visibleIds('accounts'), ['A1']);

      // iPhone deletes; Mac picks it up via pull.
      iphone.advanceClock(const Duration(minutes: 1));
      await iphone.writeRow(
        table: 'accounts',
        rowId: 'A1',
        columns: _account(name: 'Cash'),
        deleted: true,
      );
      cluster.advanceAllClocks(const Duration(seconds: 30));
      await cluster.syncAll();

      expect(await mac.isVisible('accounts', 'A1'), isFalse);
      expect(await mac.visibleIds('accounts'), isEmpty);

      // Extra cycles must not revive the row.
      for (var i = 0; i < 3; i++) {
        cluster.advanceAllClocks(const Duration(seconds: 30));
        await cluster.syncAll();
        expect(
          await mac.visibleIds('accounts'),
          isEmpty,
          reason: 'cycle $i: row still tombstoned',
        );
        expect(await iphone.visibleIds('accounts'), isEmpty);
      }
      expect(await cluster.isConverged('accounts'), isTrue);
    });

    // Scenario 5: a large backlog drains across paged push/pull without loss.
    test('large backlog drains across paged push/pull without loss', () async {
      final cluster = SyncCluster();
      addTearDown(cluster.disposeAll);
      final iphone = cluster.addDevice('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
      final mac = cluster.addDevice('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');

      const total = 600;
      iphone.offline = true;
      for (var i = 0; i < total; i++) {
        await iphone.writeRow(
          table: 'journal_entries',
          rowId: 'JE${i.toString().padLeft(4, '0')}',
          columns: _journalEntry(narration: 'bulk-$i'),
        );
        if (i % 50 == 49) {
          iphone.advanceClock(const Duration(seconds: 1));
        }
      }
      expect(await iphone.pendingDepth(), total);

      iphone.offline = false;
      // Drive enough cycles to drain at the 500-row batch cap.
      for (var c = 0; c < 4; c++) {
        cluster.advanceAllClocks(const Duration(seconds: 30));
        await cluster.syncAll();
      }

      expect(await iphone.pendingDepth(), 0, reason: 'all rows acknowledged');
      expect(
        (await mac.visibleIds('journal_entries')).length,
        total,
        reason: 'peer materialised every row exactly once',
      );

      // Push batches must respect the 500-row cap.
      for (final batch in cluster.api.pushedBatches) {
        expect(
          batch.length,
          lessThanOrEqualTo(500),
          reason: 'no push batch over the spec cap',
        );
      }
    });

    // E2E-3 (phase1 P1-G): a row tombstoned and then recreated with the
    // same id surfaces as the new version on peers — the tombstone must
    // not block the resurrection write.
    test(
      'delete-then-recreate same id: peer materialises the new row',
      () async {
        final cluster = SyncCluster();
        addTearDown(cluster.disposeAll);
        final iphone = cluster.addDevice(
          'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        );
        final mac = cluster.addDevice('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');

        await iphone.writeRow(
          table: 'accounts',
          rowId: 'A1',
          columns: _account(name: 'Cash'),
        );
        cluster.advanceAllClocks(const Duration(seconds: 30));
        await cluster.syncAll();
        expect((await mac.lookup('accounts', 'A1'))!['name'], 'Cash');

        // Tombstone, propagate.
        iphone.advanceClock(const Duration(minutes: 1));
        await iphone.writeRow(
          table: 'accounts',
          rowId: 'A1',
          columns: _account(name: 'Cash'),
          deleted: true,
        );
        cluster.advanceAllClocks(const Duration(seconds: 30));
        await cluster.syncAll();
        expect(await mac.isVisible('accounts', 'A1'), isFalse);

        // Recreate with same id, newer HLC.
        iphone.advanceClock(const Duration(minutes: 1));
        await iphone.writeRow(
          table: 'accounts',
          rowId: 'A1',
          columns: _account(name: 'Cash (reopened)'),
        );
        cluster.advanceAllClocks(const Duration(seconds: 30));
        await cluster.syncAll();

        expect(await mac.isVisible('accounts', 'A1'), isTrue);
        final macRow = await mac.lookup('accounts', 'A1');
        expect(macRow!['name'], 'Cash (reopened)');
        expect(macRow['deleted_at'], isNull);
        expect(await cluster.isConverged('accounts'), isTrue);
      },
    );

    // E2E-4 (phase1 P1-G): physical wall clock rewinds (device time was
    // wrong, or NTP corrects backward) but HLC stays strictly monotonic,
    // so a later write still wins LWW against an earlier one.
    test(
      'physical clock rewind: HLC stays monotonic and LWW resolves it',
      () async {
        final cluster = SyncCluster();
        addTearDown(cluster.disposeAll);
        final iphone = cluster.addDevice(
          'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        );
        final mac = cluster.addDevice('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');

        // First write at the initial wall clock.
        await iphone.writeRow(
          table: 'accounts',
          rowId: 'A1',
          columns: _account(name: 'before-rewind'),
        );
        final hlc1 = Hlc.parse(
          (await iphone.lookup('accounts', 'A1'))!['hlc']! as String,
        );

        // Rewind the wall clock — way back, ten minutes.
        iphone.advanceClock(const Duration(minutes: -10));

        // Second write must still produce an HLC strictly greater than the
        // first, despite the wall clock having gone backward.
        await iphone.writeRow(
          table: 'accounts',
          rowId: 'A1',
          columns: _account(name: 'after-rewind'),
        );
        final hlc2 = Hlc.parse(
          (await iphone.lookup('accounts', 'A1'))!['hlc']! as String,
        );

        expect(
          hlc2 > hlc1,
          isTrue,
          reason: 'HLC must be monotonic across a backward wall-clock jump',
        );

        // Both devices must converge on the second write.
        cluster.advanceAllClocks(const Duration(seconds: 30));
        await cluster.syncAll();
        expect((await mac.lookup('accounts', 'A1'))!['name'], 'after-rewind');
        expect(await cluster.isConverged('accounts'), isTrue);
      },
    );

    // E2E-5 (phase1 P1-G): a transient push failure must not drop ops;
    // the outbox retries on the next cycle and the peer eventually sees
    // the write.
    test(
      'transient push failure: outbox survives and retries to convergence',
      () async {
        final cluster = SyncCluster();
        addTearDown(cluster.disposeAll);
        final iphone = cluster.addDevice(
          'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        );
        final mac = cluster.addDevice('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');

        await iphone.writeRow(
          table: 'accounts',
          rowId: 'A1',
          columns: _account(name: 'Cash'),
        );
        await iphone.writeRow(
          table: 'accounts',
          rowId: 'A2',
          columns: _account(name: 'Bank'),
        );
        expect(await iphone.pendingDepth(), 2);

        // Script one transient server failure ahead of the next sync. The
        // outbox must not consume the dirty pointer when the call throws.
        cluster.api.programmedResponses.add(
          SyncException(SyncErrorKind.network, message: 'transient'),
        );

        cluster.advanceAllClocks(const Duration(seconds: 30));
        // Run iphone's cycle manually so we can observe the failure.
        try {
          await iphone.tickSync();
        } on SyncException catch (_) {
          // Expected — the cycle surfaces the network error.
        }
        expect(
          await iphone.pendingDepth(),
          2,
          reason: 'outbox must not lose ops on a transient push failure',
        );
        expect(await mac.isVisible('accounts', 'A1'), isFalse);

        // Next cycle succeeds — outbox drains and the peer materialises.
        cluster.advanceAllClocks(const Duration(seconds: 30));
        await cluster.syncAll();

        expect(await iphone.pendingDepth(), 0);
        expect((await mac.lookup('accounts', 'A1'))!['name'], 'Cash');
        expect((await mac.lookup('accounts', 'A2'))!['name'], 'Bank');
        expect(await cluster.isConverged('accounts'), isTrue);
      },
    );
  });
}
