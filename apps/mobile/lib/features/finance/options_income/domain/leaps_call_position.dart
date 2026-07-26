import 'package:decimal/decimal.dart';

import 'package:naviwealth/core/sync/sync_meta.dart';

const Object _unsetLeapsField = Object();

/// A long-dated call held alongside (but never as a stage of) a Wheel.
///
/// Premiums are stored per contract. Fees are total position fees. A manual
/// mark and delta are optional snapshots: absence is represented honestly
/// instead of being replaced with estimated market data.
class LeapsCallPosition {
  const LeapsCallPosition({
    required this.id,
    required this.symbol,
    required this.optionSymbol,
    required this.openedAt,
    required this.expirationAt,
    required this.closedAt,
    required this.strikePrice,
    required this.entryDebit,
    required this.exitCredit,
    required this.fees,
    required this.currency,
    required this.contractSize,
    required this.contractQuantity,
    required this.status,
    required this.currentMark,
    required this.currentDelta,
    required this.markedAt,
    required this.brokerageAccountId,
    this.cashAccountId,
    this.underlyingMarket,
    required this.notes,
    required this.sync,
  });

  final String id;
  final String symbol;
  final String optionSymbol;
  final DateTime openedAt;
  final DateTime expirationAt;
  final DateTime? closedAt;
  final Decimal strikePrice;
  final Decimal entryDebit;
  final Decimal? exitCredit;
  final Decimal fees;
  final String currency;
  final int contractSize;
  final int contractQuantity;
  final LeapsCallStatus status;
  final Decimal? currentMark;
  final Decimal? currentDelta;
  final DateTime? markedAt;
  final String? brokerageAccountId;
  final String? cashAccountId;
  final String? underlyingMarket;
  final String? notes;
  final SyncMeta sync;

  bool get isOpen => status == LeapsCallStatus.open;
  Decimal get grossEntryCost =>
      entryDebit * Decimal.fromInt(contractQuantity) + fees;
  Decimal? get grossExitProceeds => exitCredit == null
      ? null
      : exitCredit! * Decimal.fromInt(contractQuantity);
  Decimal? get realizedPnl {
    final proceeds = grossExitProceeds;
    if (proceeds != null) return proceeds - grossEntryCost;
    if (status == LeapsCallStatus.expired) return -grossEntryCost;
    return null;
  }

  Decimal? get marketValue => currentMark == null
      ? null
      : currentMark! * Decimal.fromInt(contractQuantity);
  Decimal? get unrealizedPnl =>
      marketValue == null ? null : marketValue! - grossEntryCost;
  Decimal? get deltaEquivalentShares => currentDelta == null
      ? null
      : currentDelta! *
            Decimal.fromInt(contractSize) *
            Decimal.fromInt(contractQuantity);

  LeapsCallPosition copyWith({
    String? symbol,
    String? optionSymbol,
    DateTime? openedAt,
    DateTime? expirationAt,
    Object? closedAt = _unsetLeapsField,
    Decimal? strikePrice,
    Decimal? entryDebit,
    Object? exitCredit = _unsetLeapsField,
    Decimal? fees,
    String? currency,
    int? contractSize,
    int? contractQuantity,
    LeapsCallStatus? status,
    Object? currentMark = _unsetLeapsField,
    Object? currentDelta = _unsetLeapsField,
    Object? markedAt = _unsetLeapsField,
    Object? brokerageAccountId = _unsetLeapsField,
    Object? cashAccountId = _unsetLeapsField,
    Object? underlyingMarket = _unsetLeapsField,
    Object? notes = _unsetLeapsField,
    SyncMeta? sync,
  }) => LeapsCallPosition(
    id: id,
    symbol: symbol ?? this.symbol,
    optionSymbol: optionSymbol ?? this.optionSymbol,
    openedAt: openedAt ?? this.openedAt,
    expirationAt: expirationAt ?? this.expirationAt,
    closedAt: identical(closedAt, _unsetLeapsField)
        ? this.closedAt
        : closedAt as DateTime?,
    strikePrice: strikePrice ?? this.strikePrice,
    entryDebit: entryDebit ?? this.entryDebit,
    exitCredit: identical(exitCredit, _unsetLeapsField)
        ? this.exitCredit
        : exitCredit as Decimal?,
    fees: fees ?? this.fees,
    currency: currency ?? this.currency,
    contractSize: contractSize ?? this.contractSize,
    contractQuantity: contractQuantity ?? this.contractQuantity,
    status: status ?? this.status,
    currentMark: identical(currentMark, _unsetLeapsField)
        ? this.currentMark
        : currentMark as Decimal?,
    currentDelta: identical(currentDelta, _unsetLeapsField)
        ? this.currentDelta
        : currentDelta as Decimal?,
    markedAt: identical(markedAt, _unsetLeapsField)
        ? this.markedAt
        : markedAt as DateTime?,
    brokerageAccountId: identical(brokerageAccountId, _unsetLeapsField)
        ? this.brokerageAccountId
        : brokerageAccountId as String?,
    cashAccountId: identical(cashAccountId, _unsetLeapsField)
        ? this.cashAccountId
        : cashAccountId as String?,
    underlyingMarket: identical(underlyingMarket, _unsetLeapsField)
        ? this.underlyingMarket
        : underlyingMarket as String?,
    notes: identical(notes, _unsetLeapsField) ? this.notes : notes as String?,
    sync: sync ?? this.sync,
  );
}

enum LeapsCallStatus { open, closed, exercised, expired }

extension LeapsCallStatusWire on LeapsCallStatus {
  String get wire => name;
}

LeapsCallStatus parseLeapsCallStatus(String wire) =>
    LeapsCallStatus.values.firstWhere(
      (value) => value.wire == wire,
      orElse: () => LeapsCallStatus.open,
    );
