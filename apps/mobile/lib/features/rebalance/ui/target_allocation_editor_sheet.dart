import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../home/domain/dashboard_models.dart';
import '../../home/ui/asset_category_visuals.dart';
import '../../shared/forms/form_dirty_guard.dart';
import '../data/rebalance_providers.dart';
import '../domain/allocation_schemes.dart';
import '../domain/rebalance_models.dart';
import 'deviation_bar.dart';

const _editableCategories = <AssetCategory>[
  AssetCategory.stock,
  AssetCategory.etf,
  AssetCategory.bondsAndFunds,
  AssetCategory.cash,
  AssetCategory.crypto,
  AssetCategory.realEstate,
  AssetCategory.vehicle,
];

Future<void> showTargetAllocationEditorSheet({
  required BuildContext context,
}) async {
  final l10n = AppLocalizations.of(context);
  final dirty = FormDirtyController();
  try {
    await showAppSheet<void>(
      context: context,
      title: l10n.targetAllocationEditorTitle,
      subtitle: l10n.targetAllocationEditorSubtitle,
      maxHeightFactor: 0.94,
      dirtyGuard: dirty,
      confirmDismiss: () => confirmDiscardIfDirty(context, dirty),
      builder: (_) => TargetAllocationEditorSheet(dirty: dirty),
    );
  } finally {
    dirty.dispose();
  }
}

class TargetAllocationEditorSheet extends ConsumerStatefulWidget {
  const TargetAllocationEditorSheet({super.key, required this.dirty});

  final FormDirtyController dirty;

  @override
  ConsumerState<TargetAllocationEditorSheet> createState() =>
      _TargetAllocationEditorSheetState();
}

