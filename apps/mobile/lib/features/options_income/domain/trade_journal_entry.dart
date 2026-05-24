import 'package:decimal/decimal.dart';

import '../../../data/domain/sync_meta.dart';
import 'options_strategy_profile.dart';

/// One row of the user's options trade journal.
///
/// Created from a successful sell, mutated when the position closes (or is
/// assigned / expires). The entry is synced — every device sees the same
/// journal — per `docs/options-income.md` §6.2.
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
  final SyncMeta sync;

  TradeJournalEntry copyWith({
    OptionsStrategyKind? strategy,
    String? symbol,
    String? optionSymbol,
    DateTime? openedAt,
    DateTime? closedAt,
    Decimal? entryCredit,
    Decimal? exitDebit,
    Decimal? realizedPnl,
    String? currency,
    TradeJournalStatus? status,
    String? notes,
    SyncMeta? sync,
  }) {
    return TradeJournalEntry(
      id: id,
      strategy: strategy ?? this.strategy,
      symbol: symbol ?? this.symbol,
      optionSymbol: optionSymbol ?? this.optionSymbol,
      openedAt: openedAt ?? this.openedAt,
      closedAt: closedAt ?? this.closedAt,
      entryCredit: entryCredit ?? this.entryCredit,
      exitDebit: exitDebit ?? this.exitDebit,
      realizedPnl: realizedPnl ?? this.realizedPnl,
      currency: currency ?? this.currency,
      status: status ?? this.status,
      notes: notes ?? this.notes,
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
