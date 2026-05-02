import 'package:decimal/decimal.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'enums.dart';
import 'sync_meta.dart';

part 'transaction.freezed.dart';

/// Single fact-table entry. Every position change in NaviWealth flows
/// through this — Holding is *always* a fold over Transactions, never a
/// hand-edited row.
///
/// `assetId` is nullable because pure cash flows (deposit / withdraw / fee
/// / tax) live on an account without referencing a specific asset.
/// `counterAccountId` is set on transfers to allow the matching leg to be
/// found by id rather than scanning by date and amount.
/// `transferGroupId` (FIR-124) links the two legs of an atomic transfer:
/// the `transferOut` row on the source account and the matching
/// `transferIn` row on the destination account share the same group id,
/// so the pair can be displayed and tombstoned as a single unit.
@freezed
abstract class Transaction with _$Transaction {
  const factory Transaction({
    required String id,
    required String accountId,
    String? assetId,
    required TransactionType type,
    required Decimal quantity,
    required Decimal price,
    required String currency,
    required DateTime tradeDate,
    DateTime? settleDate,
    Decimal? fee,
    Decimal? tax,
    String? counterAccountId,
    String? lotId,
    String? note,
    String? transferGroupId,
    required SyncMeta sync,
  }) = _Transaction;
}
