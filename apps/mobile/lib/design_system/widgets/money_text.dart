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
    this.semanticLabel,
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

  /// Override the screen-reader label. Defaults to `"<amount> <currencyCode>"`
  /// (e.g. `"1234.50 CNY"`) which reads more naturally than the rendered
  /// glyph form (`¥1,234.50` would be read as "yen sign one comma two
  /// three..."). Pass an explicit label when you need locale-aware phrasing
  /// or want to combine the amount with surrounding context.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = (style ?? TypographyTokens.numericBody).copyWith(
      color: color,
      fontFeatures: TypographyTokens.tabularFigures,
    );
    // Clamp the user's text-scale on numeric displays. The hero net-worth
    // figure uses [TypographyTokens.numericDisplay] (32pt @ -0.25 letter
    // spacing) and overflows on cards at the system max of 2.0×; the
    // tabular-figure layout doesn't reflow gracefully because monetary
    // figures must stay on a single line. Body / caption sizes still
    // honour the user's preference fully.
    final fontSize = effectiveStyle.fontSize ?? 14;
    final mq = MediaQuery.maybeOf(context);
    final scaler = mq == null
        ? TextScaler.noScaling
        : (fontSize >= 24
              ? mq.textScaler.clamp(maxScaleFactor: 1.4)
              : mq.textScaler);
    final text = Text(
      _format(context),
      style: effectiveStyle,
      textAlign: textAlign,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textScaler: scaler,
    );
    return Semantics(
      label: semanticLabel ?? _semanticLabel(),
      excludeSemantics: true,
      child: text,
    );
  }

  /// Locale-agnostic spoken form so VoiceOver/TalkBack reads numbers
  /// correctly without misreading currency glyphs as their literal name.
  String _semanticLabel() {
    if (amount == null) return currencyCode;
    final value = amount!;
    final digits = fractionDigits ?? 2;
    final magnitude = value.abs().toStringAsFixed(digits);
    final sign = value < 0
        ? '-'
        : (showSign && value > 0 ? '+' : '');
    return '$sign$magnitude $currencyCode';
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
