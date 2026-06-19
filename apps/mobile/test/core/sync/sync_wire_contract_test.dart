import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/sync_api_client.dart';

void main() {
  group('Sync v2 wire contracts', () {
    test('protocol version is pinned to v2', () {
      expect(kSyncProtocolVersion, 2);
    });

    test('RowChange.toJson emits only client-to-server fields', () {
      // SP-B-4 / SP-C-2: client pushes current row state; server-set cursor
      // fields must not leak into outbound changes.
      const change = RowChange(
        table: 'fin:accounts',
        id: 'acc-1',
        payload: <String, Object?>{
          'id': 'acc-1',
          'name': 'Cash',
          'hlc': '1716381000123.0000-device-a',
        },
        version: '1716381000123.0000-device-a',
        deleted: false,
        deviceId: 'server-only',
        seq: 42,
      );

      expect(change.toJson(), <String, Object?>{
        'table': 'fin:accounts',
        'id': 'acc-1',
        'payload': <String, Object?>{
          'id': 'acc-1',
          'name': 'Cash',
          'hlc': '1716381000123.0000-device-a',
        },
        'version': '1716381000123.0000-device-a',
        'deleted': false,
      });
    });

    test('RowChange.toJson matches the shared client-push fixture', () {
      // This fixture is also consumed by the backend Rust tests, pinning the
      // Dart and Rust serializers to the same row-change wire shape.
      final fixture = _readFixture('sync_v2_client_push_row_change.json');
      final change = RowChange.fromJson(fixture);

      expect(change.toJson(), fixture);
    });

    test('RowChange.toJson preserves tombstone shape', () {
      // SP-B-5: a delete is still a row-state change with the same row id.
      const change = RowChange(
        table: 'fin:accounts',
        id: 'acc-1',
        payload: null,
        version: '1716381000124.0000-device-a',
        deleted: true,
      );

      expect(change.toJson(), <String, Object?>{
        'table': 'fin:accounts',
        'id': 'acc-1',
        'payload': null,
        'version': '1716381000124.0000-device-a',
        'deleted': true,
      });
    });

    test('RowChange.fromJson parses server-only fields', () {
      final change = RowChange.fromJson(<String, Object?>{
        'table': 'know:knowledge_notes',
        'id': 'note-1',
        'payload': <Object?, Object?>{
          'id': 'note-1',
          'title': 'Decision context',
        },
        'version': '1716381000125.0000-device-b',
        'deleted': false,
        'device_id': 'device-b',
        'seq': 1287,
      });

      expect(change.table, 'know:knowledge_notes');
      expect(change.id, 'note-1');
      expect(change.payload, <String, Object?>{
        'id': 'note-1',
        'title': 'Decision context',
      });
      expect(change.version, '1716381000125.0000-device-b');
      expect(change.deleted, isFalse);
      expect(change.deviceId, 'device-b');
      expect(change.seq, 1287);
    });

    test('RowChange.fromJson treats null payload as a tombstone payload', () {
      final change = RowChange.fromJson(<String, Object?>{
        'table': 'health:health_metrics',
        'id': 'metric-1',
        'payload': null,
        'version': '1716381000126.0000-device-b',
        'deleted': true,
        'device_id': 'device-b',
        'seq': 1288,
      });

      expect(change.payload, isNull);
      expect(change.deleted, isTrue);
      expect(change.deviceId, 'device-b');
      expect(change.seq, 1288);
    });

    test('RowChange.fromJson reads the shared server tombstone fixture', () {
      final fixture = _readFixture('sync_v2_server_tombstone_row_change.json');
      final change = RowChange.fromJson(fixture);

      expect(change.table, 'health:health_metrics');
      expect(change.id, 'metric-1');
      expect(change.payload, isEmpty);
      expect(change.version, '1716381000124.0000-device-b');
      expect(change.deleted, isTrue);
      expect(change.deviceId, 'device-b');
      expect(change.seq, 42);
    });

    test('RowAck and SyncResponse expose accepted wire keys', () {
      // SP-C-3 / SP-C-4: the engine clears only dirty pointers whose wire
      // keys appear in the server's accepted list.
      const response = SyncResponse(
        seq: 9,
        changes: <RowChange>[],
        more: false,
        accepted: <RowAck>[
          RowAck(table: 'fin:accounts', id: 'acc-1'),
          RowAck(table: 'know:knowledge_notes', id: 'note-1'),
        ],
      );

      expect(response.acceptedKeys, <String>{
        'fin:accounts\u{0}acc-1',
        'know:knowledge_notes\u{0}note-1',
      });
      expect(response.accepted.first.toJson(), <String, Object?>{
        'table': 'fin:accounts',
        'id': 'acc-1',
      });
    });
  });
}

Map<String, Object?> _readFixture(String name) {
  final file = File('../../docs/fixtures/$name');
  return (jsonDecode(file.readAsStringSync()) as Map<String, Object?>).map(
    (key, value) => MapEntry(key, value),
  );
}
