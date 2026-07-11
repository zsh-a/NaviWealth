part of 'allocation_detail_panel.dart';

class _DimensionSwitch extends StatelessWidget {
  const _DimensionSwitch({required this.value, required this.onChanged});

  final _AllocationDimension value;
  final ValueChanged<_AllocationDimension> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final labels = {
      _AllocationDimension.assetClass: l10n.portfolioViewClass,
      _AllocationDimension.currency: l10n.portfolioViewCurrency,
    };
    final icons = {
      _AllocationDimension.assetClass: FLucideIcons.layoutGrid,
      _AllocationDimension.currency: FLucideIcons.arrowLeftRight,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.theme.colors.secondary.withValues(
          alpha: AppOpacity.scrim,
        ),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s2),
        child: Row(
          children: [
            for (final dimension in _AllocationDimension.values)
              Expanded(
                child: _DimensionButton(
                  label: labels[dimension]!,
                  icon: icons[dimension]!,
                  selected: value == dimension,
                  onTap: () => onChanged(dimension),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DimensionButton extends StatelessWidget {
  const _DimensionButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? context.theme.colors.primary
        : context.theme.colors.mutedForeground;
    return FTappable(
      onPress: onTap,
      child: AnimatedContainer(
        duration: AppMotionPolicy.duration(context, Motion.fast),
        curve: Motion.standardDecelerate,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
        decoration: BoxDecoration(
          color: selected
              ? context.theme.colors.background
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.full),
          boxShadow: selected ? AppShadow.elevation1 : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: AppIconSizes.sm, color: color),
            const SizedBox(width: AppSpacing.s6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: selected
                    ? context.captionLabelStyle.copyWith(color: color)
                    : context.captionMediumStyle.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
