import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

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
    final colorScheme = Theme.of(context).colorScheme;
    final barColor = switch (severity) {
      DriftSeverity.ok => colorScheme.primary,
      DriftSeverity.warning => colorScheme.tertiary,
      DriftSeverity.critical => colorScheme.error,
    };
    final bgBarColor = colorScheme.surfaceContainerHighest;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: context.theme.typography.sm)),
              Text(
                '${(actualWeight * 100).toStringAsFixed(1)}%',
                style: context.theme.typography.sm.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                ' / ${(targetWeight * 100).toStringAsFixed(1)}%',
                style: context.theme.typography.xs.copyWith(
                  color: context.theme.colors.mutedForeground,
                ),
              ),
              const SizedBox(width: 8),
              _DeviationChip(deviation: deviation, severity: severity),
            ],
          ),
          const SizedBox(height: 4),
          Stack(
            children: [
              // Background bar.
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  height: 8,
                  child: Stack(
                    children: [
                      Positioned.fill(child: ColoredBox(color: bgBarColor)),
                      FractionallySizedBox(
                        widthFactor: actualWeight.clamp(0.0, 1.0).toDouble(),
                        child: ColoredBox(color: barColor),
                      ),
                    ],
                  ),
                ),
              ),
              // Target line.
              Positioned(
                left: null,
                right: null,
                top: 0,
                bottom: 0,
                child: FractionallySizedBox(
                  widthFactor: targetWeight.clamp(0, 1),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      width: 2,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
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
    final colorScheme = Theme.of(context).colorScheme;
    final sign = deviation >= 0 ? '+' : '';
    final text = '$sign${(deviation * 100).toStringAsFixed(1)}%';

    final (bg, fg) = switch (severity) {
      DriftSeverity.ok => (
        colorScheme.primaryContainer,
        colorScheme.onPrimaryContainer,
      ),
      DriftSeverity.warning => (
        colorScheme.tertiaryContainer,
        colorScheme.onTertiaryContainer,
      ),
      DriftSeverity.critical => (
        colorScheme.errorContainer,
        colorScheme.onErrorContainer,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: context.theme.typography.xs2.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
