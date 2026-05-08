import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/op.dart';
import 'package:naviwealth/data/db/app_database.dart';
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/data/repositories/account_op_applier.dart';

import '../../data/db/test_database.dart';

const _user = 'user-1';
const _devA = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const _devB = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

Op _accountOp({
  required String opId,
  required OpType opType,
  required int wall,
  String rowId = 'account-1',
  String deviceId = _devA,
  Map<String, Object?>? fields,
}) {
  return Op(
    opId: opId,
    tableName: 'accounts',
    rowId: rowId,
    opType: opType,
    fieldsDiff: opType == OpType.delete ? null : fields,
    hlc: Hlc(wallMillis: wall, counter: 0, nodeId: Hlc.serverNodeId),
    deviceId: deviceId,
  );
}

Map<String, Object?> _insertFields({
  String id = 'account-1',
  String name = 'Cash',
  String currency = 'CNY',
}) {
  return {
    'id': id,
    'type': 'cash',
    'name': name,
    'currency': currency,
    'category': 'asset',
    'institution': null,
    'account_number': null,
    'note': null,
    'archived': false,
    'parent_id': null,
    'icon': null,
    'color': null,
    'owner_user_id': _user,
  };
}

Future<AccountRow> _account(AppDatabase db, String id) async {
  return (db.select(db.accounts)..where((t) => t.id.equals(id))).getSingle();
}

void main() {
  late AppDatabase db;
  late AccountOpApplier applier;

  setUp(() {
    db = makeTestDatabase();
    applier = AccountOpApplier(db);
  });

  tearDown(() => db.close());

  test(
    'inserts pulled account ops into the local materialised table',
    () async {
      await applier.applyAll([
        _accountOp(
          opId: 'op-1',
          opType: OpType.insert,
          wall: 1_000,
          fields: _insertFields(),
        ),
      ]);

      final row = await _account(db, 'account-1');
      expect(row.name, 'Cash');
      expect(row.currency, 'CNY');
      expect(row.ownerUserId, _user);
      expect(row.updatedByDevice, _devA);
      expect(row.hlc.wallMillis, 1_000);
    },
  );

  test('applies newer updates and ignores stale account ops', () async {
    await applier.applyAll([
      _accountOp(
        opId: 'op-1',
        opType: OpType.insert,
        wall: 1_000,
        fields: _insertFields(),
      ),
      _accountOp(
        opId: 'op-2',
        opType: OpType.update,
        wall: 2_000,
        deviceId: _devB,
        fields: {'name': 'Emergency Cash'},
      ),
      _accountOp(
        opId: 'op-stale',
        opType: OpType.update,
        wall: 1_500,
        fields: {'name': 'Stale Name'},
      ),
    ]);

    final row = await _account(db, 'account-1');
    expect(row.name, 'Emergency Cash');
    expect(row.updatedByDevice, _devB);
    expect(row.hlc.wallMillis, 2_000);
  });

  test('materialises newer deletes as tombstones', () async {
    await applier.applyAll([
      _accountOp(
        opId: 'op-1',
        opType: OpType.insert,
        wall: 1_000,
        fields: _insertFields(),
      ),
      _accountOp(opId: 'op-2', opType: OpType.delete, wall: 2_000),
    ]);

    final row = await _account(db, 'account-1');
    expect(row.deletedAt, isNotNull);
    expect(row.hlc.wallMillis, 2_000);
  });
}
