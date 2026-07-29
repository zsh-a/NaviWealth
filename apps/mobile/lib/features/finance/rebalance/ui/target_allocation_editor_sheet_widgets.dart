part of 'target_allocation_editor_sheet.dart';

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: context.captionLabelStyle.copyWith(
        color: context.theme.colors.mutedForeground,
      ),
    );
  }
}

class _EmptyAssetTargets extends StatelessWidget {
  const _EmptyAssetTargets({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.theme.colors.muted.withValues(
            alpha: AppOpacity.subtle,
          ),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s12),
          child: Text(message, style: context.captionStyle),
        ),
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.totalPct, required this.valid});

  final double totalPct;
  final bool valid;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formatters = AppFormatters(locale: Localizations.localeOf(context));
    final colors = context.theme.colors;
    final fg = valid ? colors.primary : colors.destructive;
    final bg = valid
        ? colors.primary.withValues(alpha: AppOpacity.subtle)
        : colors.destructive.withValues(alpha: AppOpacity.subtle);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: fg.withValues(alpha: AppOpacity.muted)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s12),
        child: Row(
          children: [
            Icon(
              valid ? FLucideIcons.circleCheck : FLucideIcons.circleAlert,
              size: AppIconSizes.md,
              color: fg,
            ),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: Text(
                l10n.targetAllocationEditorTotalLabel,
                style: context.labelStyle,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedMoneyText(
                  amount: totalPct,
                  currencyCode: 'PCT',
                  symbolStyle: MoneySymbolStyle.none,
                  fractionDigits: 1,
                  style: context.strongLabelStyle.copyWith(color: fg),
                  semanticsLabel: formatters.percent(
                    totalPct / 100,
                    decimalDigits: 1,
                  ),
                ),
                Text('%', style: context.strongLabelStyle.copyWith(color: fg)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AllocationRow extends StatelessWidget {
  const _AllocationRow({
    required this.rowKey,
    required this.label,
    required this.icon,
    required this.value,
    required this.controller,
    required this.onSliderChanged,
    this.errorText,
    this.onRemove,
  });

  final String rowKey;
  final String label;
  final IconData icon;
  final double value;
  final TextEditingController controller;
  final ValueChanged<double> onSliderChanged;
  final String? errorText;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formatters = AppFormatters(locale: Localizations.localeOf(context));
    final colors = context.theme.colors;

    return SoftCard.raised(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: AppIconSizes.h18,
                  color: colors.mutedForeground,
                ),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: Text(label, style: context.theme.typography.body.sm),
                ),
                SizedBox(
                  width: AppControlWidths.detailLabel,
                  child: FTextFormField(
                    key: ValueKey('target-allocation-field-$rowKey'),
                    control: FTextFieldControl.managed(controller: controller),
                    label: Text(l10n.targetAllocationEditorPercentLabel),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: const [percentInputFormatter],
                    suffixBuilder: (_, style, variants) => Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.s8),
                      child: Text(
                        '%',
                        style: style.contentTextStyle.resolve(variants),
                      ),
                    ),
                    forceErrorText: errorText,
                  ),
                ),
                if (onRemove != null) ...[
                  const SizedBox(width: AppSpacing.s6),
                  FButton.icon(
                    variant: FButtonVariant.ghost,
                    onPress: onRemove,
                    child: const Icon(FLucideIcons.x, size: AppIconSizes.h18),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
            FSlider(
              control: FSliderControl.liftedContinuous(
                value: FSliderValue(max: value.clamp(0, 100).toDouble() / 100),
                stepPercentage: 0.001,
                onChange: (next) => onSliderChanged(next.max * 100),
              ),
              tooltipBuilder: (_, next) =>
                  Text(formatters.percent(next, decimalDigits: 1)),
              semanticValueFormatterCallback: (next) =>
                  formatters.percent(next, decimalDigits: 1),
            ),
          ],
        ),
      ),
    );
  }
}

class _TargetPreview extends StatelessWidget {
  const _TargetPreview({
    required this.categoryWeights,
    required this.assetTargets,
  });

  final Map<AssetCategory, double> categoryWeights;
  final Map<String, _AssetTargetDraft> assetTargets;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final activeCategories = [
      for (final category in _editableCategories)
        if ((categoryWeights[category] ?? 0) > 0) category,
    ];
    final activeAssets = assetTargets.values
        .where((target) => target.weight > 0)
        .toList(growable: false);
    final weights = [
      for (final category in activeCategories) categoryWeights[category] ?? 0,
      for (final target in activeAssets) target.weight,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.targetAllocationEditorPreviewTitle,
          style: context.captionLabelStyle.copyWith(
            color: context.theme.colors.mutedForeground,
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        _AllocationPreviewBar(weights: weights),
        const SizedBox(height: AppSpacing.s8),
        for (final category in activeCategories)
          SizedBox(
            width: double.infinity,
            child: DeviationBar(
              label: AssetCategoryVisuals.label(l10n, category),
              actualWeight: (categoryWeights[category] ?? 0) / 100,
              targetWeight: (categoryWeights[category] ?? 0) / 100,
              deviation: 0,
              severity: DriftSeverity.ok,
            ),
          ),
        for (final target in activeAssets)
          SizedBox(
            width: double.infinity,
            child: DeviationBar(
              label: target.label,
              actualWeight: target.weight / 100,
              targetWeight: target.weight / 100,
              deviation: 0,
              severity: DriftSeverity.ok,
            ),
          ),
      ],
    );
  }
}

class _AllocationPreviewBar extends StatelessWidget {
  const _AllocationPreviewBar({required this.weights});

  final List<double> weights;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: SizedBox(
        height: AppSpacing.s10,
        child: weights.isEmpty
            ? ColoredBox(color: colors.muted)
            : Row(
                children: [
                  for (var index = 0; index < weights.length; index++)
                    Expanded(
                      flex: (weights[index] * 10)
                          .round()
                          .clamp(1, 1000)
                          .toInt(),
                      child: ColoredBox(
                        color: colors.primary.withValues(
                          alpha: 1 - (index % 5) * 0.13,
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
