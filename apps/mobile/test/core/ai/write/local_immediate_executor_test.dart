import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/write/write.dart';

void main() {
  group('LocalImmediateWriteExecutor', () {
    test('register returns a LocalImmediateWrite envelope with undo token', () async {
      var clock = DateTime.utc(2026, 5, 10, 10);
      final exec = LocalImmediateWriteExecutor(now: () => clock);

      final envelope = await exec.register(
        kindLabel: 'memo_edit',
        summaryZh: '修改备注',
        revert: () async {},
      );

      expect(envelope.kindLabel, 'memo_edit');
      expect(envelope.summaryZh, '修改备注');
      expect(envelope.undo.token, isNotEmpty);
      expect(envelope.undo.expiresAtIso, contains('2026-05-10T10:00:30'));
      expect(exec.pendingCount, 1);
    });

    test('undo runs the revert and consumes the entry', () async {
      final exec = LocalImmediateWriteExecutor();
      var reverted = false;
      final envelope = await exec.register(
        kindLabel: 'tag_apply',
        summaryZh: '打标签',
        revert: () async {
          reverted = true;
        },
      );

      final ok = await exec.undo(envelope.undo.token);
      expect(ok, isTrue);
      expect(reverted, isTrue);
      expect(exec.pendingCount, 0);
    });

    test('undo returns false for an unknown token', () async {
      final exec = LocalImmediateWriteExecutor();
      final ok = await exec.undo('not-a-token');
      expect(ok, isFalse);
    });

    test('expired entries are dropped before they can be undone', () async {
      var clock = DateTime.utc(2026, 5, 10, 10);
      final exec = LocalImmediateWriteExecutor(now: () => clock);
      final envelope = await exec.register(
        kindLabel: 'memo_edit',
        summaryZh: '修改备注',
        revert: () async {
          fail('revert should not run after expiry');
        },
        window: const Duration(seconds: 5),
      );

      // Advance clock past the window.
      clock = clock.add(const Duration(seconds: 6));
      expect(exec.pendingCount, 0);
      final ok = await exec.undo(envelope.undo.token);
      expect(ok, isFalse);
    });

    test('recent returns entries newest-first', () async {
      var clock = DateTime.utc(2026, 5, 10, 10);
      final exec = LocalImmediateWriteExecutor(now: () => clock);

      await exec.register(
        kindLabel: 'memo_edit',
        summaryZh: '第一次',
        revert: () async {},
      );
      clock = clock.add(const Duration(seconds: 1));
      await exec.register(
        kindLabel: 'tag_apply',
        summaryZh: '第二次',
        revert: () async {},
      );
      clock = clock.add(const Duration(seconds: 1));
      await exec.register(
        kindLabel: 'category_set',
        summaryZh: '第三次',
        revert: () async {},
      );

      final recent = exec.recent();
      expect(
        recent.map((e) => e.summaryZh).toList(),
        <String>['第三次', '第二次', '第一次'],
      );
    });

    test('multiple undo calls on the same token are idempotent (false)', () async {
      final exec = LocalImmediateWriteExecutor();
      var count = 0;
      final envelope = await exec.register(
        kindLabel: 'memo_edit',
        summaryZh: '修改',
        revert: () async {
          count++;
        },
      );

      expect(await exec.undo(envelope.undo.token), isTrue);
      expect(await exec.undo(envelope.undo.token), isFalse);
      expect(count, 1);
    });
  });
}
