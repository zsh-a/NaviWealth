/// First production caller of the Memory Runtime
/// (`docs/lifeos-shell.md` §6, D-1.7b).
///
/// For each [TradeJournalEntry] this indexer emits **two** kinds of
/// records:
///
/// 1. **Always** an [EventRecord] in the cross-domain event log:
///    `trade_opened` for live positions, `trade_closed` /
///    `trade_assigned` / `trade_expired` for terminal ones. Events are
///    cheap, abundant; they feed `ContextPack.recentEvents`.
/// 2. **For terminal positions only** an episodic [MemoryRecord]
///    capturing the decision shape: `{context, decision, reasoning,
///    outcome}`. This is what makes "去年这个时候为什么卖 NVDA put"
///    answerable with actual reasoning, not embedded prose.
///
/// Importance heuristic (terminal episodes):
///
/// - assigned (had to take shares) → 0.75 (high — capital allocated)
/// - closed early with realised P&L → 0.6
/// - expired worthless → 0.5
/// - with user notes attached → +0.1 (max 0.95)
///
/// No semantic / procedural extraction yet — those require pattern
/// detection across many entries and are deferred to a later pass.
library;

import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/contracts/event_record.dart';
import '../../../core/ai/contracts/memory_record.dart';
import '../../../core/ai/local/memory/memory_runtime.dart';
import '../../../core/ai/local/memory/providers.dart';
import '../../../data/repositories/mutation_context.dart';
import '../domain/options_strategy_profile.dart';
import '../domain/trade_journal_entry.dart';
import 'providers.dart';

/// Stable cross-source label so [ContextPack] can filter ("only
/// options memories") without enum'ing in core.
const String kTradeJournalSource = 'options_trade_journal';

/// Event types this indexer emits. Free-form strings on the wire;
/// constants here for local consistency.
const String kEventTradeOpened = 'trade_opened';
const String kEventTradeClosed = 'trade_closed';
const String kEventTradeAssigned = 'trade_assigned';
const String kEventTradeExpired = 'trade_expired';

