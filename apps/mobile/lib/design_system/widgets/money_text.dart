import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../tokens/typography_tokens.dart';

/// How much horizontal space the symbol should take.
enum MoneySymbolStyle {
  /// `¥`, `$`, `€` (compact glyph). Default.
  symbol,

  /// `CNY`, `USD`, `EUR` (always 3 letters, useful in tables).
  isoCode,

  /// Don't render any symbol.
  none,
}

/// Renders a monetary amount with consistent typography (lining tabular
/// figures), thousands grouping, and a configurable currency symbol.
///
/// Direction-tinted "delta" amounts should use [DeltaText] instead — this
/// widget is brightness/scheme aware but does NOT colour by sign.
class MoneyText extends StatelessWidget {
  const MoneyText({
    super.key,
    required this.amount,
    this.currencyCode = 'CNY',
    this.symbol,
    this.symbolStyle = MoneySymbolStyle.symbol,
    this.fractionDigits,
    this.style,
    this.color,
    this.locale,
    this.textAlign,
    this.compact = false,
    this.showSign = false,
  });

  /// Amount in the major unit (e.g. `1234.5` = ¥1,234.50). Accepts `num` so
  /// callers can pass either `int` or `double`. Pass via `Decimal.toDouble()`
  /// at the boundary for now; a `Decimal`-typed overload can come later
  /// without churning callers.
  final num? amount;

  /// ISO 4217 currency code (drives default symbol + decimal places).
  final String currencyCode;

  /// Override the symbol glyph (e.g. `'US$'`). Defaults to the locale's
  /// symbol for [currencyCode].
  final String? symbol;

  final MoneySymbolStyle symbolStyle;

  /// Override decimals. If null, uses the currency's default (most fiat = 2,
  /// JPY = 0, etc.).
  final int? fractionDigits;

  /// Text style override. Defaults to [TypographyTokens.numericBody].
  final TextStyle? style;

  final Color? color;

  /// Locale for grouping/decimal separator. Defaults to current app locale.
  final String? locale;

  final TextAlign? textAlign;

  /// Render `1.2K`, `3.4M`, `5.6B` style (useful in tight chart axis labels).
  final bool compact;

  /// Always render the leading `+` for positive values. Useful next to a
  /// delta. Negative numbers always show `-`.
  final bool showSign;

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = (style ?? TypographyTokens.numericBody).copyWith(
      color: color,
      fontFeatures: TypographyTokens.tabularFigures,
    );
    return Text(
      _format(context),
      style: effectiveStyle,
      textAlign: textAlign,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  String _format(BuildContext context) {
    if (amount == null) return _emptyForSymbol();
    final loc = locale ?? Localizations.maybeLocaleOf(context)?.toString();
    final value = amount!;

    final NumberFormat formatter;
    switch (symbolStyle) {
      case MoneySymbolStyle.symbol:
        // `simpleCurrency` would pick a locale default, but its symbol
        // field is final. Use `currency` directly so we can substitute
        // an explicit override or our fallback table for common fiat.
        final glyph = symbol ?? _defaultGlyphFor(currencyCode);
        formatter = compact
            ? NumberFormat.compactCurrency(
                locale: loc,
                name: currencyCode,
                symbol: glyph,
              )
            : NumberFormat.currency(
                locale: loc,
                name: currencyCode,
                symbol: glyph,
                decimalDigits: fractionDigits,
              );
      case MoneySymbolStyle.isoCode:
        formatter = compact
            ? NumberFormat.compactCurrency(
                locale: loc,
                name: currencyCode,
                symbol: '$currencyCode ',
              )
            : NumberFormat.currency(
                locale: loc,
                name: currencyCode,
                symbol: '$currencyCode ',
                decimalDigits: fractionDigits,
              );
      case MoneySymbolStyle.none:
        formatter = compact
            ? NumberFormat.compact(locale: loc)
            : NumberFormat.decimalPatternDigits(
                locale: loc,
                decimalDigits: fractionDigits ?? 2,
              );
    }

    final formatted = formatter.format(value.abs());
    if (value < 0) return '-$formatted';
    if (showSign && value > 0) return '+$formatted';
    return formatted;
  }

  String _emptyForSymbol() {
    switch (symbolStyle) {
      case MoneySymbolStyle.symbol:
        return '${symbol ?? _defaultGlyphFor(currencyCode)} —';
      case MoneySymbolStyle.isoCode:
        return '$currencyCode —';
      case MoneySymbolStyle.none:
        return '—';
    }
  }

  String _defaultGlyphFor(String code) {
    switch (code.toUpperCase()) {
      case 'CNY':
      case 'JPY':
        return '¥';
      case 'USD':
        return '\$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      case 'HKD':
        return 'HK\$';
      default:
        return code;
    }
  }
}
