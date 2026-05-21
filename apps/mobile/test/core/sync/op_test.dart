import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/op.dart';
import 'package:naviwealth/data/domain/hlc.dart';

void main() {
  group('Op encoding', () {
    final hlc = Hlc.parse(
      '1714291200000.0001-1f5b0c3a-4e2d-4d31-9b77-3f7c1f0d2c01',
    );
    const dev = '1f5b0c3a-4e2d-4d31-9b77-3f7c1f0d2c01';

    // SP-B-1
    test('insert encodes full row including PK', () {
      final op = Op(
        opId: 'op-1',
        tableName: 'accounts',
        rowId: 'A1',
        opType: OpType.insert,
        fieldsDiff: const {'id': 'A1', 'name': 'Cash', 'currency': 'USD'},
        hlc: hlc,
        deviceId: dev,
      );
      final json = op.toJson();
      expect(json['op_type'], 'insert');
      expect((json['fields_diff'] as Map).containsKey('id'), isTrue);
      expect((json['fields_diff'] as Map)['name'], 'Cash');
    });

    // SP-B-2
    test('update encodes partial diff', () {
      final op = Op(
        opId: 'op-2',
        tableName: 'accounts',
        rowId: 'A1',
        opType: OpType.update,
        fieldsDiff: const {'name': 'Wallet'},
        hlc: hlc,
        deviceId: dev,
      );
      expect(op.toJson()['fields_diff'], {'name': 'Wallet'});
    });

    // SP-B-3
    test('delete encodes null diff', () {
      final op = Op(
        opId: 'op-3',
        tableName: 'accounts',
        rowId: 'A1',
        opType: OpType.delete,
        fieldsDiff: null,
        hlc: hlc,
        deviceId: dev,
      );
      expect(op.toJson()['fields_diff'], isNull);
      expect(op.toJson()['op_type'], 'delete');
    });

    // SP-B-5: null vs absent column distinction (preserved in JSON)
    test('null is distinct from absent', () {
      final op = Op(
        opId: 'op-4',
        tableName: 'accounts',
        rowId: 'A1',
        opType: OpType.update,
        fieldsDiff: const {'note': null},
        hlc: hlc,
        deviceId: dev,
      );
      final encoded = op.encode();
      expect(encoded.contains('"note":null'), isTrue);
      final round = Op.decode(encoded);
      expect(round.fieldsDiff!.containsKey('note'), isTrue);
      expect(round.fieldsDiff!['note'], isNull);
    });

    // SP-B-7
    test('validateOpForQueue rejects oversized diff', () {
      final big = 'x' * (65 * 1024);
      final op = Op(
        opId: 'op-big',
        tableName: 'accounts',
        rowId: 'A1',
        opType: OpType.update,
        fieldsDiff: {'note': big},
        hlc: hlc,
        deviceId: dev,
      );
      expect(validateOpForQueue(op), 'payload_too_large');
    });

    // SP-B-4
    test('validateOpForQueue rejects empty update', () {
      final op = Op(
        opId: 'op-5',
        tableName: 'accounts',
        rowId: 'A1',
        opType: OpType.update,
        fieldsDiff: const {},
        hlc: hlc,
        deviceId: dev,
      );
      expect(validateOpForQueue(op), 'empty_update');
    });

    // SP-K-3
    test('validateOpForQueue rejects unknown table', () {
      final op = Op(
        opId: 'op-6',
        tableName: 'secret_diary',
        rowId: 'A1',
        opType: OpType.insert,
        fieldsDiff: const {'a': 1},
        hlc: hlc,
        deviceId: dev,
      );
      expect(validateOpForQueue(op), 'unknown_table');
    });

    test('round-trip JSON', () {
      final op = Op(
        opId: 'op-rt',
        tableName: 'journal_entries',
        rowId: 'JE1',
        opType: OpType.update,
        fieldsDiff: const {'description': 'rebate'},
        hlc: hlc,
        deviceId: dev,
      );
      expect(Op.decode(op.encode()), isA<Op>());
      final round = Op.decode(op.encode());
      expect(round.opId, op.opId);
      expect(round.tableName, op.tableName);
      expect(round.rowId, op.rowId);
      expect(round.hlc, op.hlc);
      expect(round.fieldsDiff, op.fieldsDiff);
    });
  });

  // Pin the forward-only sync enum so any future add / drop is a deliberate
  // schema change, not a silent edit.
  group('kSyncableTables', () {
    test('contains the FIR-130 ledger triple', () {
      expect(
        kSyncableTables,
        containsAll(<String>{'journal_entries', 'postings', 'prices'}),
      );
    });

    test('matches the documented v1 closed set', () {
      // Mirror of `docs/sync-protocol.md` §4.1. Updating either side
      // without the other is the bug this test catches.
      const expected = <String>{
        'accounts',
        'assets',
        'liabilities',
        'fx_rates',
        'tags',
        'tag_links',
        'goals',
        'devices',
        'amortization_entries',
        'categories',
        'settings',
        'users',
        'journal_entries',
        'postings',
        'prices',
        'watchlist_items',
        // Options Income Planner P0 (`docs/options-income.md`).
        'options_strategy_profile',
        'approved_underlyings',
        // Options Income Planner P3 — trade journal.
        'options_trade_journal',
      };
      expect(kSyncableTables, expected);
    });
  });
}
