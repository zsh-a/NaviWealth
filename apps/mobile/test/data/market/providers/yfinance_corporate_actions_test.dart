import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/data/market/providers/yfinance_corporate_actions.dart';
import 'package:naviwealth/features/investment/domain/reporting/event_timeline.dart';

const _exDivTs1 = 1714521600; // 2024-05-01 UTC
const _exDivTs2 = 1722470400; // 2024-08-01 UTC
const _splitTs = 1659384000; // 2022-08-02 UTC

Map<String, Object?> _chart({
  Map<String, Object?>? events,
}) {
  final result = <String, Object?>{
    'meta': <String, Object?>{'symbol': 'AAPL'},
  };
  if (events != null) result['events'] = events;
  return <String, Object?>{
    'chart': <String, Object?>{
      'result': <Object?>[result],
    },
  };
}

void main() {
  group('parseYahooCorporateActions', () {
    test('returns empty when body is missing chart.result', () {
      expect(
        parseYahooCorporateActions(
          responseBody: const {},
          symbol: 'AAPL',
          currency: 'USD',
        ),
        isEmpty,
      );
    });

    test('returns empty when result has no events block', () {
      expect(
        parseYahooCorporateActions(
          responseBody: _chart(),
          symbol: 'AAPL',
          currency: 'USD',
        ),
        isEmpty,
      );
    });

    test('parses dividend events into cashDividend rows', () {
      final out = parseYahooCorporateActions(
        responseBody: _chart(
          events: <String, Object?>{
            'dividends': <String, Object?>{
              '$_exDivTs1': <String, Object?>{
                'date': _exDivTs1,
                'amount': 0.22,
              },
              '$_exDivTs2': <String, Object?>{
                'date': _exDivTs2,
                'amount': 0.24,
              },
            },
          },
        ),
        symbol: 'aapl',
        currency: 'USD',
      );
      expect(out, hasLength(2));
      for (final e in out) {
        expect(e.symbol, 'AAPL');
        expect(e.kind, CorporateActionKind.cashDividend);
        expect(e.currency, 'USD');
        expect(e.ratio, isNull);
      }
      final amounts = out.map((e) => e.cashAmount).toList();
      expect(amounts, containsAll([Decimal.parse('0.22'), Decimal.parse('0.24')]));
    });

    test('parses split events with numerator/denominator', () {
      final out = parseYahooCorporateActions(
        responseBody: _chart(
          events: <String, Object?>{
            'splits': <String, Object?>{
              '$_splitTs': <String, Object?>{
                'date': _splitTs,
                'numerator': 20,
                'denominator': 1,
                'splitRatio': '20:1',
              },
            },
          },
        ),
        symbol: 'AAPL',
        currency: 'USD',
      );
      final ev = out.single;
      expect(ev.kind, CorporateActionKind.split);
      expect(ev.cashAmount, Decimal.zero);
      expect(ev.ratio?.numerator, 20);
      expect(ev.ratio?.denominator, 1);
      expect(ev.ratio?.isForward, isTrue);
    });

    test('drops malformed dividend / split rows instead of throwing', () {
      final out = parseYahooCorporateActions(
        responseBody: _chart(
          events: <String, Object?>{
            'dividends': <String, Object?>{
              'broken_no_amount': <String, Object?>{'date': _exDivTs1},
              'broken_negative_date': <String, Object?>{
                'date': -1,
                'amount': 0.10,
              },
              'broken_string_date': <String, Object?>{
                'date': 'tomorrow',
                'amount': 0.10,
              },
              'good': <String, Object?>{'date': _exDivTs1, 'amount': 0.10},
            },
            'splits': <String, Object?>{
              'broken_no_num': <String, Object?>{
                'date': _splitTs,
                'denominator': 1,
              },
              'broken_zero': <String, Object?>{
                'date': _splitTs,
                'numerator': 0,
                'denominator': 1,
              },
              'good': <String, Object?>{
                'date': _splitTs,
                'numerator': 4,
                'denominator': 1,
              },
            },
          },
        ),
        symbol: 'AAPL',
        currency: 'USD',
      );
      expect(out, hasLength(2));
      expect(
        out.map((e) => e.kind).toSet(),
        {CorporateActionKind.cashDividend, CorporateActionKind.split},
      );
    });

    test('event ids are deterministic so re-fetch dedups in the timeline', () {
      Map<String, Object?> body() => _chart(
            events: <String, Object?>{
              'dividends': <String, Object?>{
                '$_exDivTs1': <String, Object?>{
                  'date': _exDivTs1,
                  'amount': 0.22,
                },
              },
            },
          );
      final first = parseYahooCorporateActions(
        responseBody: body(),
        symbol: 'AAPL',
        currency: 'USD',
      );
      final second = parseYahooCorporateActions(
        responseBody: body(),
        symbol: 'AAPL',
        currency: 'USD',
      );
      expect(first.single.id, second.single.id);
      // The id format is also stable enough to compose with the timeline
      // dedup keyed on `id`.
      expect(first.single.id, startsWith('div_AAPL_'));
    });

    test('scheduledFor floors to UTC calendar day', () {
      final out = parseYahooCorporateActions(
        responseBody: _chart(
          events: <String, Object?>{
            'dividends': <String, Object?>{
              '$_exDivTs1': <String, Object?>{
                // Same calendar day, 23:59:59 UTC — should still floor to
                // 00:00 of the same day.
                'date': _exDivTs1 + 86399,
                'amount': 0.22,
              },
            },
          },
        ),
        symbol: 'AAPL',
        currency: 'USD',
      );
      final ev = out.single;
      expect(ev.scheduledFor.hour, 0);
      expect(ev.scheduledFor.minute, 0);
      expect(ev.scheduledFor.second, 0);
      expect(ev.scheduledFor.isUtc, isTrue);
    });
  });
}
