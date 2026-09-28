import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/data/market/providers/yfinance_corporate_actions.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/market_corporate_action.dart';

const _exDivTs1 = 1714521600; // 2024-05-01 UTC
const _exDivTs2 = 1722470400; // 2024-08-01 UTC
const _splitTs = 1659384000; // 2022-08-02 UTC

Map<String, Object?> _chart({Map<String, Object?>? events}) {
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
  group('parseYahooMarketCorporateActions', () {
    test('invalid chart returns no actions', () {
      expect(
        parseYahooMarketCorporateActions(
          responseBody: const {},
          symbol: 'AAPL',
          currency: 'USD',
          market: AssetMarket.usStock,
        ).actions,
        isEmpty,
      );
    });

    test('returns empty when result has no events block', () {
      expect(
        parseYahooMarketCorporateActions(
          responseBody: _chart(),
          symbol: 'AAPL',
          currency: 'USD',
          market: AssetMarket.usStock,
        ).actions,
        isEmpty,
      );
    });

    test('parses dividend distributions without timeline projection', () {
      final out = parseYahooMarketCorporateActions(
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
        market: AssetMarket.usStock,
      ).actions;
      expect(out, hasLength(2));
      for (final e in out) {
        expect(e.symbol, 'AAPL');
        expect(e.kind, MarketCorporateActionKind.distribution);
        expect(e.currency, 'USD');
        expect(e.splitNumerator, isNull);
      }
      final amounts = out.map((e) => e.cashPerShare).toList();
      expect(
        amounts,
        containsAll([Decimal.parse('0.22'), Decimal.parse('0.24')]),
      );
    });

    test('parses split events with numerator/denominator', () {
      final out = parseYahooMarketCorporateActions(
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
        market: AssetMarket.usStock,
      ).actions;
      final ev = out.single;
      expect(ev.kind, MarketCorporateActionKind.split);
      expect(ev.cashPerShare, isNull);
      expect(ev.splitNumerator, 20);
      expect(ev.splitDenominator, 1);
    });

    test('drops malformed dividend / split rows instead of throwing', () {
      final out = parseYahooMarketCorporateActions(
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
        market: AssetMarket.usStock,
      ).actions;
      expect(out, hasLength(2));
      expect(out.map((e) => e.kind).toSet(), {
        MarketCorporateActionKind.distribution,
        MarketCorporateActionKind.split,
      });
    });

    test('event ids are deterministic across re-fetches', () {
      Map<String, Object?> body() => _chart(
        events: <String, Object?>{
          'dividends': <String, Object?>{
            '$_exDivTs1': <String, Object?>{'date': _exDivTs1, 'amount': 0.22},
          },
        },
      );
      final first = parseYahooMarketCorporateActions(
        responseBody: body(),
        symbol: 'AAPL',
        currency: 'USD',
        market: AssetMarket.usStock,
      ).actions;
      final second = parseYahooMarketCorporateActions(
        responseBody: body(),
        symbol: 'AAPL',
        currency: 'USD',
        market: AssetMarket.usStock,
      ).actions;
      expect(first.single.id, second.single.id);
      // Source-scoped ids preserve provider identity across re-fetches.
      expect(first.single.id, startsWith('yfinance:yahoo_chart:div:AAPL:'));
    });

    test('detailed parser distinguishes malformed envelopes', () {
      final parsed = parseYahooMarketCorporateActions(
        responseBody: const <String, Object?>{},
        symbol: 'AAPL',
        currency: 'USD',
        market: AssetMarket.usStock,
      );
      expect(parsed.envelopeValid, isFalse);
      expect(parsed.actions, isEmpty);
      expect(parsed.errorMessage, isNotNull);
    });

    test('detailed parser reports mixed malformed rows as partial data', () {
      final parsed = parseYahooMarketCorporateActions(
        responseBody: _chart(
          events: <String, Object?>{
            'dividends': <String, Object?>{
              'bad': <String, Object?>{'date': _exDivTs1},
              'good': <String, Object?>{'date': _exDivTs1, 'amount': 0.22},
            },
          },
        ),
        symbol: 'AAPL',
        currency: 'USD',
        market: AssetMarket.usStock,
      );
      expect(parsed.envelopeValid, isTrue);
      expect(parsed.actions, hasLength(1));
      expect(parsed.droppedRows, 1);
    });

    test('same-day provider event keys retain distinct identities', () {
      final parsed = parseYahooMarketCorporateActions(
        responseBody: _chart(
          events: <String, Object?>{
            'dividends': <String, Object?>{
              'event-a': <String, Object?>{'date': _exDivTs1, 'amount': 0.22},
              'event-b': <String, Object?>{'date': _exDivTs1, 'amount': 0.03},
            },
          },
        ),
        symbol: 'AAPL',
        currency: 'USD',
        market: AssetMarket.usStock,
      );
      expect(parsed.actions, hasLength(2));
      expect(parsed.actions.map((action) => action.id).toSet(), hasLength(2));
    });

    test('exDate floors to UTC calendar day', () {
      final out = parseYahooMarketCorporateActions(
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
        market: AssetMarket.usStock,
      ).actions;
      final ev = out.single;
      expect(ev.exDate!.hour, 0);
      expect(ev.exDate!.minute, 0);
      expect(ev.exDate!.second, 0);
      expect(ev.exDate!.isUtc, isTrue);
    });
  });
}
