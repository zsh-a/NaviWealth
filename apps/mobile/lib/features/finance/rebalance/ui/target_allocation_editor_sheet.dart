import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/features/finance/application/read_models/dashboard_providers.dart';
import 'package:naviwealth/features/finance/data/preferences/risk_appetite_preferences.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/finance/home/ui/asset_category_visuals.dart';

import '../../../../core/forms/form_dirty_guard.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../data/rebalance_providers.dart';
import '../domain/rebalance_models.dart';
import 'deviation_bar.dart';

part 'target_allocation_editor_sheet_models.dart';
part 'target_allocation_editor_sheet_widgets.dart';

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
  late final Map<AssetCategory, TextEditingController> _categoryControllers;
  final _assetControllers = <String, TextEditingController>{};
  final _disposedAssetControllers = <TextEditingController>[];
  late Map<AssetCategory, double> _categoryWeights;
  late Map<String, _AssetTargetDraft> _assetTargets;
  final _categoryErrors = <AssetCategory, String>{};
  final _assetErrors = <String, String>{};
  bool _showTotalError = false;
  bool _writingController = false;

  @override
  void initState() {
    super.initState();
    final initial = ref.read(targetAllocationProvider);
    final optionById = {
      for (final option in _assetOptions(
        ref.read(dashboardSnapshotProvider).value,
      ))
        option.assetId: option,
    };
    _categoryWeights = {
      for (final category in _editableCategories)
        category: _roundPercent(initial[category] * 100),
    };
    _assetTargets = {
      for (final target in initial.assetTargets.values)
        target.assetId: _AssetTargetDraft(
          assetId: target.assetId,
          label: optionById[target.assetId]?.label ?? target.label,
          category: optionById[target.assetId]?.category ?? target.category,
          weight: _roundPercent(target.weight * 100),
        ),
    };
    _categoryControllers = {
      for (final entry in _categoryWeights.entries)
        entry.key: TextEditingController(text: _formatInput(entry.value)),
    };
    _assetControllers.addAll({
      for (final entry in _assetTargets.entries)
        entry.key: TextEditingController(
          text: _formatInput(entry.value.weight),
        ),
    });
    for (final controller in [
      ..._categoryControllers.values,
      ..._assetControllers.values,
    ]) {
      controller.addListener(_handleTextEdit);
    }
    widget.dirty.bindTextControllers(_categoryControllers.values.toList());
    widget.dirty.snapshotBaseline();
  }

  @override
  void dispose() {
    for (final controller in [
      ..._categoryControllers.values,
      ..._assetControllers.values,
      ..._disposedAssetControllers,
    ]) {
      controller.removeListener(_handleTextEdit);
      controller.dispose();
    }
    super.dispose();
  }

  void _handleTextEdit() {
    if (_writingController) return;
    final l10n = AppLocalizations.of(context);
    final nextCategoryWeights = Map<AssetCategory, double>.from(
      _categoryWeights,
    );
    final nextAssetTargets = Map<String, _AssetTargetDraft>.from(_assetTargets);
    final nextCategoryErrors = <AssetCategory, String>{};
    final nextAssetErrors = <String, String>{};

    for (final entry in _categoryControllers.entries) {
      final raw = entry.value.text.trim();
      final value = double.tryParse(raw);
      if (raw.isEmpty || value == null) {
        nextCategoryErrors[entry.key] =
            l10n.targetAllocationEditorRequiredError;
        continue;
      }
      if (value < 0 || value > 100) {
        nextCategoryErrors[entry.key] = l10n.targetAllocationEditorRangeError;
        continue;
      }
      nextCategoryWeights[entry.key] = _roundPercent(value);
    }

    for (final entry in _assetControllers.entries) {
      final raw = entry.value.text.trim();
      final value = double.tryParse(raw);
      if (raw.isEmpty || value == null) {
        nextAssetErrors[entry.key] = l10n.targetAllocationEditorRequiredError;
        continue;
      }
      if (value < 0 || value > 100) {
        nextAssetErrors[entry.key] = l10n.targetAllocationEditorRangeError;
        continue;
      }
      final current = nextAssetTargets[entry.key];
      if (current != null) {
        nextAssetTargets[entry.key] = current.copyWith(
          weight: _roundPercent(value),
        );
      }
    }

    setState(() {
      _categoryWeights = nextCategoryWeights;
      _assetTargets = nextAssetTargets;
      _categoryErrors
        ..clear()
        ..addAll(nextCategoryErrors);
      _assetErrors
        ..clear()
        ..addAll(nextAssetErrors);
      _showTotalError = false;
    });
    widget.dirty.markDirty();
  }

  void _setCategoryWeight(AssetCategory category, double value) {
    final rounded = _roundPercent(value);
    setState(() {
      _categoryWeights = {..._categoryWeights, category: rounded};
      _categoryErrors.remove(category);
      _showTotalError = false;
    });
    _writingController = true;
    try {
      _categoryControllers[category]!.text = _formatInput(rounded);
    } finally {
      _writingController = false;
    }
    widget.dirty.markDirty();
  }

  void _setAssetWeight(String assetId, double value) {
    final rounded = _roundPercent(value);
    final current = _assetTargets[assetId];
    if (current == null) return;
    setState(() {
      _assetTargets = {
        ..._assetTargets,
        assetId: current.copyWith(weight: rounded),
      };
      _assetErrors.remove(assetId);
      _showTotalError = false;
    });
    _writingController = true;
    try {
      _assetControllers[assetId]!.text = _formatInput(rounded);
    } finally {
      _writingController = false;
    }
    widget.dirty.markDirty();
  }

  void _removeAssetTarget(String assetId) {
    final controller = _assetControllers.remove(assetId);
    if (controller != null) {
      controller.removeListener(_handleTextEdit);
      _disposedAssetControllers.add(controller);
    }
    setState(() {
      _assetTargets = {..._assetTargets}..remove(assetId);
      _assetErrors.remove(assetId);
      _showTotalError = false;
    });
    widget.dirty.markDirty();
  }

  Future<void> _addAssetTarget(List<_AssetOption> options) async {
    final l10n = AppLocalizations.of(context);
    final available = options
        .where((option) => !_assetTargets.containsKey(option.assetId))
        .toList(growable: false);
    if (available.isEmpty) return;

    final selected = await showAppSheet<_AssetOption>(
      context: context,
      title: l10n.targetAllocationEditorAddAssetTarget,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final option in available)
            FTile(
              title: Text(option.label),
              subtitle: Text(AssetCategoryVisuals.label(l10n, option.category)),
              prefix: Icon(
                AssetCategoryVisuals.icon(option.category),
                size: AppIconSizes.h18,
              ),
              onPress: () => Navigator.of(context).pop(option),
            ),
        ],
      ),
    );
    if (selected == null) return;

    final controller = TextEditingController(text: '0');
    controller.addListener(_handleTextEdit);
    setState(() {
      _assetTargets = {
        ..._assetTargets,
        selected.assetId: _AssetTargetDraft(
          assetId: selected.assetId,
          label: selected.label,
          category: selected.category,
          weight: 0,
        ),
      };
      _assetControllers[selected.assetId] = controller;
      _showTotalError = false;
    });
    widget.dirty.markDirty();
  }

  Future<void> _save() async {
    if (_categoryErrors.isNotEmpty || _assetErrors.isNotEmpty) return;
    final allocation = _allocation;
    if (!allocation.isValid) {
      setState(() => _showTotalError = true);
      return;
    }

    widget.dirty.busy = true;
    try {
      await ref.read(targetAllocationProvider.notifier).update(allocation);
      // Saving a hand-edited set of weights is what makes the user
      // "custom" — write through the SSOT so Settings + Rebalance both
      // reflect the new state instantly.
      await ref.read(riskAppetiteProvider.notifier).set(RiskAppetite.custom);
      widget.dirty.markPristine();
      if (mounted) Navigator.of(context).pop();
    } finally {
      widget.dirty.busy = false;
    }
  }

  TargetAllocation get _allocation => TargetAllocation(
    weights: {
      for (final category in _editableCategories)
        category: (_categoryWeights[category] ?? 0) / 100,
    },
    assetTargets: {
      for (final target in _assetTargets.values)
        target.assetId: AssetTargetAllocation(
          assetId: target.assetId,
          label: target.label,
          category: target.category,
          weight: target.weight / 100,
        ),
    },
  );

  double get _totalPct =>
      _categoryWeights.values.fold<double>(0, (sum, value) => sum + value) +
      _assetTargets.values.fold<double>(0, (sum, value) => sum + value.weight);

  bool get _canSave =>
      _categoryErrors.isEmpty && _assetErrors.isEmpty && _allocation.isValid;

  String _formatInput(double value) {
    if (value == value.roundToDouble()) return value.round().toString();
    return value.toStringAsFixed(1);
  }

  double _roundPercent(double value) => (value * 10).roundToDouble() / 10;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final assetOptions = _assetOptions(
      ref.watch(dashboardSnapshotProvider).value,
    );
    final hasAvailableAssets = assetOptions.any(
      (option) => !_assetTargets.containsKey(option.assetId),
    );
    final totalValid = _allocation.isValid;
    final totalColor = totalValid
        ? context.theme.colors.primary
        : context.theme.colors.destructive;
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
                  if (category == _editableCategories.first) ...[
                    _SectionLabel(
                      label: l10n.targetAllocationEditorCategoryTargets,
                    ),
                    const SizedBox(height: AppSpacing.s6),
                  ],
                  _AllocationRow(
                    rowKey: 'category-${category.name}',
                    label: AssetCategoryVisuals.label(l10n, category),
                    icon: AssetCategoryVisuals.icon(category),
                    value: _categoryWeights[category] ?? 0,
                    errorText: _categoryErrors[category],
                    controller: _categoryControllers[category]!,
                    onSliderChanged: (value) =>
                        _setCategoryWeight(category, value),
                  ),
                  const SizedBox(height: AppSpacing.s8),
                ],
                const SizedBox(height: AppSpacing.s4),
                _SectionLabel(label: l10n.targetAllocationEditorAssetTargets),
                const SizedBox(height: AppSpacing.s6),
                if (_assetTargets.isEmpty)
                  _EmptyAssetTargets(
                    message: l10n.targetAllocationEditorNoAssetTargets,
                  )
                else
                  for (final target in _assetTargets.values) ...[
                    _AllocationRow(
                      rowKey: 'asset-${target.assetId}',
                      label: target.label,
                      icon: AssetCategoryVisuals.icon(target.category),
                      value: target.weight,
                      errorText: _assetErrors[target.assetId],
                      controller: _assetControllers[target.assetId]!,
                      onSliderChanged: (value) =>
                          _setAssetWeight(target.assetId, value),
                      onRemove: () => _removeAssetTarget(target.assetId),
                    ),
                    const SizedBox(height: AppSpacing.s8),
                  ],
                FButton(
                  variant: FButtonVariant.outline,
                  onPress: hasAvailableAssets
                      ? () => _addAssetTarget(assetOptions)
                      : null,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(FLucideIcons.plus, size: AppIconSizes.sm),
                      const SizedBox(width: AppSpacing.s6),
                      Text(
                        hasAvailableAssets
                            ? l10n.targetAllocationEditorAddAssetTarget
                            : l10n.targetAllocationEditorNoAssetsAvailable,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.s4),
                _TargetPreview(
                  categoryWeights: _categoryWeights,
                  assetTargets: _assetTargets,
                ),
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
                style: context.captionStyle.copyWith(color: totalColor),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}
