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
    required this.closedAt,
    required this.entryCredit,
    required this.exitDebit,
    required this.realizedPnl,
    required this.currency,
    required this.status,
    required this.notes,
    this.brokerageAccountId,
    this.cashAccountId,
    this.underlyingMarket,
    this.strikePrice,
    this.contractSize,
    required this.sync,
  });

  final String id;
  final OptionsStrategyKind strategy;
  final String symbol;
  final String optionSymbol;
  final DateTime openedAt;
  final DateTime? closedAt;

  /// Premium received when the position opened (per contract, USD = 100×
  /// the per-share credit).
  final Decimal entryCredit;

  /// Debit paid to close, or `null` if the position is still open / was
  /// assigned / expired worthless.
  final Decimal? exitDebit;

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
  final SyncMeta sync;

  TradeJournalEntry copyWith({
    OptionsStrategyKind? strategy,
    String? symbol,
    String? optionSymbol,
    DateTime? openedAt,
    Object? closedAt = _unsetTradeJournalField,
    Decimal? entryCredit,
    Object? exitDebit = _unsetTradeJournalField,
    Object? realizedPnl = _unsetTradeJournalField,
    String? currency,
    TradeJournalStatus? status,
    Object? notes = _unsetTradeJournalField,
    Object? brokerageAccountId = _unsetTradeJournalField,
    Object? cashAccountId = _unsetTradeJournalField,
    Object? underlyingMarket = _unsetTradeJournalField,
    Object? strikePrice = _unsetTradeJournalField,
    Object? contractSize = _unsetTradeJournalField,
    SyncMeta? sync,
  }) {
    return TradeJournalEntry(
      id: id,
      strategy: strategy ?? this.strategy,
      symbol: symbol ?? this.symbol,
      optionSymbol: optionSymbol ?? this.optionSymbol,
      openedAt: openedAt ?? this.openedAt,
      closedAt: identical(closedAt, _unsetTradeJournalField)
          ? this.closedAt
          : closedAt as DateTime?,
      entryCredit: entryCredit ?? this.entryCredit,
      exitDebit: identical(exitDebit, _unsetTradeJournalField)
          ? this.exitDebit
          : exitDebit as Decimal?,
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
