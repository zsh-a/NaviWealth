/// Stable error codes raised by the trade-entry layer.
///
/// Codes are surfaced to the UI for localisation; the messages are English
/// developer hints. Callers MUST switch on [TradeEntryErrorCode] rather than
/// the message string, which is unstable.
enum TradeEntryErrorCode {
  /// Quantity was zero or negative. Buys and sells require a positive amount.
  quantityNotPositive,

  /// Quantity carried more fractional digits than the asset type allows
  /// (see [DecimalPrecisionRules.maxQuantityScale]).
  quantityScaleExceeded,

  /// Fee or tax was negative. The model expects positive amounts.
  amountNegative,

  /// Trade currency disagrees with the quote/asset currency in a way the
  /// service cannot resolve (e.g. no FX rate available).
  currencyMismatch,

  /// User omitted the price *and* the market-data backfill returned nothing
  /// usable for [TradeDraft.tradeDate].
  priceUnavailable,

  /// Sell would consume more shares than are open in matching lots — the
  /// caller can choose to either reject or persist with a leftover negative
  /// position, but the default service refuses by default.
  insufficientHoldings,

  /// A field that should never reach the engine is empty (asset id, account
  /// id, etc.).
  fieldRequired,
}

/// Validation / orchestration error raised when a [TradeDraft] cannot be
/// resolved into a [TradeEntryPlan].
class TradeEntryException implements Exception {
  TradeEntryException(this.code, this.message, {this.field, this.cause});

  final TradeEntryErrorCode code;
  final String message;
  final String? field;
  final Object? cause;

  @override
  String toString() =>
      'TradeEntryException(${code.name}${field == null ? '' : ', $field'}): '
      '$message';
}
