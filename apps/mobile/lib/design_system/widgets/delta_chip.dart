import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../theme/app_theme_scope.dart';
import '../tokens/dimens_tokens.dart';
import 'amount_privacy_scope.dart';
import 'delta_text.dart';

/// Pill-shaped variant of [DeltaText] — same direction-aware coloring but
/// with a soft container background. Useful when the delta sits next to a
/// large hero number (e.g. portfolio value) and needs to read as a chip.
class DeltaChip extends StatelessWidget {
  const DeltaChip({
    super.key,
    required this.value,
    this.format = DeltaFormat.percent,
    this.currencyCode = 'CNY',
    this.fractionDigits,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.s8,
      vertical: AppSpacing.s2,
    ),
    this.style,
  });

  final num? value;
  final DeltaFormat format;
  final String currencyCode;
  final int? fractionDigits;
  final EdgeInsetsGeometry padding;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final market = context.appTheme.market;
    final hidden = value != null && AmountPrivacyScope.isHiddenOf(context);
    final colors = context.theme.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: hidden
            ? colors.muted.withValues(alpha: AppOpacity.subtle)
            : value == null || value == 0
            // Flat deltas keep the legacy translucent fill rather than a
            // solid container so zero rows stay quiet.
            ? market.flat.fg.withValues(alpha: AppOpacity.light)
            : market.roleForDelta(value).container,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Padding(
        padding: padding,
        child: DeltaText(
          value: value,
          format: format,
          currencyCode: currencyCode,
          fractionDigits: fractionDigits,
          style: style,
          color: hidden
              ? colors.mutedForeground
              : market.roleForDelta(value).onContainer,
        ),
      ),
    );
  }
}
