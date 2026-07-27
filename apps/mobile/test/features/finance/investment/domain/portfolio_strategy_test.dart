import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/investment/domain/strategy/portfolio_strategy.dart';

void main() {
  final registry = PortfolioStrategyRegistry.standard();

  test('built-in settings round-trip through their versioned codec', () {
    const settings = DividendIncomeStrategySettings(
      reinvestDividends: true,
      preservePositions: false,
    );

    final payload = registry.encode(
      PortfolioStrategyKind.dividendIncome,
      settings,
    );
    final decoded = registry.decode(
      kind: PortfolioStrategyKind.dividendIncome,
      schemaVersion: 1,
      payload: payload,
    );

    expect(decoded, isA<DividendIncomeStrategySettings>());
    expect(
      (decoded as DividendIncomeStrategySettings).reinvestDividends,
      isTrue,
    );
    expect(decoded.preservePositions, isFalse);
  });

  test('unknown strategy identifiers remain lossless opaque values', () {
    const kind = PortfolioStrategyKind('future_factor_strategy');
    final decoded = registry.decode(
      kind: kind,
      schemaVersion: 7,
      payload: const {
        'factor': 'quality',
        'constraints': <Object?>['low_turnover'],
      },
    );

    expect(decoded, isA<OpaquePortfolioStrategySettings>());
    expect(registry.encode(kind, decoded), {
      'factor': 'quality',
      'constraints': <Object?>['low_turnover'],
    });
  });

  test('registered codecs reject unknown fields and schema versions', () {
    expect(
      () => registry.decode(
        kind: PortfolioStrategyKind.indexCore,
        schemaVersion: 1,
        payload: const {'automatic_contributions': false, 'surprise': true},
      ),
      throwsFormatException,
    );
    expect(
      () => registry.decode(
        kind: PortfolioStrategyKind.indexCore,
        schemaVersion: 2,
        payload: const {'automatic_contributions': false},
      ),
      throwsFormatException,
    );
  });
}
