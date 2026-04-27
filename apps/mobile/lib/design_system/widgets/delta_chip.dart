import 'package:flutter/material.dart';

import '../theme/market_colors.dart';
import '../tokens/radius_tokens.dart';
import '../tokens/spacing_tokens.dart';
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
      horizontal: Spacing.s8,
      vertical: Spacing.s2,
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
    final market = MarketColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: market.containerForDelta(value),
        borderRadius: Radii.brSm,
      ),
      child: Padding(
        padding: padding,
        child: DeltaText(
          value: value,
          format: format,
          currencyCode: currencyCode,
          fractionDigits: fractionDigits,
          style: (style ?? const TextStyle()).copyWith(
            color: market.onContainerForDelta(value),
          ),
        ),
      ),
    );
  }
}
