part of 'yfinance_options_provider.dart';

class _CachedChainPayload {
  const _CachedChainPayload({
    required this.currency,
    required this.underlyingPriceRaw,
    required this.fetchedAt,
    required this.contracts,
  });

  final String currency;
  final String underlyingPriceRaw;
  final DateTime fetchedAt;
  final List<OptionContract> contracts;
}

class _RawChain {
  const _RawChain({
    required this.currency,
    required this.underlyingPriceRaw,
    required this.expirations,
    required this.firstExpirationEpoch,
    required this.contracts,
  });

  final String currency;
  final String underlyingPriceRaw;
  final List<int> expirations;
  final int? firstExpirationEpoch;
  final List<OptionContract> contracts;
}

Map<String, dynamic> _expectMap(
  dynamic value,
  String path, {
  required String provider,
}) {
  if (value is Map<String, dynamic>) return value;
  throw ProviderResponseException(
    '$path expected object, got ${value.runtimeType}',
    provider: provider,
  );
}

Decimal _decimal(num value) => Decimal.parse(value.toString());

num _safeNum(Object? value) => value is num ? value : 0;

extension on Money {
  /// Rounds the amount to 4 decimal places. yfinance returns float strike
  /// prices like `190.0000000000001`; we keep four digits for display.
  Money rounded() {
    final raw = amount;
    final rounded = Decimal.parse(raw.toStringAsFixed(4));
    return Money(rounded, currency);
  }
}
