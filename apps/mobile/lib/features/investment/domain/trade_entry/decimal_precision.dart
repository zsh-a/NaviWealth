import 'package:decimal/decimal.dart';

import '../../../../data/domain/enums.dart';

/// Per-[AssetType] scale rules used to validate trade-entry input.
///
/// Crypto needs the most headroom — ERC-20 tokens commonly have 18 decimals
/// and stable-coins 6, so we let users enter quantities up to 18 fractional
/// digits. Equities/ETFs allow fractional shares but in practice never go
/// past 8 places (most brokers stop at 6). Cash and bond face values are
/// integer-leaning, capped at 4 to leave room for ¢-style minor units.
class DecimalPrecisionRules {
  const DecimalPrecisionRules._();

  /// Highest decimal scale the UI / service layer should accept for a
  /// quantity field. Anything beyond this is treated as user error rather
  /// than rounded silently — silent rounding on quantity has caused real
  /// reconciliation pain on production trading apps.
  static int maxQuantityScale(AssetType type) {
    switch (type) {
      case AssetType.crypto:
        return 18;
      case AssetType.cash:
        return 4;
      case AssetType.bond:
        return 6;
      case AssetType.stock:
      case AssetType.etf:
      case AssetType.mutualFund:
      case AssetType.commodity:
      case AssetType.realEstate:
      case AssetType.vehicle:
      case AssetType.custom:
        return 8;
    }
  }

  /// Highest decimal scale we expect for monetary fields (price, fee, tax).
  /// Markets quote crypto in 8–10 decimals; everything else is comfortably
  /// inside 6.
  static int maxMoneyScale(AssetType type) {
    switch (type) {
      case AssetType.crypto:
        return 10;
      default:
        return 6;
    }
  }

  /// Returns the count of significant fractional digits in [d] — i.e. the
  /// scale after stripping trailing zeros.
  ///
  /// `Decimal` keeps its scale verbatim from parse, so `Decimal.parse('1.10')`
  /// reports a non-zero fractional component but should validate the same as
  /// `1.1`. Strip the zeros before counting.
  static int fractionalDigits(Decimal d) {
    final shaved = d.toString();
    final dot = shaved.indexOf('.');
    if (dot < 0) return 0;
    var end = shaved.length;
    while (end > dot + 1 && shaved.codeUnitAt(end - 1) == 0x30) {
      end--;
    }
    if (end == dot + 1) return 0;
    return end - dot - 1;
  }
}
