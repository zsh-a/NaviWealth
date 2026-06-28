import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';
import '../tokens/typography_tokens.dart';
import 'amount_privacy_scope.dart';

enum AmountPrivacyPlaceholderDensity { display, title, body, caption, compact }

/// Static, non-loading placeholder for hidden monetary values.
///
/// This intentionally does not use the app's shimmer skeleton: privacy mode is
/// a final display state, not pending content. The grouped bars preserve the
/// rhythm of an amount without exposing sign, magnitude, or decimal precision.
class AmountPrivacyPlaceholder extends StatelessWidget {
  const AmountPrivacyPlaceholder({
    super.key,
    this.style,
    this.density = AmountPrivacyPlaceholderDensity.body,
    this.textAlign,
    this.width,
    this.semanticsLabel,
  });

  final TextStyle? style;
  final AmountPrivacyPlaceholderDensity density;
  final TextAlign? textAlign;
  final double? width;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = style ?? _defaultStyle;
    final fontSize = effectiveStyle.fontSize ?? 14;
    final height = _height(fontSize);
    final resolvedWidth = width ?? _width(fontSize);
    final alignment = switch (textAlign) {
      TextAlign.right || TextAlign.end => AlignmentDirectional.centerEnd,
      TextAlign.center || TextAlign.justify => AlignmentDirectional.center,
      _ => AlignmentDirectional.centerStart,
    };
    final baseline =
        (effectiveStyle.fontSize ?? 14) * (effectiveStyle.height ?? 1.0) * 0.72;

    return Semantics(
      label:
          semanticsLabel ?? AmountPrivacyScope.hiddenSemanticsLabelOf(context),
      child: Baseline(
        baseline: baseline,
        baselineType: TextBaseline.alphabetic,
        child: Align(
          widthFactor: 1,
          heightFactor: 1,
          alignment: alignment,
          child: SizedBox(
            width: resolvedWidth,
            height: height,
            child: _PrivacyBars(
              height: height,
              density: density,
              color: _color(context),
            ),
          ),
        ),
      ),
    );
  }

  TextStyle get _defaultStyle => switch (density) {
    AmountPrivacyPlaceholderDensity.display => TypographyTokens.numericDisplay,
    AmountPrivacyPlaceholderDensity.title =>
      TypographyTokens.numericTitleStrong,
    AmountPrivacyPlaceholderDensity.body => TypographyTokens.numericBody,
    AmountPrivacyPlaceholderDensity.caption => TypographyTokens.numericCaption,
    AmountPrivacyPlaceholderDensity.compact => TypographyTokens.numericCaption,
  };

  double _height(double fontSize) {
    final ratio = switch (density) {
      AmountPrivacyPlaceholderDensity.display => 0.42,
      AmountPrivacyPlaceholderDensity.title => 0.44,
      AmountPrivacyPlaceholderDensity.body => 0.48,
      AmountPrivacyPlaceholderDensity.caption => 0.52,
      AmountPrivacyPlaceholderDensity.compact => 0.5,
    };
    return (fontSize * ratio).clamp(6, 18).toDouble();
  }

  double _width(double fontSize) {
    final factor = switch (density) {
      AmountPrivacyPlaceholderDensity.display => 4.9,
      AmountPrivacyPlaceholderDensity.title => 4.4,
      AmountPrivacyPlaceholderDensity.body => 4.2,
      AmountPrivacyPlaceholderDensity.caption => 3.8,
      AmountPrivacyPlaceholderDensity.compact => 3.0,
    };
    return (fontSize * factor).clamp(36, 180).toDouble();
  }

  Color _color(BuildContext context) {
    final colors = context.theme.colors;
    final isDark = colors.brightness == Brightness.dark;
    return colors.foreground.withValues(alpha: isDark ? 0.28 : 0.16);
  }
}

class _PrivacyBars extends StatelessWidget {
  const _PrivacyBars({
    required this.height,
    required this.density,
    required this.color,
  });

  final double height;
  final AmountPrivacyPlaceholderDensity density;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final segments = switch (density) {
      AmountPrivacyPlaceholderDensity.compact => const [0.52, 0.34],
      AmountPrivacyPlaceholderDensity.caption => const [0.46, 0.28, 0.18],
      _ => const [0.34, 0.22, 0.3],
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = density == AmountPrivacyPlaceholderDensity.compact
            ? AppSpacing.s4
            : AppSpacing.s6;
        final available = (constraints.maxWidth - gap * (segments.length - 1))
            .clamp(0, double.infinity)
            .toDouble();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < segments.length; i++) ...[
              if (i > 0) SizedBox(width: gap),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: SizedBox(width: available * segments[i], height: height),
              ),
            ],
          ],
        );
      },
    );
  }
}
