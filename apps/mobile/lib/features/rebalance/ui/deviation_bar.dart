import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final barColor = switch (severity) {
      DriftSeverity.ok => colorScheme.primary,
      DriftSeverity.warning => colorScheme.tertiary,
      DriftSeverity.critical => colorScheme.error,
    };
    final bgBarColor = colorScheme.surfaceContainerHighest;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
              Text(
                '${(actualWeight * 100).toStringAsFixed(1)}%',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                ' / ${(targetWeight * 100).toStringAsFixed(1)}%',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: Spacing.s8),
              _DeviationChip(deviation: deviation, severity: severity),
            ],
          ),
          const SizedBox(height: Spacing.s4),
          Stack(
            children: [
              // Background bar.
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: actualWeight.clamp(0, 1),
                  backgroundColor: bgBarColor,
                  valueColor: AlwaysStoppedAnimation(barColor),
                  minHeight: 8,
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
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
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.s8,
        vertical: Spacing.s2,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
