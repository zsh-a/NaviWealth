part of 'yfinance_options_provider.dart';

mixin YFinanceOptionsNormalizationMixin {
  OptionContract? _normalize({
    required Map<String, dynamic> raw,
    required OptionType type,
    required String underlying,
    required String currency,
    required DateTime expiration,
    required Money underlyingPrice,
    required DateTime fetchedAt,
  }) {
    final symbol = raw['contractSymbol'];
    final strikeRaw = raw['strike'];
    final bidRaw = raw['bid'];
    final askRaw = raw['ask'];
    if (symbol is! String || strikeRaw is! num) return null;
    final strike = Money(_decimal(strikeRaw), currency);
    final bid = Money(_decimal(_safeNum(bidRaw)), currency);
    final ask = Money(_decimal(_safeNum(askRaw)), currency);
    final mid = _midpoint(bid: bid, ask: ask, lastFallback: raw['lastPrice']);
    final spread = _spreadPct(
      bid: bid.amount,
      ask: ask.amount,
      mid: mid.amount,
    );
    final dte = expiration
        .toUtc()
        .difference(DateTime(fetchedAt.year, fetchedAt.month, fetchedAt.day))
        .inDays;
    return OptionContract(
      underlying: underlying,
      market: AssetMarket.usStock,
      optionSymbol: symbol,
      type: type,
      expiration: DateTime.utc(
        expiration.year,
        expiration.month,
        expiration.day,
      ),
      dte: dte < 0 ? 0 : dte,
      strike: strike,
      bid: bid,
      ask: ask,
      mid: mid,
      volume: (raw['volume'] as num?)?.toInt() ?? 0,
      openInterest: (raw['openInterest'] as num?)?.toInt() ?? 0,
      impliedVolatility: (raw['impliedVolatility'] as num?) == null
          ? null
          : _decimal(raw['impliedVolatility'] as num),
      delta: null, // yfinance does not return greeks.
      underlyingPrice: underlyingPrice,
      bidAskSpreadPct: spread,
      fetchedAt: fetchedAt,
    );
  }

  Money _midpoint({
    required Money bid,
    required Money ask,
    required Object? lastFallback,
  }) {
    final hasBid = bid.amount > Decimal.zero;
    final hasAsk = ask.amount > Decimal.zero;
    if (hasBid && hasAsk) {
      final sum = bid.amount + ask.amount;
      final midAmount = (sum / Decimal.fromInt(2)).toDecimal(
        scaleOnInfinitePrecision: 6,
      );
      return Money(midAmount, bid.currency).rounded();
    }
    if (hasAsk) return ask;
    if (hasBid) return bid;
    if (lastFallback is num && lastFallback > 0) {
      return Money(_decimal(lastFallback), bid.currency);
    }
    return Money.zero(bid.currency);
  }

  Decimal _spreadPct({
    required Decimal bid,
    required Decimal ask,
    required Decimal mid,
  }) {
    if (mid <= Decimal.zero) return Decimal.one;
    if (bid <= Decimal.zero || ask <= Decimal.zero) return Decimal.one;
    final diff = ask - bid;
    final dec = (diff / mid).toDecimal(scaleOnInfinitePrecision: 6);
    if (dec < Decimal.zero) return Decimal.zero;
    if (dec > Decimal.one) return Decimal.one;
    return dec;
  }
}
