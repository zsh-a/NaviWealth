import 'package:decimal/decimal.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'holding.freezed.dart';

/// Holdings are **derived** from the [Transaction] fact table — never the
/// source of truth. We materialize them into [Holding] objects (and
/// optionally cache them, see `holdings_cache` in `tables.dart`) so the UI
/// can render quickly and analytics queries don't replay every transaction
/// on every refresh.
///
/// As a derived view, Holding has no [SyncMeta] of its own.
@freezed
abstract class Holding with _$Holding {
  const factory Holding({
    required String accountId,
    required String assetId,
    required Decimal quantity,
    required Decimal averageCost,
    required Decimal marketValue,
    required Decimal unrealizedPnl,
    required String currency,
    required DateTime asOf,
  }) = _Holding;
}
