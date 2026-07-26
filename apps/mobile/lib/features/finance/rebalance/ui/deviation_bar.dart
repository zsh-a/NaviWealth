import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../../core/format/formatters.dart';
import '../../../../design_system/design_system.dart';

import '../domain/rebalance_models.dart';

/// A horizontal bar showing actual vs target allocation for a single
/// category, with a colored indicator for drift severity.
class DeviationBar extends StatelessWidget {
  const DeviationBar({
    super.key,
    required this.label,
    required this.actualWeight,
    required this.targetWeight,
    required this.deviation,
    required this.severity,
  });

  final String label;
  final double actualWeight;
  final double targetWeight;
  final double deviation;
  final DriftSeverity severity;

  @override
  Widget build(BuildContext context) {
    final semantic = SemanticColors.of(context);
    final formatters = AppFormatters(locale: Localizations.localeOf(context));
    final barColor = switch (severity) {
      DriftSeverity.ok => context.theme.colors.primary,
      DriftSeverity.warning => semantic.warning,
      DriftSeverity.critical => semantic.danger,
    };
    final bgBarColor = context.theme.colors.secondary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: context.theme.typography.body.sm),
              ),
              Text(
                formatters.percent(actualWeight, decimalDigits: 1),
                style: context.labelStyle,
              ),
              Text(
                ' / ${formatters.percent(targetWeight, decimalDigits: 1)}',
                style: context.captionStyle,
              ),
              const SizedBox(width: AppSpacing.s8),
              _DeviationChip(deviation: deviation, severity: severity),
            ],
          ),
          const SizedBox(height: AppSpacing.s4),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.hasBoundedWidth
                  ? constraints.maxWidth
                  : MediaQuery.sizeOf(context).width;
              final actualWidth =
                  width * actualWeight.clamp(0.0, 1.0).toDouble();
              final targetLeft =
                  width * targetWeight.clamp(0.0, 1.0).toDouble();
              return SizedBox(
                width: width,
                height: AppSpacing.s8,
                child: Stack(
                  children: [
                    // Background bar.
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: SizedBox(
                        height: AppSpacing.s8,
                        child: ColoredBox(
                          color: bgBarColor,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              width: actualWidth,
                              height: AppSpacing.s8,
                              child: ColoredBox(color: barColor),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Target line.
                    Positioned(
                      left: targetLeft.clamp(0.0, width - 2),
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 2,
                        color: context.theme.colors.mutedForeground,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DeviationChip extends StatelessWidget {
  const _DeviationChip({required this.deviation, required this.severity});

  final double deviation;
  final DriftSeverity severity;

  @override
  Widget build(BuildContext context) {
    final semantic = SemanticColors.of(context);
    final formatters = AppFormatters(locale: Localizations.localeOf(context));
    final text = formatters.signedPercent(deviation, decimalDigits: 1);

    final (bg, fg) = switch (severity) {
      DriftSeverity.ok => (
        AccentColors.tint(context.theme.colors.brightness),
        context.theme.colors.primary,
      ),
      DriftSeverity.warning => (
        semantic.warningContainer,
        semantic.onWarningContainer,
      ),
      DriftSeverity.critical => (
        semantic.dangerContainer,
        semantic.onDangerContainer,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s2,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(text, style: context.microLabelStyle.copyWith(color: fg)),
    );
  }
}
