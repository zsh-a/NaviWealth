import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../tokens/motion_tokens.dart' show Motion;
import '../tokens/typography_tokens.dart';
import 'money_text.dart';

/// A [MoneyText] variant that animates between values with a counting effect.
///
/// When [amount] changes, the displayed number smoothly counts from the old
/// value to the new one over [duration], using a decelerate curve for a
/// natural "odometer" feel. Uses tabular figures to prevent digit jitter.
class AnimatedMoneyText extends StatefulWidget {
  const AnimatedMoneyText({
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
    this.duration = Motion.ticker,
  });

  final num? amount;
  final String currencyCode;
  final String? symbol;
  final MoneySymbolStyle symbolStyle;
  final int? fractionDigits;
  final TextStyle? style;
  final Color? color;
  final String? locale;
  final TextAlign? textAlign;
  final bool compact;
  final bool showSign;
  final Duration duration;

  @override
  State<AnimatedMoneyText> createState() => _AnimatedMoneyTextState();
}

class _AnimatedMoneyTextState extends State<AnimatedMoneyText> {
  double _previous = 0;
  double _current = 0;

  @override
  void initState() {
    super.initState();
    _current = widget.amount?.toDouble() ?? 0;
    _previous = _current;
  }

  @override
  void didUpdateWidget(AnimatedMoneyText oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newAmount = widget.amount?.toDouble() ?? 0;
    if (newAmount != _current) {
      _previous = _current;
      _current = newAmount;
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = (widget.style ?? TypographyTokens.numericBody)
        .copyWith(
          color: widget.color,
          fontFeatures: TypographyTokens.tabularFigures,
        );

    // No animation needed for null amounts.
    if (widget.amount == null) {
      return Text(
        _formatValue(context, 0),
        style: effectiveStyle,
        textAlign: widget.textAlign,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: _previous, end: _current),
      duration: widget.duration,
      curve: Motion.emphasizedDecelerate,
      builder: (context, value, _) {
        return Text(
          _formatValue(context, value),
          style: effectiveStyle,
          textAlign: widget.textAlign,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }

  String _formatValue(BuildContext context, double value) {
    final loc = widget.locale ??
        Localizations.maybeLocaleOf(context)?.toString();

    final NumberFormat formatter;
    switch (widget.symbolStyle) {
      case MoneySymbolStyle.symbol:
        final glyph = widget.symbol ?? _defaultGlyphFor(widget.currencyCode);
        formatter = widget.compact
            ? NumberFormat.compactCurrency(
                locale: loc,
                name: widget.currencyCode,
                symbol: glyph,
              )
            : NumberFormat.currency(
                locale: loc,
                name: widget.currencyCode,
                symbol: glyph,
                decimalDigits: widget.fractionDigits,
              );
      case MoneySymbolStyle.isoCode:
        formatter = widget.compact
            ? NumberFormat.compactCurrency(
                locale: loc,
                name: widget.currencyCode,
                symbol: '${widget.currencyCode} ',
              )
            : NumberFormat.currency(
                locale: loc,
                name: widget.currencyCode,
                symbol: '${widget.currencyCode} ',
                decimalDigits: widget.fractionDigits,
              );
      case MoneySymbolStyle.none:
        formatter = widget.compact
            ? NumberFormat.compact(locale: loc)
            : NumberFormat.decimalPatternDigits(
                locale: loc,
                decimalDigits: widget.fractionDigits ?? 2,
              );
    }

    final formatted = formatter.format(value.abs());
    if (value < 0) return '-$formatted';
    if (widget.showSign && value > 0) return '+$formatted';
    return formatted;
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
