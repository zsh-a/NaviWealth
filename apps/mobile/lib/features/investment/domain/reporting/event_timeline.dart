/// Investment "Event timeline" — corporate actions that affect holdings
/// (dividend / split / rights) projected onto a chronological list.
///
/// MT-2.2.M2.1 (`docs/roadmap-midterm-execution.md`). Pure domain:
/// callers hand in a flat list of observed/announced events, the builder
/// filters by symbol set, sorts, and trims to a window. Market-data
/// providers are out of scope here — they sit in `data/market/` and feed
/// this layer the events they discover.
library;

import 'package:decimal/decimal.dart';

/// One scheduled or executed corporate action on a single symbol.
class CorporateActionEvent {
  const CorporateActionEvent({
    required this.id,
    required this.symbol,
    required this.kind,
    required this.scheduledFor,
    required this.cashAmount,
    required this.currency,
    this.ratio,
    this.note,
  });

  /// Stable id — the provider's own event id when available, otherwise a
  /// hash of `(symbol, kind, scheduledFor)` so dedup survives re-fetches.
  final String id;

  /// Ticker / option underlying, uppercased.
  final String symbol;

  final CorporateActionKind kind;

  /// Ex-dividend date / split effective date / rights record date —
  /// whatever the user cares about per [kind]. Stored as UTC date-only
  /// (the time component is ignored on render).
  final DateTime scheduledFor;

  /// Per-share cash component, in [currency]. Zero for non-cash events
  /// (split / rights without cash leg).
  final Decimal cashAmount;

  /// ISO 4217 currency code for [cashAmount].
  final String currency;

  /// Split / rights ratio (e.g. `4/1` for a 4-for-1 split). `null` for
  /// pure-cash dividends.
  final SplitRatio? ratio;

  final String? note;
}

/// What kind of corporate action this row records.
enum CorporateActionKind {
  /// Cash dividend (regular or special). `cashAmount` is per share.
  cashDividend,

  /// Forward / reverse split. `ratio` carries the numerator/denominator.
  split,

  /// Rights offering. `cashAmount` is the subscription price per right.
  rights,

  /// DRIP — dividend reinvested into shares. `cashAmount` is the cash
  /// value reinvested; `ratio` is the resulting share fraction.
  drip,
}

extension CorporateActionKindWire on CorporateActionKind {
  String get wire => switch (this) {
        CorporateActionKind.cashDividend => 'cash_dividend',
        CorporateActionKind.split => 'split',
        CorporateActionKind.rights => 'rights',
        CorporateActionKind.drip => 'drip',
      };
}

/// Split numerator / denominator. e.g. `SplitRatio(4, 1)` for 4-for-1.
class SplitRatio {
  const SplitRatio(this.numerator, this.denominator)
      : assert(numerator > 0 && denominator > 0,
            'split ratio must be positive');
  final int numerator;
  final int denominator;

  bool get isForward => numerator > denominator;
  bool get isReverse => numerator < denominator;

  @override
  String toString() => '$numerator-for-$denominator';
}

/// Project a chronological timeline of upcoming corporate actions for the
/// supplied [watchedSymbols] set.
///
/// - **Filters** to events whose `symbol` is in [watchedSymbols].
/// - **Filters** to events occurring on/after [from] (default: today UTC).
/// - **Filters** out events more than [windowDays] in the future.
/// - **Sorts** by `scheduledFor` ascending, then by symbol for stability.
/// - **Drops duplicates** by `id` (provider re-fetches must not double-count).
List<CorporateActionEvent> buildEventTimeline({
  required Iterable<CorporateActionEvent> events,
  required Set<String> watchedSymbols,
  DateTime? from,
  int windowDays = 90,
}) {
  if (windowDays <= 0) {
    throw ArgumentError.value(
      windowDays,
      'windowDays',
      'must be > 0',
    );
  }
  final lowerBound = _dateFloor(from ?? DateTime.now().toUtc());
  final upperBound = lowerBound.add(Duration(days: windowDays));
  final normalised = watchedSymbols.map((s) => s.toUpperCase()).toSet();

  final seen = <String>{};
  final out = <CorporateActionEvent>[];
  for (final event in events) {
    if (!normalised.contains(event.symbol.toUpperCase())) continue;
    final when = _dateFloor(event.scheduledFor);
    if (when.isBefore(lowerBound)) continue;
    if (!when.isBefore(upperBound)) continue;
    if (!seen.add(event.id)) continue;
    out.add(event);
  }
  out.sort((a, b) {
    final byDate = a.scheduledFor.compareTo(b.scheduledFor);
    if (byDate != 0) return byDate;
    return a.symbol.compareTo(b.symbol);
  });
  return out;
}

DateTime _dateFloor(DateTime dt) {
  final utc = dt.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}
