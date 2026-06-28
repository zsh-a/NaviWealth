import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import '../theme/market_color_mode.dart';
import '../theme/market_colors.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/typography_tokens.dart';
import 'amount_privacy_placeholder.dart';
import 'amount_privacy_scope.dart';
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

  @override
  Widget build(BuildContext context) {
    final hidden = value != null && AmountPrivacyScope.isHiddenOf(context);
    final baseStyle = (style ?? TypographyTokens.numericBody).copyWith(
      fontFeatures: TypographyTokens.tabularFigures,
    );
    if (hidden) {
      return AmountPrivacyPlaceholder(
        style: baseStyle,
        density: _placeholderDensity(baseStyle),
        semanticsLabel: AmountPrivacyScope.hiddenSemanticsLabelOf(context),
      );
    }
    final market = MarketColors.of(context);
    final tone = market.forDelta(value);
    final effectiveStyle = baseStyle.copyWith(color: tone);

    return Semantics(
      container: true,
      label: _spokenLabel(context),
      excludeSemantics: true,
      child: DefaultTextStyle.merge(
        style: effectiveStyle,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showIcon)
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.s2),
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
      ),
    );
  }

  String _spokenLabel(BuildContext context) {
    if (value == null) return '—';
    if (AmountPrivacyScope.isHiddenOf(context)) {
      return AmountPrivacyScope.hiddenSemanticsLabelOf(context);
    }
    final direction = value! > 0
        ? '+'
        : value! < 0
        ? '-'
        : '';
    if (format == DeltaFormat.currency) {
      final loc = locale ?? Localizations.maybeLocaleOf(context)?.toString();
      final digits = fractionDigits ?? 2;
      final formatter = NumberFormat.decimalPatternDigits(
        locale: loc,
        decimalDigits: digits,
      );
      return '$direction${formatter.format(value!.abs())} $currencyCode';
    }
    return '$direction${_formatNonCurrency(context).replaceAll(RegExp(r'^[+-]'), '')}';
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
    if (v == null || v == 0) return FLucideIcons.minus;
    return v > 0 ? FLucideIcons.chevronUp : FLucideIcons.chevronDown;
  }

  AmountPrivacyPlaceholderDensity _placeholderDensity(TextStyle style) {
    final fontSize =
        style.fontSize ?? TypographyTokens.numericBody.fontSize ?? 14;
    if (fontSize >= 18) return AmountPrivacyPlaceholderDensity.title;
    if (fontSize <= 12) return AmountPrivacyPlaceholderDensity.caption;
    return AmountPrivacyPlaceholderDensity.body;
  }
}
