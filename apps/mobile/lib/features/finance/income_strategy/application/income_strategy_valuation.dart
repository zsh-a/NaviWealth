import 'package:naviwealth/features/finance/domain/fx/currency_converter.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';

import '../domain/income_strategy.dart';

class IncomeStrategyValuation {
  const IncomeStrategyValuation({
    required this.baseCurrency,
    required this.converter,
    required this.asOf,
  });

  final String baseCurrency;
  final CurrencyConverter converter;
  final DateTime asOf;

  Money? tryToBase(Money value, {DateTime? on}) {
    try {
      return converter.convert(value, baseCurrency, on: on ?? asOf);
    } on FxRateNotFoundError {
      return null;
    }
  }

  IncomeStrategyMoneyMetric metric(Money value, {DateTime? on}) {
    final converted = tryToBase(value, on: on);
    return converted == null
        ? IncomeStrategyMoneyMetric.zero(
            baseCurrency,
            quality: IncomeStrategyMetricQuality.unavailable,
          )
        : IncomeStrategyMoneyMetric(value: converted);
  }

  IncomeStrategyMoneyMetric optionalMetric(Money? value, {DateTime? on}) {
    if (value == null) {
      return IncomeStrategyMoneyMetric.zero(
        baseCurrency,
        quality: IncomeStrategyMetricQuality.unavailable,
      );
    }
    return metric(value, on: on);
  }
}
