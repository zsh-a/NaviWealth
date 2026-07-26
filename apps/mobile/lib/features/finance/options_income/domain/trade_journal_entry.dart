import 'package:decimal/decimal.dart';

import 'package:naviwealth/core/sync/sync_meta.dart';
import 'options_strategy_profile.dart';

const Object _unsetTradeJournalField = Object();

/// One row of the user's options trade journal.
///
/// Created from a successful sell, mutated when the position closes (or is
/// assigned / expires). The entry is synced — every device sees the same
/// journal — per `docs/domains/options-income.md` §6.2.
class TradeJournalEntry {
  const TradeJournalEntry({
    required this.id,
    required this.strategy,
    required this.symbol,
    required this.optionSymbol,
    required this.openedAt,
    this.expirationAt,
    required this.closedAt,
    required this.entryCredit,
    required this.exitDebit,
    this.fees,
    required this.realizedPnl,
    required this.currency,
    required this.status,
    required this.notes,
    this.brokerageAccountId,
    this.cashAccountId,
    this.underlyingMarket,
    this.strikePrice,
    this.contractSize,
    this.contractQuantity = 1,
    required this.sync,
  });

  final String id;
  final OptionsStrategyKind strategy;
  final String symbol;
  final String optionSymbol;
  final DateTime openedAt;
  final DateTime? expirationAt;
  final DateTime? closedAt;

  /// Premium received when the position opened (per contract, USD = 100×
  /// the per-share credit).
  final Decimal entryCredit;

  /// Debit paid to close, or `null` if the position is still open / was
  /// assigned / expired worthless.
  final Decimal? exitDebit;

  /// Total broker fees across open and close legs.
  final Decimal? fees;

  /// Realised P&L stored explicitly instead of recomputed so a manual
  /// override (e.g. broker commission netting) survives a re-render.
  final Decimal? realizedPnl;

  final String currency;
  final TradeJournalStatus status;
  final String? notes;
  final String? brokerageAccountId;
  final String? cashAccountId;
  final String? underlyingMarket;
  final Decimal? strikePrice;
  final int? contractSize;
  final int contractQuantity;
  final SyncMeta sync;

  int get effectiveContractSize => contractSize ?? 100;
  Decimal get effectiveFees => fees ?? Decimal.zero;
  Decimal get grossEntryCredit =>
      entryCredit * Decimal.fromInt(contractQuantity);
  Decimal? get grossExitDebit =>
      exitDebit == null ? null : exitDebit! * Decimal.fromInt(contractQuantity);

  Decimal? get trackedNetPnl {
    final explicit = realizedPnl;
    if (explicit != null) return explicit;
    final debit = grossExitDebit;
    if (debit != null) return grossEntryCredit - debit - effectiveFees;
    if (status == TradeJournalStatus.expired ||
        status == TradeJournalStatus.assigned) {
      return grossEntryCredit - effectiveFees;
    }
    return null;
  }

  TradeJournalEntry copyWith({
    OptionsStrategyKind? strategy,
    String? symbol,
    String? optionSymbol,
    DateTime? openedAt,
    Object? expirationAt = _unsetTradeJournalField,
    Object? closedAt = _unsetTradeJournalField,
    Decimal? entryCredit,
    Object? exitDebit = _unsetTradeJournalField,
    Object? fees = _unsetTradeJournalField,
    Object? realizedPnl = _unsetTradeJournalField,
    String? currency,
    TradeJournalStatus? status,
    Object? notes = _unsetTradeJournalField,
    Object? brokerageAccountId = _unsetTradeJournalField,
    Object? cashAccountId = _unsetTradeJournalField,
    Object? underlyingMarket = _unsetTradeJournalField,
    Object? strikePrice = _unsetTradeJournalField,
    Object? contractSize = _unsetTradeJournalField,
    int? contractQuantity,
    SyncMeta? sync,
  }) {
    return TradeJournalEntry(
      id: id,
      strategy: strategy ?? this.strategy,
      symbol: symbol ?? this.symbol,
      optionSymbol: optionSymbol ?? this.optionSymbol,
      openedAt: openedAt ?? this.openedAt,
      expirationAt: identical(expirationAt, _unsetTradeJournalField)
          ? this.expirationAt
          : expirationAt as DateTime?,
      closedAt: identical(closedAt, _unsetTradeJournalField)
          ? this.closedAt
          : closedAt as DateTime?,
      entryCredit: entryCredit ?? this.entryCredit,
      exitDebit: identical(exitDebit, _unsetTradeJournalField)
          ? this.exitDebit
          : exitDebit as Decimal?,
      fees: identical(fees, _unsetTradeJournalField)
          ? this.fees
          : fees as Decimal?,
      realizedPnl: identical(realizedPnl, _unsetTradeJournalField)
          ? this.realizedPnl
          : realizedPnl as Decimal?,
      currency: currency ?? this.currency,
      status: status ?? this.status,
      notes: identical(notes, _unsetTradeJournalField)
          ? this.notes
          : notes as String?,
      brokerageAccountId: identical(brokerageAccountId, _unsetTradeJournalField)
          ? this.brokerageAccountId
          : brokerageAccountId as String?,
      cashAccountId: identical(cashAccountId, _unsetTradeJournalField)
          ? this.cashAccountId
          : cashAccountId as String?,
      underlyingMarket: identical(underlyingMarket, _unsetTradeJournalField)
          ? this.underlyingMarket
          : underlyingMarket as String?,
      strikePrice: identical(strikePrice, _unsetTradeJournalField)
          ? this.strikePrice
          : strikePrice as Decimal?,
      contractSize: identical(contractSize, _unsetTradeJournalField)
          ? this.contractSize
          : contractSize as int?,
      contractQuantity: contractQuantity ?? this.contractQuantity,
      sync: sync ?? this.sync,
    );
  }
}

enum TradeJournalStatus { open, closed, assigned, expired }

extension TradeJournalStatusWire on TradeJournalStatus {
  String get wire => switch (this) {
    TradeJournalStatus.open => 'open',
    TradeJournalStatus.closed => 'closed',
    TradeJournalStatus.assigned => 'assigned',
    TradeJournalStatus.expired => 'expired',
  };
}

TradeJournalStatus parseTradeJournalStatus(String wire) {
  switch (wire) {
    case 'open':
      return TradeJournalStatus.open;
    case 'closed':
      return TradeJournalStatus.closed;
    case 'assigned':
      return TradeJournalStatus.assigned;
    case 'expired':
      return TradeJournalStatus.expired;
  }
  return TradeJournalStatus.open;
}