class TradeJournalMemoryIndexer {
  TradeJournalMemoryIndexer({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  /// Re-index every supplied entry. Idempotent — repeated calls with
  /// the same input overwrite the same rows (events and memories are
  /// both upserted by stable id).
  ///
  /// Returns `(events, memories)` written.
  Future<({int events, int memories})> reindex(
    MemoryRuntime runtime,
    Iterable<TradeJournalEntry> entries, {
    required String ownerUserId,
  }) async {
    var events = 0;
    var memories = 0;
    final now = _clock();
    for (final entry in entries) {
      await runtime.recordEvent(_eventFor(entry, ownerUserId));
      events++;
      final memory = _episodicMemoryFor(entry, ownerUserId, now: now);
      if (memory != null) {
        await runtime.remember(memory);
        memories++;
      }
    }
    return (events: events, memories: memories);
  }

  EventRecord _eventFor(TradeJournalEntry entry, String ownerUserId) {
    final type = _eventType(entry.status);
    return EventRecord(
      id: '$kTradeJournalSource:$type:${entry.id}',
      type: type,
      timestamp: entry.closedAt?.toUtc() ?? entry.openedAt.toUtc(),
      source: kTradeJournalSource,
      ownerUserId: ownerUserId,
      title: '${entry.symbol} · ${entry.strategy.wire}',
      summary: _eventSummary(entry, type),
      payload: <String, Object?>{
        'strategy': entry.strategy.wire,
        'symbol': entry.symbol,
        'option_symbol': entry.optionSymbol,
        'currency': entry.currency,
        'entry_credit': entry.entryCredit.toString(),
        if (entry.exitDebit != null) 'exit_debit': entry.exitDebit!.toString(),
        if (entry.realizedPnl != null)
          'realized_pnl': entry.realizedPnl!.toString(),
        'status': entry.status.wire,
        'opened_at': entry.openedAt.toUtc().toIso8601String(),
        if (entry.closedAt != null)
          'closed_at': entry.closedAt!.toUtc().toIso8601String(),
      },
      entities: _entitiesFor(entry),
      importance: _eventImportance(entry),
    );
  }

  /// Returns `null` when the entry isn't worth an episodic memory yet
  /// (open positions don't have an outcome).
  MemoryRecord? _episodicMemoryFor(
    TradeJournalEntry entry,
    String ownerUserId, {
    required DateTime now,
  }) {
    if (entry.status == TradeJournalStatus.open) return null;
    final outcomeWire = entry.status.wire;
    final notes = entry.notes?.trim();
    final hasNotes = notes != null && notes.isNotEmpty;
    final pnl = entry.realizedPnl;
    final eventId =
        '$kTradeJournalSource:${_eventType(entry.status)}:${entry.id}';
    final memoryId = '$kTradeJournalSource:episodic:${entry.id}';
    return MemoryRecord(
      id: memoryId,
      kind: MemoryKind.episodic,
      ownerUserId: ownerUserId,
      scope: 'options_trading',
      source: kTradeJournalSource,
      sourceId: entry.id,
      sourceEventId: eventId,
      title: '${entry.symbol} · ${entry.strategy.wire} → $outcomeWire',
      summary: _episodicSummary(entry),
      payload: <String, Object?>{
        'context': _episodicContext(entry),
        'decision': '${entry.strategy.wire} on ${entry.symbol}',
        'reasoning': hasNotes ? notes : null,
        'outcome': <String, Object?>{
          'status': outcomeWire,
          if (pnl != null) 'realized_pnl': pnl.toString(),
          'currency': entry.currency,
        },
      },
      entities: _entitiesFor(entry),
      importance: _episodicImportance(entry),
      confidence: hasNotes ? 0.9 : 0.75,
      validFrom: entry.openedAt.toUtc(),
      // No validUntil — historical decisions stay valid forever as
      // reference material.
      createdAt: now,
      updatedAt: now,
    );
  }

  String _eventType(TradeJournalStatus s) => switch (s) {
        TradeJournalStatus.open => kEventTradeOpened,
        TradeJournalStatus.closed => kEventTradeClosed,
        TradeJournalStatus.assigned => kEventTradeAssigned,
        TradeJournalStatus.expired => kEventTradeExpired,
      };

  String _eventSummary(TradeJournalEntry entry, String type) {
    final base = '${entry.strategy.wire} on ${entry.symbol} (${entry.optionSymbol})';
    final whenIso =
        (entry.closedAt ?? entry.openedAt).toUtc().toIso8601String();
    switch (type) {
      case kEventTradeOpened:
        return '$base opened $whenIso for credit ${entry.entryCredit} ${entry.currency}.';
      case kEventTradeClosed:
        final pnl = entry.realizedPnl;
        return '$base closed $whenIso${pnl == null ? '' : ', realised $pnl ${entry.currency}'}.';
      case kEventTradeAssigned:
        return '$base assigned $whenIso (took delivery).';
      case kEventTradeExpired:
        return '$base expired $whenIso worthless.';
      default:
        return base;
    }
  }

  String _episodicSummary(TradeJournalEntry entry) {
    final notes = entry.notes?.trim();
    final pnl = entry.realizedPnl;
    final outcome = switch (entry.status) {
      TradeJournalStatus.closed =>
        pnl == null ? 'closed' : 'closed with P&L $pnl ${entry.currency}',
      TradeJournalStatus.assigned => 'assigned (took shares)',
      TradeJournalStatus.expired => 'expired worthless',
      TradeJournalStatus.open => 'open',
    };
    return [
      '${entry.strategy.wire} on ${entry.symbol} opened ${entry.openedAt.toUtc().toIso8601String()} for credit ${entry.entryCredit} ${entry.currency}.',
      'Outcome: $outcome.',
      if (notes != null && notes.isNotEmpty) 'Reasoning: $notes',
    ].join(' ');
  }

  String _episodicContext(TradeJournalEntry entry) =>
      '${entry.strategy.wire} ${entry.optionSymbol} opened ${entry.openedAt.toUtc().toIso8601String()} for credit ${entry.entryCredit} ${entry.currency}.';

  Set<String> _entitiesFor(TradeJournalEntry entry) => <String>{
        entry.symbol,
        entry.optionSymbol,
        entry.strategy.wire,
        entry.currency,
      };

  double _eventImportance(TradeJournalEntry entry) {
    switch (entry.status) {
      case TradeJournalStatus.open:
        return 0.45;
      case TradeJournalStatus.closed:
        return 0.55;
      case TradeJournalStatus.assigned:
        return 0.75;
      case TradeJournalStatus.expired:
        return 0.5;
    }
  }

  double _episodicImportance(TradeJournalEntry entry) {
    var imp = switch (entry.status) {
      TradeJournalStatus.assigned => 0.75,
      TradeJournalStatus.closed => 0.6,
      TradeJournalStatus.expired => 0.5,
      TradeJournalStatus.open => 0.0,
    };
    final notes = entry.notes?.trim();
    if (notes != null && notes.isNotEmpty) imp += 0.1;
    // Outsized P&L magnitudes nudge importance up. Heuristic: |pnl| in
    // entry-credit units is rough proxy for "this matters to remember".
    final pnl = entry.realizedPnl;
    if (pnl != null && entry.entryCredit > Decimal.zero) {
      final ratio = pnl.abs() / entry.entryCredit;
      if (ratio.toDouble() >= 1.0) imp += 0.05;
    }
    return imp.clamp(0.0, 0.95);
  }
}

/// Provider that wires the indexer to the trade journal stream. Holds
/// the subscription for app lifetime so a single boot-time read is
/// enough to keep the runtime current.
///
/// Subscribes at the repo layer (not the autoDispose stream provider)
/// so subscription lifecycle is owned here, not by transient UI
/// consumers.
final tradeJournalMemoryIndexerProvider =
    Provider<TradeJournalMemoryIndexer>((ref) {
  final indexer = TradeJournalMemoryIndexer();
  var running = false;

  Future<void> reindexNow(List<TradeJournalEntry> entries) async {
    if (running) return;
    running = true;
    try {
      final runtime = await ref.read(memoryRuntimeProvider.future);
      final userId = await ref.read(currentUserIdProvider)();
      await indexer.reindex(runtime, entries, ownerUserId: userId);
    } finally {
      running = false;
    }
  }

  () async {
    final repo = await ref.read(tradeJournalRepositoryProvider.future);
    final userId = await ref.read(currentUserIdProvider)();
    final sub = repo.watchActive(userId).listen((entries) {
      // ignore: discarded_futures
      reindexNow(entries);
    });
    ref.onDispose(sub.cancel);
  }();

  return indexer;
});
