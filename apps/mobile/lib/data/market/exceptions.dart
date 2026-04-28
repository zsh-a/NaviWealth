/// Hierarchical exception types thrown by the market-data layer.
///
/// All provider failures are normalised to one of these so the composite
/// service can decide whether to retry, fall back to another provider, or
/// degrade to cached / stale data.
sealed class MarketDataException implements Exception {
  const MarketDataException(this.message, {this.provider, this.cause});

  final String message;
  final String? provider;
  final Object? cause;

  @override
  String toString() {
    final src = provider == null ? '' : ' [$provider]';
    return '$runtimeType$src: $message';
  }
}

/// Provider returned a non-2xx status that is not specifically handled.
class ProviderUnavailableException extends MarketDataException {
  const ProviderUnavailableException(
    super.message, {
    super.provider,
    super.cause,
    this.statusCode,
  });
  final int? statusCode;
}

/// Provider explicitly told us we are over quota / too fast.
class RateLimitException extends MarketDataException {
  const RateLimitException(
    super.message, {
    super.provider,
    super.cause,
    this.retryAfter,
  });
  final Duration? retryAfter;
}

/// Provider responded but the symbol does not exist there. NOT retried; the
/// composite service should try the next provider in the chain.
class SymbolNotFoundException extends MarketDataException {
  const SymbolNotFoundException(super.message, {super.provider, super.cause});
}

/// Network-level failure (DNS, timeout, connection reset). Eligible for retry.
class NetworkException extends MarketDataException {
  const NetworkException(super.message, {super.provider, super.cause});
}

/// Provider response could not be parsed. Indicates either an upstream
/// schema change or a non-JSON error page; not retried at provider level
/// but is logged and counted as `error`.
class ProviderResponseException extends MarketDataException {
  const ProviderResponseException(super.message, {super.provider, super.cause});
}

/// Composite signal — every provider in the chain failed AND no usable
/// (even stale) cache existed.
class NoMarketDataAvailableException extends MarketDataException {
  const NoMarketDataAvailableException(super.message, {super.cause});
}
