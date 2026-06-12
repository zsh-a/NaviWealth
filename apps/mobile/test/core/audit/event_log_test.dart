import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/audit/domain_event.dart';
import 'package:naviwealth/core/audit/event_log_reader.dart';
import 'package:naviwealth/core/audit/event_log_writer.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';

import '../../core/persistence/test_database.dart';

void main() {
  late AppDatabase db;
  late EventLogReader reader;

  setUp(() {
    db = makeTestDatabase();
    reader = EventLogReader(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('EventLogWriter direct API', () {
    test(
      'records created and field_changed with structured before/after',
      () async {
        final stamper = _makeTestStamper();
        final writer = EventLogWriter(db: db);
        final created = await stamper.stamp();
        await writer.recordCreated(
          entityTable: 'assets',
          entityId: 'a-1',
          stamp: created,
          after: <String, Object?>{'last_price': '100', 'name': 'cash'},
        );
        final changed = await stamper.stamp();
        await writer.recordFieldChanged(
          entityTable: 'assets',
          entityId: 'a-1',
          stamp: changed,
          before: <String, Object?>{'last_price': '100'},
          after: <String, Object?>{'last_price': '300'},
          reason: '对账修正',
        );

        final events = await reader.listByEntity(
          entityTable: 'assets',
          entityId: 'a-1',
        );
        expect(events, hasLength(2));
        expect(events[0].kind, DomainEventKind.created);
        expect(events[0].after!['name'], 'cash');
        expect(events[0].before, isNull);
        expect(events[1].kind, DomainEventKind.fieldChanged);
        expect(events[1].before!['last_price'], '100');
        expect(events[1].after!['last_price'], '300');
        expect(events[1].reason, '对账修正');
        // Ordering by HLC means the create event comes before the change
        // even when the underlying recorded_at strings tie.
        expect(events[0].hlc.compareTo(events[1].hlc) < 0, isTrue);
      },
    );

    test('field_changed with empty after is a no-op', () async {
      final stamper = _makeTestStamper();
      final writer = EventLogWriter(db: db);
      final stamp = await stamper.stamp();
      await writer.recordFieldChanged(
        entityTable: 'assets',
        entityId: 'a-1',
        stamp: stamp,
        before: const <String, Object?>{},
        after: const <String, Object?>{},
      );
      expect(
        await reader.countByEntity(entityTable: 'assets', entityId: 'a-1'),
        0,
      );
    });

    test('soft_deleted snapshots before-state and leaves after null', () async {
      final stamper = _makeTestStamper();
      final writer = EventLogWriter(db: db);
      await writer.recordSoftDeleted(
        entityTable: 'accounts',
        entityId: 'acc-1',
        stamp: await stamper.stamp(),
        before: <String, Object?>{'name': '招行储蓄'},
        reason: 'cleanup',
      );
      final events = await reader.listByEntity(
        entityTable: 'accounts',
        entityId: 'acc-1',
      );
      expect(events.single.kind, DomainEventKind.softDeleted);
      expect(events.single.before!['name'], '招行储蓄');
      expect(events.single.after, isNull);
      expect(events.single.reason, 'cleanup');
    });

    test(
      'deleteByEntity is a maintenance escape hatch and counts rows',
      () async {
        final stamper = _makeTestStamper();
        final writer = EventLogWriter(db: db);
        await writer.recordCreated(
          entityTable: 'assets',
          entityId: 'a-1',
          stamp: await stamper.stamp(),
          after: const <String, Object?>{'name': 'x'},
        );
        await writer.recordCreated(
          entityTable: 'assets',
          entityId: 'a-2',
          stamp: await stamper.stamp(),
          after: const <String, Object?>{'name': 'y'},
        );
        final removed = await reader.deleteByEntity(
          entityTable: 'assets',
          entityId: 'a-1',
        );
        expect(removed, 1);
        // The other entity's history is untouched.
        expect(
          await reader.countByEntity(entityTable: 'assets', entityId: 'a-2'),
          1,
        );
      },
    );
  });

  // `ExpenseRepository` is read-only; all expense writes flow through
  // `JournalEntryRepository`.
}

MutationStamper _makeTestStamper({
  String userId = 'u-test',
  String deviceId = 'dev-test',
  int initialMillis = 1_700_000_000_000,
}) {
  var millis = initialMillis;
  Hlc? last;
  return MutationStamper(
    currentUserId: () async => userId,
    deviceId: () async => deviceId,
    stampHlc: () async {
      final base = Hlc(wallMillis: millis, counter: 0, nodeId: deviceId);
      final next = last == null
          ? base
          : Hlc.tick(lastSeen: last!, nowMillis: millis);
      last = next;
      millis += 1;
      return next;
    },
  );
}
