import 'package:decimal/decimal.dart';

/// Itemized fee breakdown for a single trade.
///
/// Journal-entry builders persist fee totals as posting legs, but at the
/// input/computation layer we want a typed breakdown so reports can roll
/// up commission vs stamp duty vs regulatory fees separately and the
/// cost-basis engine still sees a single total.
///
/// Convention: every component is non-negative. [total] is the sum that
/// flows into [BuyEvent.fee] / [SellEvent.fee].
///
/// The four named buckets cover the fee categories the task scope calls
/// out (买卖佣金 / 印花税 (A 股) / 监管费 / 过户费); [other] catches
/// anything broker-specific that does not fit.
class TradeFees {
  TradeFees({
    Decimal? commission,
    Decimal? stampDuty,
    Decimal? regulatory,
    Decimal? transferFee,
    Decimal? other,
  }) : commission = commission ?? Decimal.zero,
       stampDuty = stampDuty ?? Decimal.zero,
       regulatory = regulatory ?? Decimal.zero,
       transferFee = transferFee ?? Decimal.zero,
       other = other ?? Decimal.zero {
    _requireNonNegative(this.commission, 'commission');
    _requireNonNegative(this.stampDuty, 'stampDuty');
    _requireNonNegative(this.regulatory, 'regulatory');
    _requireNonNegative(this.transferFee, 'transferFee');
    _requireNonNegative(this.other, 'other');
  }

  /// Zero across every bucket.
  factory TradeFees.zero() => TradeFees();

  /// Brokerage commission (买卖佣金).
  final Decimal commission;

  /// Stamp duty (印花税). On A-share sells the rate is set by Ministry of
  /// Finance; on buys it is zero. Storing the value rather than the rate
  /// keeps the model agnostic to jurisdiction-specific schedules.
  final Decimal stampDuty;

  /// Regulatory levy (监管费 / 证管费 / SEC 31 fee).
  final Decimal regulatory;

  /// Transfer / clearing fee (过户费 / DTCC fee).
  final Decimal transferFee;

  /// Anything else the broker itemizes (platform fee, FX spread, etc.).
  final Decimal other;

  /// Sum of all components — matches what flows to the fee posting.
  Decimal get total =>
      commission + stampDuty + regulatory + transferFee + other;

  bool get isZero => total.sign == 0;

  TradeFees copyWith({
    Decimal? commission,
    Decimal? stampDuty,
    Decimal? regulatory,
    Decimal? transferFee,
    Decimal? other,
  }) {
    return TradeFees(
      commission: commission ?? this.commission,
      stampDuty: stampDuty ?? this.stampDuty,
      regulatory: regulatory ?? this.regulatory,
      transferFee: transferFee ?? this.transferFee,
      other: other ?? this.other,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TradeFees &&
        other.commission == commission &&
        other.stampDuty == stampDuty &&
        other.regulatory == regulatory &&
        other.transferFee == transferFee &&
        other.other == this.other;
  }

  @override
  int get hashCode =>
      Object.hash(commission, stampDuty, regulatory, transferFee, other);

  @override
  String toString() =>
      'TradeFees(total: $total, commission: $commission, '
      'stampDuty: $stampDuty, regulatory: $regulatory, '
      'transferFee: $transferFee, other: $other)';

  static void _requireNonNegative(Decimal value, String name) {
    if (value.sign < 0) {
      throw ArgumentError.value(value, name, 'must be non-negative');
    }
  }
}
