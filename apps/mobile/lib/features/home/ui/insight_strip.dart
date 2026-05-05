import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import 'insight_chip.dart';

/// A data model for a single insight item.
class InsightItem {
  const InsightItem({
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? iconColor;
  final VoidCallback? onTap;
}

/// Horizontal scrollable row of [InsightChip] widgets.
/// Shows actionable insights on the dashboard (rebalancing alerts,
/// goal progress, upcoming maturities, expense anomalies).
class InsightStrip extends StatelessWidget {
  const InsightStrip({super.key, required this.insights});

  final List<InsightItem> insights;

  @override
  Widget build(BuildContext context) {
    if (insights.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: insights.length,
        separatorBuilder: (_, _) => const SizedBox(width: Spacing.s8),
        itemBuilder: (context, i) {
          final item = insights[i];
          return InsightChip(
            icon: item.icon,
            label: item.label,
            value: item.value,
            iconColor: item.iconColor,
            onTap: item.onTap,
          );
        },
      ),
    );
  }
}
