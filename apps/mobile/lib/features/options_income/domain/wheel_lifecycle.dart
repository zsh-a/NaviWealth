import 'package:decimal/decimal.dart';

import 'options_strategy_profile.dart';
import 'trade_journal_entry.dart';

/// Stages of the **Wheel** options-income strategy (Income Planner P4).
///
/// The Wheel cycles through:
/// `cash → short put → (expired ⇒ cash) | (assigned ⇒ shares) → short call →
///  (expired ⇒ shares) | (called away ⇒ cash)`.
///
/// `between` is the resting state immediately before the user has opened
/// their first position on a symbol, or after every position on it has
/// closed. The presentation layer typically renders it identically to
/// `cashWaiting` but keeps them separate so the lifecycle never claims a
/// position exists when it doesn't.
enum WheelStage {
  /// No position recorded yet, or every prior cycle closed and the user
  /// hasn't opened a new put.
  between,

  /// Sitting on cash earmarked for a short put — premium income paused.
  cashWaiting,

  /// A cash-secured put is currently open.
  shortPut,

  /// A put expired worthless (assignment risk passed). Transient state —
  /// the lifecycle expects the next entry to either rotate back to
  /// `cashWaiting` or start a new short put.
  putExpired,

  /// A put was assigned; the user now holds shares of the underlying.
  putAssigned,

  /// Holding shares between covered-call sales.
  sharesHeld,

  /// A covered call is currently open.
  shortCall,

  /// A covered call expired worthless — user kept shares + income.
  callExpired,

  /// Shares were called away — cycle ends and rotates back to cash.
  callCalled,
}

/// One Wheel lifecycle for a single underlying symbol.
///
/// Derived deterministically from a (chronologically-ordered) set of trade
/// journal entries; equality is by the value fields so providers can
/// distinct-stream cheaply.
class WheelLifecycle {
  const WheelLifecycle({
    required this.symbol,
    required this.currency,
    required this.stage,
    required this.openPosition,
    required this.cumulativeIncome,
    required this.entries,
  });

  /// Empty lifecycle for [symbol] — a freshly-onboarded underlying with no
  /// journal entries yet.
  factory WheelLifecycle.empty({
    required String symbol,
    required String currency,
  }) =>
      WheelLifecycle(
        symbol: symbol,
        currency: currency,
        stage: WheelStage.between,
        openPosition: null,
        cumulativeIncome: Decimal.zero,
        entries: const [],
      );

  final String symbol;
  final String currency;
  final WheelStage stage;

  /// The currently open journal entry, or `null` when the lifecycle is
  /// resting between positions.
  final TradeJournalEntry? openPosition;

  /// Sum of `entryCredit - exitDebit` across every closed entry. Open
  /// entries do not contribute until they resolve.
  final Decimal cumulativeIncome;

  /// Entries for this underlying ordered by `openedAt` ascending. Stored
  /// in the lifecycle so the UI can render the cycle's full history
  /// without re-querying.
  final List<TradeJournalEntry> entries;

  /// True when a position is open on this underlying.
  bool get hasOpenPosition => openPosition != null;

  /// True when the lifecycle holds shares (assigned but not yet called).
  bool get holdsShares =>
      stage == WheelStage.putAssigned ||
      stage == WheelStage.sharesHeld ||
      stage == WheelStage.shortCall ||
      stage == WheelStage.callExpired;
}

/// Derive a Wheel [WheelLifecycle] for [symbol] from [entries].
///
/// Mixed-symbol input is allowed — only entries matching [symbol] are
/// folded in; the rest are dropped. This lets callers hand in the
/// unfiltered journal without an intermediate group-by step.
///
/// The stage is computed from the most-recent entry's strategy + status:
/// open entries pin the stage to "short put / short call"; the **most
/// recently closed** entry pins the stage to its terminal state, except
/// when a later open entry exists for the same symbol — that wins.
WheelLifecycle buildWheelLifecycle({
  required String symbol,
  required String currency,
  required Iterable<TradeJournalEntry> entries,
}) {
  final ours = entries.where((e) => e.symbol == symbol).toList()
    ..sort((a, b) => a.openedAt.compareTo(b.openedAt));

  if (ours.isEmpty) {
    return WheelLifecycle.empty(symbol: symbol, currency: currency);
  }

  var income = Decimal.zero;
  TradeJournalEntry? openEntry;
  TradeJournalEntry? lastClosed;
  for (final entry in ours) {
    if (entry.status == TradeJournalStatus.open) {
      openEntry = entry;
      continue;
    }
    lastClosed = entry;
    final realized = entry.realizedPnl;
    if (realized != null) {
      income += realized;
      continue;
    }
    final credit = entry.entryCredit;
    final debit = entry.exitDebit ?? Decimal.zero;
    income += credit - debit;
  }

  final stage = _stageFrom(openEntry: openEntry, lastClosed: lastClosed);
  return WheelLifecycle(
    symbol: symbol,
    currency: currency,
    stage: stage,
    openPosition: openEntry,
    cumulativeIncome: income,
    entries: ours,
  );
}

WheelStage _stageFrom({
  required TradeJournalEntry? openEntry,
  required TradeJournalEntry? lastClosed,
}) {
  if (openEntry != null) {
    return switch (openEntry.strategy) {
      OptionsStrategyKind.cashSecuredPut => WheelStage.shortPut,
      OptionsStrategyKind.coveredCall => WheelStage.shortCall,
    };
  }
  if (lastClosed == null) return WheelStage.between;
  return switch (lastClosed.strategy) {
    OptionsStrategyKind.cashSecuredPut => switch (lastClosed.status) {
      TradeJournalStatus.expired => WheelStage.cashWaiting,
      TradeJournalStatus.closed => WheelStage.cashWaiting,
      TradeJournalStatus.assigned => WheelStage.putAssigned,
      TradeJournalStatus.open => WheelStage.between, // unreachable
    },
    OptionsStrategyKind.coveredCall => switch (lastClosed.status) {
      // Called away = shares left the account, lifecycle is back to cash.
      TradeJournalStatus.assigned => WheelStage.cashWaiting,
      TradeJournalStatus.expired => WheelStage.sharesHeld,
      TradeJournalStatus.closed => WheelStage.sharesHeld,
      TradeJournalStatus.open => WheelStage.between, // unreachable
    },
  };
}