class _TargetAllocationEditorSheetState
    extends ConsumerState<TargetAllocationEditorSheet> {
  late final Map<AssetCategory, TextEditingController> _controllers;
  late Map<AssetCategory, double> _weights;
  final _fieldErrors = <AssetCategory, String>{};
  bool _showTotalError = false;
  bool _writingController = false;

  @override
  void initState() {
    super.initState();
    final initial = ref.read(targetAllocationProvider);
    _weights = {
      for (final category in _editableCategories)
        category: _roundPercent(initial[category] * 100),
    };
    _controllers = {
      for (final entry in _weights.entries)
        entry.key: TextEditingController(text: _formatInput(entry.value)),
    };
    for (final controller in _controllers.values) {
      controller.addListener(_handleTextEdit);
    }
    widget.dirty.bindTextControllers(_controllers.values.toList());
    widget.dirty.snapshotBaseline();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.removeListener(_handleTextEdit);
      controller.dispose();
    }
    super.dispose();
  }

  void _handleTextEdit() {
    if (_writingController) return;
    final l10n = AppLocalizations.of(context);
    final nextWeights = Map<AssetCategory, double>.from(_weights);
    final nextErrors = <AssetCategory, String>{};

    for (final entry in _controllers.entries) {
      final raw = entry.value.text.trim();
      final value = double.tryParse(raw);
      if (raw.isEmpty || value == null) {
        nextErrors[entry.key] = l10n.targetAllocationEditorRequiredError;
        continue;
      }
      if (value < 0 || value > 100) {
        nextErrors[entry.key] = l10n.targetAllocationEditorRangeError;
        continue;
      }
      nextWeights[entry.key] = _roundPercent(value);
    }

    setState(() {
      _weights = nextWeights;
      _fieldErrors
        ..clear()
        ..addAll(nextErrors);
      _showTotalError = false;
    });
  }

  void _setWeight(AssetCategory category, double value) {
    final rounded = _roundPercent(value);
    setState(() {
      _weights = {..._weights, category: rounded};
      _fieldErrors.remove(category);
      _showTotalError = false;
    });
    _writingController = true;
    try {
      _controllers[category]!.text = _formatInput(rounded);
    } finally {
      _writingController = false;
    }
    widget.dirty.markDirty();
  }

  Future<void> _save() async {
    if (_fieldErrors.isNotEmpty) return;
    final allocation = _allocation;
    if (!allocation.isValid) {
      setState(() => _showTotalError = true);
      return;
    }

    widget.dirty.busy = true;
    try {
      await ref.read(targetAllocationProvider.notifier).update(allocation);
      await ref
          .read(selectedSchemeProvider.notifier)
          .select(AllocationSchemePreset.custom);
      widget.dirty.markPristine();
      if (mounted) Navigator.of(context).pop();
    } finally {
      widget.dirty.busy = false;
    }
  }

  TargetAllocation get _allocation => TargetAllocation(
    weights: {
      for (final category in _editableCategories)
        category: (_weights[category] ?? 0) / 100,
    },
  );

  double get _totalPct =>
      _weights.values.fold<double>(0, (sum, value) => sum + value);

  bool get _canSave => _fieldErrors.isEmpty && _allocation.isValid;

  String _formatInput(double value) {
    if (value == value.roundToDouble()) return value.round().toString();
    return value.toStringAsFixed(1);
  }

  double _roundPercent(double value) => (value * 10).roundToDouble() / 10;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final totalValid = _allocation.isValid;
    final totalColor = totalValid
        ? context.theme.colors.primary
        : Theme.of(context).colorScheme.error;
    final size = MediaQuery.sizeOf(context);

    return SizedBox(
      width: size.width,
      height: size.height * 0.74,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TotalCard(totalPct: _totalPct, valid: totalValid),
          const SizedBox(height: AppSpacing.s12),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final category in _editableCategories) ...[
                  _AllocationRow(
                    category: category,
                    value: _weights[category] ?? 0,
                    errorText: _fieldErrors[category],
                    controller: _controllers[category]!,
                    onSliderChanged: (value) => _setWeight(category, value),
                  ),
                  const SizedBox(height: AppSpacing.s8),
                ],
                const SizedBox(height: AppSpacing.s4),
                _TargetPreview(weights: _weights),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s16),
          AnimatedBuilder(
            animation: widget.dirty,
            builder: (context, _) {
              return AppSheetFooter(
                cancelLabel: l10n.commonCancel,
                submitLabel: l10n.commonSave,
                busy: widget.dirty.busy,
                onSubmit: _canSave
                    ? _save
                    : () => setState(() {
                        _showTotalError = true;
                      }),
              );
            },
          ),
          if (_showTotalError || !totalValid)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s8),
              child: Text(
                l10n.targetAllocationEditorTotalHint(
                  _totalPct.toStringAsFixed(1),
                ),
                style: context.theme.typography.xs.copyWith(color: totalColor),
                textAlign: TextAlign.center,
              ),
            ),
        ],
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
    final colorScheme = Theme.of(context).colorScheme;
    final colors = context.theme.colors;
    final fg = valid ? colors.primary : colorScheme.error;
    final bg = valid
        ? colorScheme.primaryContainer.withValues(alpha: 0.22)
        : colorScheme.errorContainer.withValues(alpha: 0.28);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: fg.withValues(alpha: 0.24)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s12),
        child: Row(
          children: [
            Icon(
              valid
                  ? Icons.check_circle_outline_rounded
                  : Icons.error_outline_rounded,
              size: 20,
              color: fg,
            ),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: Text(
                l10n.targetAllocationEditorTotalLabel,
                style: context.theme.typography.sm.copyWith(
                  fontWeight: FontWeight.w600,
                ),
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
                  style: context.theme.typography.sm.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                  ),
                  semanticsLabel: '${totalPct.toStringAsFixed(1)}%',
                ),
                Text(
                  '%',
                  style: context.theme.typography.sm.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
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
    required this.category,
    required this.value,
    required this.controller,
    required this.onSliderChanged,
    this.errorText,
  });

  final AssetCategory category;
  final double value;
  final TextEditingController controller;
  final ValueChanged<double> onSliderChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final label = AssetCategoryVisuals.label(l10n, category);

    return FCard.raw(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  AssetCategoryVisuals.icon(category),
                  size: 18,
                  color: colors.mutedForeground,
                ),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: Text(label, style: context.theme.typography.sm),
                ),
                SizedBox(
                  width: 96,
                  child: FTextFormField(
                    key: ValueKey('target-allocation-field-${category.name}'),
                    control: FTextFieldControl.managed(controller: controller),
                    label: Text(l10n.targetAllocationEditorPercentLabel),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
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
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
            Material(
              type: MaterialType.transparency,
              child: Slider(
                value: value.clamp(0, 100).toDouble(),
                min: 0,
                max: 100,
                divisions: 1000,
                label: '${value.toStringAsFixed(1)}%',
                onChanged: onSliderChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TargetPreview extends StatelessWidget {
  const _TargetPreview({required this.weights});

  final Map<AssetCategory, double> weights;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.targetAllocationEditorPreviewTitle,
          style: context.theme.typography.xs.copyWith(
            color: context.theme.colors.mutedForeground,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        for (final category in _editableCategories)
          SizedBox(
            width: double.infinity,
            child: DeviationBar(
              label: AssetCategoryVisuals.label(l10n, category),
              actualWeight: (weights[category] ?? 0) / 100,
              targetWeight: (weights[category] ?? 0) / 100,
              deviation: 0,
              severity: DriftSeverity.ok,
            ),
          ),
      ],
    );
  }
}
