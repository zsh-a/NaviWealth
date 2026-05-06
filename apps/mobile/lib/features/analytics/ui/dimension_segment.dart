import 'package:flutter/material.dart';

import '../../../core/haptics/haptics.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/equity_classification.dart';

/// Three-way picker for the active allocation dimension. Public so widget tests
/// can drive it without reaching into the page state.
class DimensionSegment extends StatelessWidget {
  const DimensionSegment({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final EquityAllocationDimension value;
  final ValueChanged<EquityAllocationDimension> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const selectedColor = ColorPalette.brand500;

    final labels = <EquityAllocationDimension, String>{
      EquityAllocationDimension.sector: l10n.analyticsDimensionSector,
      EquityAllocationDimension.region: l10n.analyticsDimensionRegion,
      EquityAllocationDimension.marketCap: l10n.analyticsDimensionMarketCap,
    };
    final icons = <EquityAllocationDimension, IconData>{
      EquityAllocationDimension.sector: Icons.category_outlined,
      EquityAllocationDimension.region: Icons.public,
      EquityAllocationDimension.marketCap: Icons.bar_chart,
    };

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF2C2C2E)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(Radii.full),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        children: [
          for (final dim in EquityAllocationDimension.values)
            Expanded(
              child: _DimensionChip(
                label: labels[dim]!,
                icon: icons[dim]!,
                selected: dim == value,
                selectedColor: selectedColor,
                onTap: () {
                  Haptics.selection();
                  onChanged(dim);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _DimensionChip extends StatelessWidget {
  const _DimensionChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.selectedColor,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final Color selectedColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.medium,
        curve: Motion.emphasizedDecelerate,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.full),
          boxShadow: selected ? AppElevations.of(context).level1 : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected
                  ? selectedColor
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: selected
                      ? selectedColor
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
