import 'package:decimal/decimal.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'fx_rate.freezed.dart';

/// Time-series FX rate — `1 [base] = rate * [quote]` at [asOf].
///
/// Not synced (rates are global market data, not user data); each client
/// pulls them from the price feed and stores its own copy.
@freezed
abstract class FxRate with _$FxRate {
  const factory FxRate({
    required String id,
    required String baseCurrency,
    required String quoteCurrency,
    required Decimal rate,
    required DateTime asOf,
    String? source,
  }) = _FxRate;
}
