import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/market_color_mode.dart';
import '../theme/market_colors.dart';
import '../tokens/spacing_tokens.dart';
import '../tokens/typography_tokens.dart';
import 'money_text.dart';

/// How a delta value should render.
enum DeltaFormat {
  /// Treat [DeltaText.value] as money (uses [MoneyText] internally).
  currency,

  /// Render as a percentage. The numeric value is in **percentage points**
  /// (i.e. `1.5` → "1.50%"). Use [DeltaText.percentFromRatio] if your value
  /// is already a 0..1 ratio.
  percent,

  /// Plain number with thousands grouping (no symbol).
  decimal,
}

/// Renders a signed change (gain or loss) with the user's preferred
/// up/down color and an arrow icon for color-blind safety.
///
/// The mode comes from [MarketColors] on the active theme — flipping the
/// user's preference re-skins every [DeltaText] in the tree on next build.
class DeltaText extends StatelessWidget {
  const DeltaText({
    super.key,
    required this.value,
    this.format = DeltaFormat.currency,
    this.currencyCode = 'CNY',
    this.fractionDigits,
    this.style,
    this.showIcon = true,
    this.showSign = true,
    this.locale,
    this.semanticLabel,
  });

  /// Convenience constructor — pass a 0..1 ratio (e.g. `0.0234` for
  /// `+2.34%`).
  factory DeltaText.percentFromRatio({
    Key? key,
    required num? ratio,
    int? fractionDigits = 2,
    TextStyle? style,
    bool showIcon = true,
    bool showSign = true,
    String? locale,
    String? semanticLabel,
  }) {
    return DeltaText(
      key: key,
      value: ratio == null ? null : ratio * 100,
      format: DeltaFormat.percent,
      fractionDigits: fractionDigits,
      style: style,
      showIcon: showIcon,
      showSign: showSign,
      locale: locale,
      semanticLabel: semanticLabel,
    );
  }

  final num? value;
  final DeltaFormat format;
  final String currencyCode;
  final int? fractionDigits;
  final TextStyle? style;

  /// Arrow icon next to the number. We default this on so a color-blind user
  /// can still tell direction even before they switch to the colorblind
  /// palette.
  final bool showIcon;

  /// Always render a leading `+` for positive numbers. Defaults to true so
  /// a delta cell unambiguously communicates direction.
  final bool showSign;

  final String? locale;

  /// Override the screen-reader label. Defaults to a sign-aware spoken
  /// form (e.g. `"up 2.34 percent"`, `"down 1234.50 CNY"`, or `"unchanged"`)
  /// so colour + arrow direction reach assistive tech the same way they
  /// reach sighted users.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final market = MarketColors.of(context);
    final tone = market.forDelta(value);
    final effectiveStyle = (style ?? TypographyTokens.numericBody).copyWith(
      color: tone,
      fontFeatures: TypographyTokens.tabularFigures,
    );

    final body = DefaultTextStyle.merge(
      style: effectiveStyle,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showIcon)
            Padding(
              padding: const EdgeInsets.only(right: Spacing.s2),
              child: Icon(
                _iconFor(value, market.mode),
                size: (effectiveStyle.fontSize ?? 14) + 2,
                color: tone,
              ),
            ),
          if (format == DeltaFormat.currency)
            MoneyText(
              amount: value,
              currencyCode: currencyCode,
              fractionDigits: fractionDigits,
              style: effectiveStyle,
              showSign: showSign,
              locale: locale,
            )
          else
            Text(_formatNonCurrency(context), style: effectiveStyle),
        ],
      ),
    );

    return Semantics(
      label: semanticLabel ?? _semanticLabel(),
      excludeSemantics: true,
      container: true,
      child: body,
    );
  }

  String _semanticLabel() {
    if (value == null) return _unitNoun();
    final v = value!;
    final digits = fractionDigits ?? 2;
    final magnitude = v.abs().toStringAsFixed(digits);
    final direction = v == 0
        ? 'unchanged'
        : (v > 0 ? 'up' : 'down');
    if (format == DeltaFormat.currency) {
      if (v == 0) return 'unchanged $currencyCode';
      return '$direction $magnitude $currencyCode';
    }
    final unit = _unitNoun();
    if (v == 0) return 'unchanged';
    return '$direction $magnitude $unit';
  }

  String _unitNoun() {
    switch (format) {
      case DeltaFormat.currency:
        return currencyCode;
      case DeltaFormat.percent:
        return 'percent';
      case DeltaFormat.decimal:
        return '';
    }
  }

  String _formatNonCurrency(BuildContext context) {
    if (value == null) return '—';
    final loc = locale ?? Localizations.maybeLocaleOf(context)?.toString();
    final digits = fractionDigits ?? 2;
    final formatter = NumberFormat.decimalPatternDigits(
      locale: loc,
      decimalDigits: digits,
    );
    final formatted = formatter.format(value!.abs());
    final suffix = format == DeltaFormat.percent ? '%' : '';
    if (value! < 0) return '-$formatted$suffix';
    if (showSign && value! > 0) return '+$formatted$suffix';
    return '$formatted$suffix';
  }

  IconData _iconFor(num? v, MarketColorMode _) {
    if (v == null || v == 0) return Icons.remove;
    return v > 0 ? Icons.arrow_drop_up : Icons.arrow_drop_down;
  }
}
