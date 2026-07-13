import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/investment/domain/holding_price_source.dart';
import 'package:naviwealth/features/finance/market/domain/price_confidence.dart';
import 'package:naviwealth/features/finance/market/domain/resolved_price.dart';

void main() {
  test(
    'resolved source never leaks a future observation into an as-of read',
    () {
      final historicalAsOf = DateTime.utc(2026, 1, 1, 23, 59);
      final liveAsOf = DateTime.utc(2026, 1, 2, 8);
      final fallback = InMemoryHoldingPriceSource([
        HoldingPriceObservation(
          assetId: 'AAPL',
          price: Decimal.fromInt(100),
          currency: 'USD',
          asOf: DateTime.utc(2026, 1, 1),
          confidence: PriceConfidence.dailyClose,
          source: 'historical',
        ),
      ]);
      final source = ResolvedPriceHoldingSource(
        resolved: {
          'AAPL': ResolvedPrice(
            value: Decimal.fromInt(200),
            currency: 'USD',
            confidence: PriceConfidence.realTime,
            source: 'live',
            asOf: liveAsOf,
            fetchedAt: liveAsOf,
          ),
        },
        resolvedAt: liveAsOf,
        fallback: fallback,
      );

      final price = source.priceFor('AAPL', asOf: historicalAsOf);

      expect(price, isNotNull);
      expect(price!.price, Decimal.fromInt(100));
      expect(price.source, 'historical');
      expect(price.asOf, DateTime.utc(2026, 1, 1));
    },
  );
}
