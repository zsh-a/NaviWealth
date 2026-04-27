import 'package:freezed_annotation/freezed_annotation.dart';

part 'currency.freezed.dart';

/// Static currency dictionary entry. Not synced — every device ships with
/// the same seed list and the user can extend it locally.
@freezed
class Currency with _$Currency {
  const factory Currency({
    required String code,
    required String name,
    required int decimals,
    String? symbol,
  }) = _Currency;
}
