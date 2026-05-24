import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/investment/domain/reporting/event_timeline.dart';

CorporateActionEvent _event({
  String id = 'e',
  String symbol = 'AAPL',
  CorporateActionKind kind = CorporateActionKind.cashDividend,
  required DateTime scheduledFor,
  String cashAmount = '0',
  String currency = 'USD',
  SplitRatio? ratio,
}) =>
    CorporateActionEvent(
      id: id,
      symbol: symbol,
      kind: kind,
      scheduledFor: scheduledFor,
      cashAmount: Decimal.parse(cashAmount),
      currency: currency,
      ratio: ratio,
    );

void main() {
  group('buildEventTimeline', () {
    final today = DateTime.utc(2026, 5, 24);

    test('returns only events for watched symbols', () {
      final out = buildEventTimeline(
        events: [
          _event(
            id: 'a1',
            symbol: 'AAPL',
            scheduledFor: today.add(const Duration(days: 5)),
            cashAmount: '0.24',
          ),
          _event(
            id: 'g1',
            symbol: 'GOOGL',
            scheduledFor: today.add(const Duration(days: 7)),
          ),
        ],
        watchedSymbols: {'AAPL'},
        from: today,
      );
      expect(out.map((e) => e.id), ['a1']);
    });

    test('filters out events before today', () {
      final out = buildEventTimeline(
        events: [
          _event(
            id: 'old',
            scheduledFor: today.subtract(const Duration(days: 1)),
          ),
          _event(
            id: 'new',
            scheduledFor: today.add(const Duration(days: 1)),
          ),
        ],
        watchedSymbols: {'AAPL'},
        from: today,
      );
      expect(out.map((e) => e.id), ['new']);
    });

    test('includes events scheduled today (lower bound is inclusive)', () {
      final out = buildEventTimeline(
        events: [_event(id: 'today', scheduledFor: today)],
        watchedSymbols: {'AAPL'},
        from: today,
      );
      expect(out, hasLength(1));
    });

    test('excludes events outside the window (upper bound exclusive)', () {
      final out = buildEventTimeline(
        events: [
          _event(
            id: 'in',
            scheduledFor: today.add(const Duration(days: 89)),
          ),
          _event(
            id: 'edge',
            scheduledFor: today.add(const Duration(days: 90)),
          ),
          _event(
            id: 'out',
            scheduledFor: today.add(const Duration(days: 91)),
          ),
        ],
        watchedSymbols: {'AAPL'},
        from: today,
        windowDays: 90,
      );
      expect(out.map((e) => e.id), ['in']);
    });

    test('sorts chronologically and tie-breaks by symbol', () {
      final out = buildEventTimeline(
        events: [
          _event(
            id: 'z',
            symbol: 'ZNGA',
            scheduledFor: today.add(const Duration(days: 5)),
          ),
          _event(
            id: 'a',
            symbol: 'AAPL',
            scheduledFor: today.add(const Duration(days: 5)),
          ),
          _event(
            id: 'aapl-earlier',
            symbol: 'AAPL',
            scheduledFor: today.add(const Duration(days: 2)),
          ),
        ],
        watchedSymbols: {'AAPL', 'ZNGA'},
        from: today,
      );
      expect(out.map((e) => e.id), ['aapl-earlier', 'a', 'z']);
    });

    test('deduplicates by id', () {
      final out = buildEventTimeline(
        events: [
          _event(
            id: 'div-2026-q2',
            scheduledFor: today.add(const Duration(days: 5)),
          ),
          _event(
            id: 'div-2026-q2',
            scheduledFor: today.add(const Duration(days: 5)),
          ),
        ],
        watchedSymbols: {'AAPL'},
        from: today,
      );
      expect(out, hasLength(1));
    });

    test('watched symbols are case-insensitive', () {
      final out = buildEventTimeline(
        events: [
          _event(
            id: 'a',
            symbol: 'aapl',
            scheduledFor: today.add(const Duration(days: 5)),
          ),
        ],
        watchedSymbols: {'AAPL'},
        from: today,
      );
      expect(out, hasLength(1));
    });

    test('rejects non-positive windowDays', () {
      expect(
        () => buildEventTimeline(
          events: const [],
          watchedSymbols: const {},
          from: today,
          windowDays: 0,
        ),
        throwsArgumentError,
      );
    });

    test('SplitRatio classifies forward / reverse', () {
      expect(const SplitRatio(4, 1).isForward, isTrue);
      expect(const SplitRatio(4, 1).isReverse, isFalse);
      expect(const SplitRatio(1, 5).isReverse, isTrue);
      expect(const SplitRatio(1, 5).isForward, isFalse);
      expect(const SplitRatio(4, 1).toString(), '4-for-1');
    });
  });
}
