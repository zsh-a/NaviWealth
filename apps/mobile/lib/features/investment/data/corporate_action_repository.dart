import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/op_outbox.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';

import '../domain/models/corporate_actions.dart';

class CorporateActionRepository {
  CorporateActionRepository({
    required AppDatabase db,
    required OutboxStore outbox,
    required MutationStamper stamper,
  }) : _db = db,
       _outbox = outbox,
       _stamper = stamper;

  final AppDatabase _db;
  final OutboxStore _outbox;
  final MutationStamper _stamper;

  static const String tableName = 'corporate_actions';

  Stream<List<CorporateAction>> watchDeclared(String ownerUserId) {
    final query = _db.select(_db.corporateActions)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) =>
            OrderingTerm(expression: t.effectiveDate, mode: OrderingMode.desc),
      ]);
    return query.watch().map(
      (rows) => rows.map(_rowToDomain).toList(growable: false),
    );
  }

  Future<List<CorporateAction>> listDeclared(String ownerUserId) async {
    final query = _db.select(_db.corporateActions)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) =>
            OrderingTerm(expression: t.effectiveDate, mode: OrderingMode.desc),
      ]);
    final rows = await query.get();
    return rows.map(_rowToDomain).toList(growable: false);
  }

  Future<void> upsert(CorporateAction action) async {
    final stamp = await _stamper.stamp();
    final row = _companionFor(action, stamp);
    await _db.transaction(() async {
      await _db.into(_db.corporateActions).insertOnConflictUpdate(row);
      await _outbox.enqueue(table: tableName, rowId: action.id);
    });
  }

  CorporateActionsCompanion _companionFor(
    CorporateAction action,
    MutationStamp stamp,
  ) {
    final base = CorporateActionsCompanion.insert(
      id: action.id,
      kind: _kindFor(action),
      assetId: action.assetId,
      effectiveDate: action.effectiveDate,
      ownerUserId: stamp.ownerUserId,
      updatedAt: stamp.now,
      updatedByDevice: stamp.deviceId,
      hlc: stamp.hlc,
      deletedAt: const Value(null),
    );
    return switch (action) {
      CashDividendAction a => base.copyWith(
        transactionId: Value(a.transactionId),
        accountId: Value(a.accountId),
        currency: Value(a.currency),
        amountPerShare: Value(a.amountPerShare),
        withholdingTax: Value(a.withholdingTax),
      ),
      StockDividendAction a => base.copyWith(bonusRatio: Value(a.bonusRatio)),
      SplitAction a => base.copyWith(splitRatio: Value(a.ratio)),
      RightsIssueAction a => base.copyWith(
        transactionId: Value(a.transactionId),
        accountId: Value(a.accountId),
        currency: Value(a.currency),
        subscribedQuantity: Value(a.subscribedQuantity),
        pricePerUnit: Value(a.pricePerUnit),
        fee: Value(a.fee),
      ),
      DripAction a => base.copyWith(
        transactionId: Value(a.transactionId),
        accountId: Value(a.accountId),
        currency: Value(a.currency),
        amountPerShare: Value(a.amountPerShare),
        withholdingTax: Value(a.withholdingTax),
        pricePerUnit: Value(a.pricePerUnit),
        fee: Value(a.fee),
      ),
    };
  }
}

const String _cashDividendKind = 'cash_dividend';
const String _stockDividendKind = 'stock_dividend';
const String _splitKind = 'split';
const String _rightsIssueKind = 'rights_issue';
const String _dripKind = 'drip';

String _kindFor(CorporateAction action) => switch (action) {
  CashDividendAction() => _cashDividendKind,
  StockDividendAction() => _stockDividendKind,
  SplitAction() => _splitKind,
  RightsIssueAction() => _rightsIssueKind,
  DripAction() => _dripKind,
};

CorporateAction _rowToDomain(CorporateActionRow row) {
  switch (row.kind) {
    case _cashDividendKind:
      return CashDividendAction(
        id: row.id,
        assetId: row.assetId,
        effectiveDate: row.effectiveDate,
        transactionId: _required(row.transactionId, row, 'transactionId'),
        accountId: _required(row.accountId, row, 'accountId'),
        currency: _required(row.currency, row, 'currency'),
        amountPerShare: _required(row.amountPerShare, row, 'amountPerShare'),
        withholdingTax: row.withholdingTax ?? Decimal.zero,
      );
    case _stockDividendKind:
      return StockDividendAction(
        id: row.id,
        assetId: row.assetId,
        effectiveDate: row.effectiveDate,
        bonusRatio: _required(row.bonusRatio, row, 'bonusRatio'),
      );
    case _splitKind:
      return SplitAction(
        id: row.id,
        assetId: row.assetId,
        effectiveDate: row.effectiveDate,
        ratio: _required(row.splitRatio, row, 'splitRatio'),
      );
    case _rightsIssueKind:
      return RightsIssueAction(
        id: row.id,
        assetId: row.assetId,
        effectiveDate: row.effectiveDate,
        transactionId: _required(row.transactionId, row, 'transactionId'),
        accountId: _required(row.accountId, row, 'accountId'),
        currency: _required(row.currency, row, 'currency'),
        subscribedQuantity: _required(
          row.subscribedQuantity,
          row,
          'subscribedQuantity',
        ),
        pricePerUnit: _required(row.pricePerUnit, row, 'pricePerUnit'),
        fee: row.fee ?? Decimal.zero,
      );
    case _dripKind:
      return DripAction(
        id: row.id,
        assetId: row.assetId,
        effectiveDate: row.effectiveDate,
        transactionId: _required(row.transactionId, row, 'transactionId'),
        accountId: _required(row.accountId, row, 'accountId'),
        currency: _required(row.currency, row, 'currency'),
        amountPerShare: _required(row.amountPerShare, row, 'amountPerShare'),
        pricePerUnit: _required(row.pricePerUnit, row, 'pricePerUnit'),
        withholdingTax: row.withholdingTax ?? Decimal.zero,
        fee: row.fee ?? Decimal.zero,
      );
    default:
      throw StateError('Unsupported corporate action kind: ${row.kind}');
  }
}

T _required<T>(T? value, CorporateActionRow row, String column) {
  if (value != null) return value;
  throw StateError(
    'corporate_actions.${row.id} kind=${row.kind} missing $column',
  );
}

SyncMeta syncMetaForCorporateActionRow(CorporateActionRow row) => SyncMeta(
  ownerUserId: row.ownerUserId,
  updatedAt: row.updatedAt,
  updatedByDevice: row.updatedByDevice,
  hlc: row.hlc,
  deletedAt: row.deletedAt,
);
