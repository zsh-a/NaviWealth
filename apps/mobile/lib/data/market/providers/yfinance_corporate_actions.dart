/// Parse [CorporateActionEvent]s out of a yfinance `chart` API response.
///
/// Pure function — no I/O, no logging. The provider layer (or any caller
/// with sample JSON) decodes the wire body and hands the decoded map in;
/// this module converts it into the domain shape that
/// `features/investment/domain/reporting/event_timeline.dart` consumes.
///
/// The yfinance chart endpoint returns events under
/// `chart.result[0].events.dividends` and `.events.splits`, each keyed by
/// the ex-date / effective-date timestamp (seconds since epoch). Parsing
/// is defensive: a missing or malformed event is **skipped**, not thrown,
/// because Yahoo schema drift is documented (`yfinance_provider.dart`
/// header) and we don't want one stale row to wipe the whole batch.
library;

import 'package:decimal/decimal.dart';

import '../../../features/investment/domain/reporting/event_timeline.dart';

/// Parse all dividend + split corporate actions out of [responseBody]
/// for [symbol]. Returns an empty list when the response has no events,
/// is malformed, or carries data for a different symbol.
///
/// [currency] supplies the cash leg's currency. Yahoo doesn't include
/// currency on per-event records, so the caller pulls it out of
/// `chart.result[0].meta.currency` and passes it through.
List<CorporateActionEvent> parseYahooCorporateActions({
  required Map<String, Object?> responseBody,
  required String symbol,
  required String currency,
}) {
  final result = _firstResult(responseBody);
  if (result == null) return const [];

  final events = result['events'];
  if (events is! Map) return const [];

  final upperSymbol = symbol.toUpperCase();
  final out = <CorporateActionEvent>[];

  final dividends = events['dividends'];
  if (dividends is Map) {
    for (final entry in dividends.entries) {
      final ev = _parseDividend(entry.value, upperSymbol, currency);
      if (ev != null) out.add(ev);
    }
  }

  final splits = events['splits'];
  if (splits is Map) {
    for (final entry in splits.entries) {
      final ev = _parseSplit(entry.value, upperSymbol, currency);
      if (ev != null) out.add(ev);
    }
  }

  return out;
}

Map<String, Object?>? _firstResult(Map<String, Object?> body) {
  final chart = body['chart'];
  if (chart is! Map) return null;
  final results = chart['result'];
  if (results is! List || results.isEmpty) return null;
  final first = results.first;
  if (first is! Map) return null;
  return first.cast<String, Object?>();
}

CorporateActionEvent? _parseDividend(
  Object? raw,
  String symbol,
  String currency,
) {
  if (raw is! Map) return null;
  final date = _epochSecondsAsUtc(raw['date']);
  final amount = _decimal(raw['amount']);
  if (date == null || amount == null) return null;
  return CorporateActionEvent(
    id: 'div_${symbol}_${date.toIso8601String().substring(0, 10)}',
    symbol: symbol,
    kind: CorporateActionKind.cashDividend,
    scheduledFor: date,
    cashAmount: amount,
    currency: currency,
  );
}

CorporateActionEvent? _parseSplit(Object? raw, String symbol, String currency) {
  if (raw is! Map) return null;
  final date = _epochSecondsAsUtc(raw['date']);
  if (date == null) return null;
  final numerator = _intOrNull(raw['numerator']);
  final denominator = _intOrNull(raw['denominator']);
  if (numerator == null ||
      denominator == null ||
      numerator <= 0 ||
      denominator <= 0) {
    return null;
  }
  return CorporateActionEvent(
    id: 'split_${symbol}_${date.toIso8601String().substring(0, 10)}',
    symbol: symbol,
    kind: CorporateActionKind.split,
    scheduledFor: date,
    cashAmount: Decimal.zero,
    currency: currency,
    ratio: SplitRatio(numerator, denominator),
  );
}

DateTime? _epochSecondsAsUtc(Object? raw) {
  final n = _intOrNull(raw);
  if (n == null || n <= 0) return null;
  final utc = DateTime.fromMillisecondsSinceEpoch(n * 1000, isUtc: true);
  // The event timeline keys events by calendar day — drop the wall-clock
  // component so 23:59 UTC and 00:00 UTC of the same day collide.
  return DateTime.utc(utc.year, utc.month, utc.day);
}

Decimal? _decimal(Object? raw) {
  if (raw is num) return Decimal.parse(raw.toString());
  if (raw is String) return Decimal.tryParse(raw);
  return null;
}

int? _intOrNull(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw);
  return null;
}
