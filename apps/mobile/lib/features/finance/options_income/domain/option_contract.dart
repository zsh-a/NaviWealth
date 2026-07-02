import 'package:decimal/decimal.dart';
import 'package:naviwealth/domain/values/money.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';

/// One normalized option contract returned by an [OptionsChainProvider].
///
/// `OptionContract` is the **wire-source** snapshot. Every field is the
/// value as observed at [fetchedAt]; the scorer treats it as immutable.
/// Decimal/Money fields keep the doc §5.1 invariant ("no double for
/// premium / strike / cash_required").
class OptionContract {
  const OptionContract({
    required this.underlying,
    required this.market,
    required this.optionSymbol,
    required this.type,
    required this.expiration,
    required this.dte,
    required this.strike,
    required this.bid,
    required this.ask,
    required this.mid,
    required this.volume,
    required this.openInterest,
    required this.impliedVolatility,
    required this.delta,
    required this.underlyingPrice,
    required this.bidAskSpreadPct,
    required this.fetchedAt,
  });

  final String underlying;
  final AssetMarket market;

  /// OCC-style symbol — e.g. `AAPL250620C00200000`.
  final String optionSymbol;

  final OptionType type;

  /// UTC midnight on the expiration day.
  final DateTime expiration;

  /// Days to expiration computed as `(expiration - asOf).inDays`.
  final int dte;

  final Money strike;
  final Money bid;
  final Money ask;
  final Money mid;

  final int volume;
  final int openInterest;

  /// 0..1 fraction. May be `null` when the source omits IV.
  final Decimal? impliedVolatility;

  /// Calls: 0..1 positive; puts: -1..0 negative. May be `null` when
  /// the source omits greeks (yfinance frequently does for OTM legs).
  final Decimal? delta;

  final Money underlyingPrice;

  /// `(ask - bid) / mid`, clamped to [0, 1].
  final Decimal bidAskSpreadPct;

  final DateTime fetchedAt;
}

enum OptionType { call, put }

extension OptionTypeWire on OptionType {
  String get wire => switch (this) {
    OptionType.call => 'call',
    OptionType.put => 'put',
  };
}

OptionType? parseOptionType(String wire) {
  switch (wire) {
    case 'call':
      return OptionType.call;
    case 'put':
      return OptionType.put;
  }
  return null;
}
