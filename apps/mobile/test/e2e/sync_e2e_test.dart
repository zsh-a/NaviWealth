// Multi-device sync E2E suite (FIR-61).
//
// These tests wire `SyncEngine` instances for several `device_id`s against a
// shared in-memory backend (`FakeSyncApiClient`) and an LWW materialiser per
// device. They assert end-to-end convergence properties of the protocol —
// not unit-level encoding — so the closest analogue is the protocol-level
// tests in `docs/sync-protocol-tests.md` §F (offline) / §E (LWW) / §H
// (tombstones), exercised across every layer the data passes through:
// outbox → push → server stamp → pull → applier.
//
// Run on the existing `mobile` workflow (no extra CI wiring needed).

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/op.dart';

import '_cluster.dart';

void main() {
  group('multi-device sync E2E', () {
    // Scenario 1 (issue: 单端写入 → 其它端 30s 内可见).
    test(
      'single-device write becomes visible on peer within one cycle',
      () async {
        final cluster = SyncCluster();
        final iphone = cluster.addDevice(
          'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        );
        final mac = cluster.addDevice('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');

        await iphone.writeRow(
          table: 'accounts',
          rowId: 'A1',
          opType: OpType.insert,
          fieldsDiff: {'id': 'A1', 'name': 'Cash', 'currency': 'USD'},
        );

        // 30 s polling cadence (docs/sync-protocol.md §7.3).
        cluster.advanceAllClocks(const Duration(seconds: 30));
        await cluster.syncAll();

        final macRow = mac.applier.lookup('accounts', 'A1');
        expect(
          macRow,
          isNotNull,
          reason: 'peer should observe foreign insert after one sync cycle',
        );
        expect(macRow!.payload['name'], 'Cash');
        expect(macRow.isDeleted, isFalse);
        expect(
          cluster.isConverged(),
          isTrue,
          reason: cluster.describeDivergence(iphone, mac),
        );
      },
    );

    // Scenario 2 (issue: 离线编辑 → 上线后批量上传 → 其它端可见).
    test(
      'offline batch edit replays and reaches peer after reconnect',
      () async {
        final cluster = SyncCluster();
        final iphone = cluster.addDevice(
          'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        );
        final mac = cluster.addDevice('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');

        iphone.offline = true;

        // 10-minute offline editing session: 3 inserts, 2 updates, 1 delete.
        const minute = Duration(minutes: 1);
        await iphone.writeRow(
          table: 'accounts',
          rowId: 'A1',
          opType: OpType.insert,
          fieldsDiff: {'id': 'A1', 'name': 'Wallet', 'currency': 'USD'},
        );
        iphone.advanceClock(minute);
        await iphone.writeRow(
          table: 'accounts',
          rowId: 'A2',
          opType: OpType.insert,
          fieldsDiff: {'id': 'A2', 'name': 'Bank', 'currency': 'USD'},
        );
        iphone.advanceClock(minute);
        await iphone.writeRow(
          table: 'accounts',
          rowId: 'A3',
          opType: OpType.insert,
          fieldsDiff: {'id': 'A3', 'name': 'Brokerage', 'currency': 'USD'},
        );
        iphone.advanceClock(minute);
        await iphone.writeRow(
          table: 'accounts',
          rowId: 'A1',
          opType: OpType.update,
          fieldsDiff: {'name': 'Wallet (cash)'},
        );
        iphone.advanceClock(minute);
        await iphone.writeRow(
          table: 'accounts',
          rowId: 'A2',
          opType: OpType.update,
          fieldsDiff: {'name': 'Bank — checking'},
        );
        iphone.advanceClock(minute);
        await iphone.writeRow(
          table: 'accounts',
          rowId: 'A3',
          opType: OpType.delete,
        );

        expect(
          await iphone.outbox.depth(),
          6,
          reason: 'all six ops queued while offline',
        );

        // Reconnect.
        iphone.offline = false;
        cluster.advanceAllClocks(const Duration(seconds: 30));
        await cluster.syncAll();

        expect(
          await iphone.outbox.depth(),
          0,
          reason: 'outbox drained on reconnect',
        );

        // Peer sees the converged state.
        final macA1 = mac.applier.lookup('accounts', 'A1');
        final macA2 = mac.applier.lookup('accounts', 'A2');
        final macA3 = mac.applier.lookup('accounts', 'A3');
        expect(macA1?.payload['name'], 'Wallet (cash)');
        expect(macA2?.payload['name'], 'Bank — checking');
        expect(
          macA3?.isDeleted,
          isTrue,
          reason:
              'tombstone propagated even when same row was inserted then '
              'deleted within the same offline batch',
        );
        expect(
          cluster.isConverged(),
          isTrue,
          reason: cluster.describeDivergence(iphone, mac),
        );
      },
    );

    // Scenario 3 (issue: 两端并发写同一行 → HLC LWW 行为符合预期).
    test('concurrent same-row writes converge to a single LWW value', () async {
      final cluster = SyncCluster();
      final iphone = cluster.addDevice('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
      final web = cluster.addDevice('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');

      // Both devices already know about row A1.
      await iphone.writeRow(
        table: 'accounts',
        rowId: 'A1',
        opType: OpType.insert,
        fieldsDiff: {'id': 'A1', 'name': 'Cash', 'currency': 'USD'},
      );
      cluster.advanceAllClocks(const Duration(seconds: 30));
      await cluster.syncAll();
      expect(web.applier.lookup('accounts', 'A1')?.payload['name'], 'Cash');

      // Both edit the same row before either has synced.
      iphone.advanceClock(const Duration(seconds: 1));
      await iphone.writeRow(
        table: 'accounts',
        rowId: 'A1',
        opType: OpType.update,
        fieldsDiff: {'name': 'Cash (iPhone)'},
      );
      web.advanceClock(const Duration(seconds: 1));
      await web.writeRow(
        table: 'accounts',
        rowId: 'A1',
        opType: OpType.update,
        fieldsDiff: {'name': 'Cash (Web)'},
      );

      // Sync. Either device's value can win — what matters is convergence
      // and that it's exactly one of the two.
      cluster.advanceAllClocks(const Duration(seconds: 30));
      await cluster.syncAll();

      final iphoneName = iphone.applier
          .lookup('accounts', 'A1')!
          .payload['name'];
      final webName = web.applier.lookup('accounts', 'A1')!.payload['name'];
      expect(
        iphoneName,
        equals(webName),
        reason: 'LWW must converge to a single value across devices',
      );
      expect({'Cash (iPhone)', 'Cash (Web)'}, contains(iphoneName));
      expect(cluster.isConverged(), isTrue);
    });

    // Scenario 4 (issue: 删除墓碑 → 其它端正确隐藏 — 不复活).
    test(
      'tombstone hides on peer and does not resurrect on later sync',
      () async {
        final cluster = SyncCluster();
        final iphone = cluster.addDevice(
          'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        );
        final mac = cluster.addDevice('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');

        // Establish a row both devices see.
        await iphone.writeRow(
          table: 'accounts',
          rowId: 'A1',
          opType: OpType.insert,
          fieldsDiff: {'id': 'A1', 'name': 'Cash', 'currency': 'USD'},
        );
        cluster.advanceAllClocks(const Duration(seconds: 30));
        await cluster.syncAll();
        expect(mac.applier.list('accounts').length, 1);

        // iPhone deletes; Mac picks it up via pull.
        iphone.advanceClock(const Duration(minutes: 1));
        await iphone.writeRow(
          table: 'accounts',
          rowId: 'A1',
          opType: OpType.delete,
        );
        cluster.advanceAllClocks(const Duration(seconds: 30));
        await cluster.syncAll();

        expect(mac.applier.lookup('accounts', 'A1')?.isDeleted, isTrue);
        expect(
          mac.applier.list('accounts'),
          isEmpty,
          reason: 'tombstoned row must be hidden from default queries',
        );

        // Several extra cycles must NOT revive the row (the most common
        // class of tombstone bug — replaying the original insert from op_log
        // because the cursor regressed).
        for (var i = 0; i < 3; i++) {
          cluster.advanceAllClocks(const Duration(seconds: 30));
          await cluster.syncAll();
          expect(
            mac.applier.list('accounts'),
            isEmpty,
            reason: 'cycle $i: row still tombstoned',
          );
          expect(iphone.applier.list('accounts'), isEmpty);
        }
        expect(cluster.isConverged(), isTrue);
      },
    );

    // Scenario 5 (issue: 大批量 1000 条 OpLog → 推送 / 拉取限流不破).
    test(
      '1000-op backlog drains across paged push/pull without loss',
      () async {
        final cluster = SyncCluster();
        final iphone = cluster.addDevice(
          'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        );
        final mac = cluster.addDevice('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');

        const total = 1000;
        iphone.offline = true;
        for (var i = 0; i < total; i++) {
          await iphone.writeRow(
            table: 'journal_entries',
            rowId: 'JE${i.toString().padLeft(4, '0')}',
            opType: OpType.insert,
            fieldsDiff: {
              'id': 'JE${i.toString().padLeft(4, '0')}',
              'date': '2026-05-03T00:00:00.000Z',
              'narration': 'bulk-$i',
            },
          );
          // Bump local clock per write so HLCs differ on phys_ms; keeps the
          // outbox order stable when the engine peeks a 500-op batch.
          if (i % 50 == 49) {
            iphone.advanceClock(const Duration(seconds: 1));
          }
        }
        expect(await iphone.outbox.depth(), total);

        iphone.offline = false;

        // Drive enough cycles to drain at the spec's 500-op batch cap. Two
        // cycles cover the worst case (push wave 1 of 500, push wave 2 of 500,
        // peer pull). Add a third for headroom.
        for (var c = 0; c < 3; c++) {
          cluster.advanceAllClocks(const Duration(seconds: 30));
          await cluster.syncAll();
        }

        expect(await iphone.outbox.depth(), 0, reason: 'all 1000 ops acked');
        expect(
          mac.applier.list('journal_entries').length,
          total,
          reason: 'peer materialised every op exactly once',
        );
        expect(cluster.isConverged(), isTrue);

        // Push and pull must have respected the 500-op cap.
        for (final batch in cluster.api.pushedBatches) {
          expect(
            batch.length,
            lessThanOrEqualTo(500),
            reason: 'no push batch over the spec cap',
          );
        }
      },
    );
  });
}
