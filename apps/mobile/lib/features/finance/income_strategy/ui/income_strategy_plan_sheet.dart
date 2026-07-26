import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/persistence/domain_enums.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/investment/data/providers.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../data/providers.dart';
import '../domain/income_strategy.dart';
import '../domain/income_strategy_plan.dart';

Future<void> showIncomeStrategyPlanSheet(
  BuildContext context, {
  IncomeStrategyAsset? asset,
  IncomeStrategyPlan? existing,
}) => showAppFormSheet<void>(
  context: context,
  builder: (_) => _IncomeStrategyPlanForm(asset: asset, existing: existing),
);

class _IncomeStrategyPlanForm extends ConsumerStatefulWidget {
  const _IncomeStrategyPlanForm({this.asset, this.existing});

  final IncomeStrategyAsset? asset;
  final IncomeStrategyPlan? existing;

  @override
  ConsumerState<_IncomeStrategyPlanForm> createState() =>
      _IncomeStrategyPlanFormState();
}

class _IncomeStrategyPlanFormState
    extends ConsumerState<_IncomeStrategyPlanForm> {
  late Set<IncomeStrategySleeveKind> _enabled;
  late bool _preserveDividend;
  late bool _allowSharesCalledAway;
  String? _assetId;
  bool _advanced = false;
  bool _busy = false;
  late final TextEditingController _capitalBudget;
  late final TextEditingController _annualIncomeTarget;
  late final TextEditingController _maxPositionWeight;
  late final TextEditingController _maxLeapsCost;
  late final TextEditingController _maxAssignmentValue;
  late final TextEditingController _notes;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _assetId = existing?.assetId ?? widget.asset?.assetId;
    _enabled =
        existing?.enabledSleeves.toSet() ??
        IncomeStrategySleeveKind.values.toSet();
    _preserveDividend = existing?.preserveDividend ?? true;
    _allowSharesCalledAway = existing?.allowSharesCalledAway ?? false;
    _capitalBudget = _controller(existing?.capitalBudget);
    _annualIncomeTarget = _controller(existing?.annualIncomeTarget);
    _maxPositionWeight = _controller(
      existing?.maxPositionWeight == null
          ? null
          : existing!.maxPositionWeight! * Decimal.fromInt(100),
    );
    _maxLeapsCost = _controller(existing?.maxLeapsCost);
    _maxAssignmentValue = _controller(existing?.maxAssignmentValue);
    _notes = TextEditingController(text: existing?.notes ?? '');
  }

  TextEditingController _controller(Decimal? value) =>
      TextEditingController(text: value?.toString() ?? '');

  @override
  void dispose() {
    for (final controller in [
      _capitalBudget,
      _annualIncomeTarget,
      _maxPositionWeight,
      _maxLeapsCost,
      _maxAssignmentValue,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Decimal? _decimal(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : Decimal.parse(value);
  }

  Future<void> _save(List<Asset> assets) async {
    final l10n = AppLocalizations.of(context);
    final assetId = _assetId;
    if (assetId == null || _enabled.isEmpty) {
      AppMessenger.show(
        context,
        ToastKind.error,
        _enabled.isEmpty
            ? l10n.incomeStrategyPlanSleeveRequired
            : l10n.incomeStrategyPlanAssetRequired,
      );
      return;
    }
    final source = assets.where((asset) => asset.id == assetId).firstOrNull;
    final fallback = widget.asset;
    if (source == null && fallback == null) return;
    final symbol = source?.symbol ?? fallback!.symbol;
    final market =
        source?.market ?? fallback?.market ?? inferAssetMarket(symbol).wire;
    final currency = source?.currency ?? fallback?.currency ?? 'USD';
    final maxWeightPercent = _decimal(_maxPositionWeight);
    if (!_validNonNegativeFields() ||
        (maxWeightPercent != null &&
            (maxWeightPercent < Decimal.zero ||
                maxWeightPercent > Decimal.fromInt(100)))) {
      AppMessenger.show(
        context,
        ToastKind.error,
        l10n.incomeStrategyPlanNumberInvalid,
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final repository = await ref.read(
        incomeStrategyPlanRepositoryProvider.future,
      );
      await repository.upsert(
        assetId: assetId,
        symbol: symbol,
        market: market,
        currency: currency,
        enabledSleeves: _enabled,
        capitalBudget: _decimal(_capitalBudget),
        annualIncomeTarget: _decimal(_annualIncomeTarget),
        maxPositionWeight: maxWeightPercent == null
            ? null
            : (maxWeightPercent / Decimal.fromInt(100)).toDecimal(
                scaleOnInfinitePrecision: 8,
              ),
        maxLeapsCost: _decimal(_maxLeapsCost),
        maxAssignmentValue: _decimal(_maxAssignmentValue),
        preserveDividend: _preserveDividend,
        allowSharesCalledAway: _allowSharesCalledAway,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        AppMessenger.show(context, ToastKind.error, l10n.commonSaveFailed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _validNonNegativeFields() {
    for (final controller in [
      _capitalBudget,
      _annualIncomeTarget,
      _maxLeapsCost,
      _maxAssignmentValue,
    ]) {
      final value = controller.text.trim();
      if (value.isEmpty) continue;
      final parsed = Decimal.tryParse(value);
      if (parsed == null || parsed < Decimal.zero) return false;
    }
    return Decimal.tryParse(
          _maxPositionWeight.text.trim().isEmpty
              ? '0'
              : _maxPositionWeight.text.trim(),
        ) !=
        null;
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context: context,
      title: Text(l10n.incomeStrategyPlanDeleteTitle),
      body: Text(l10n.incomeStrategyPlanDeleteBody),
      cancelLabel: l10n.commonCancel,
      confirmLabel: l10n.commonDelete,
      destructive: true,
      icon: FLucideIcons.trash2,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final repository = await ref.read(
        incomeStrategyPlanRepositoryProvider.future,
      );
      await repository.remove(existing);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        AppMessenger.show(context, ToastKind.error, l10n.commonDeleteFailed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final assetsAsync = ref.watch(allAssetsStreamProvider);
    return AppSheet(
      title: widget.existing == null
          ? l10n.incomeStrategyPlanAdd
          : l10n.incomeStrategyPlanEdit,
      subtitle: l10n.incomeStrategyPlanSubtitle,
      footer: AppSheetFooter(
        submitLabel: l10n.incomePlannerSaveAction,
        cancelLabel: l10n.commonCancel,
        onSubmit: () => _save(assetsAsync.value ?? const []),
        busy: _busy,
      ),
      child: assetsAsync.whenOrLoading(
        context: context,
        data: (allAssets) {
          final assets = allAssets
              .where((asset) => kSecuritiesAssetTypes.contains(asset.type))
              .toList(growable: false);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.asset == null && widget.existing == null)
                FSelect<String>.rich(
                  format: (id) =>
                      assets
                          .where((asset) => asset.id == id)
                          .map((asset) => asset.symbol)
                          .firstOrNull ??
                      '',
                  control: FSelectControl<String>.lifted(
                    value: _assetId,
                    onChange: (value) => setState(() => _assetId = value),
                  ),
                  label: Text(l10n.incomeStrategyPlanAsset),
                  children: [
                    for (final asset in assets)
                      FSelectItem<String>(
                        value: asset.id,
                        title: Text(
                          '${asset.symbol} · ${asset.name ?? asset.market ?? ''}',
                        ),
                      ),
                  ],
                )
              else
                _ReadOnlyAsset(
                  label: l10n.incomeStrategyPlanAsset,
                  value:
                      widget.asset?.displayLabel ??
                      widget.existing?.symbol ??
                      '—',
                ),
              const SizedBox(height: AppSpacing.s16),
              Text(
                l10n.incomeStrategyPlanSleeves,
                style: context.captionLabelStyle,
              ),
              const SizedBox(height: AppSpacing.s6),
              for (final sleeve in IncomeStrategySleeveKind.values)
                _ToggleRow(
                  label: _sleeveLabel(l10n, sleeve),
                  value: _enabled.contains(sleeve),
                  onChanged: (value) => setState(() {
                    if (value) {
                      _enabled.add(sleeve);
                    } else {
                      _enabled.remove(sleeve);
                    }
                  }),
                ),
              const SizedBox(height: AppSpacing.s12),
              _ToggleRow(
                label: l10n.incomeStrategyPlanPreserveDividend,
                value: _preserveDividend,
                onChanged: (value) => setState(() => _preserveDividend = value),
              ),
              _ToggleRow(
                label: l10n.incomeStrategyPlanAllowCalledAway,
                value: _allowSharesCalledAway,
                onChanged: (value) =>
                    setState(() => _allowSharesCalledAway = value),
              ),
              const SizedBox(height: AppSpacing.s16),
              AppDisclosureHeader(
                title: l10n.incomeStrategyPlanLimits,
                subtitle: l10n.incomeStrategyPlanLimitsHint,
                expanded: _advanced,
                onToggle: () => setState(() => _advanced = !_advanced),
              ),
              AnimatedSizeFade(
                visible: _advanced,
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.s12),
                  child: Column(
                    children: [
                      _DecimalField(
                        controller: _capitalBudget,
                        label: l10n.incomeStrategyPlanCapitalBudget,
                      ),
                      const SizedBox(height: AppSpacing.s12),
                      _DecimalField(
                        controller: _annualIncomeTarget,
                        label: l10n.incomeStrategyPlanAnnualTarget,
                      ),
                      const SizedBox(height: AppSpacing.s12),
                      _DecimalField(
                        controller: _maxPositionWeight,
                        label: l10n.incomeStrategyPlanMaxWeight,
                      ),
                      const SizedBox(height: AppSpacing.s12),
                      _DecimalField(
                        controller: _maxLeapsCost,
                        label: l10n.incomeStrategyPlanMaxLeapsCost,
                      ),
                      const SizedBox(height: AppSpacing.s12),
                      _DecimalField(
                        controller: _maxAssignmentValue,
                        label: l10n.incomeStrategyPlanMaxAssignment,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.s16),
              FTextFormField(
                control: FTextFieldControl.managed(controller: _notes),
                label: Text(l10n.incomePlannerJournalNotesLabel),
                maxLines: 3,
              ),
              if (widget.existing != null) ...[
                const SizedBox(height: AppSpacing.s20),
                FButton(
                  variant: FButtonVariant.destructive,
                  onPress: _busy ? null : _delete,
                  child: Text(l10n.commonDelete),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ReadOnlyAsset extends StatelessWidget {
  const _ReadOnlyAsset({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: context.captionLabelStyle),
      const SizedBox(height: AppSpacing.s4),
      Text(value, style: context.labelStyle),
    ],
  );
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
    child: Row(
      children: [
        Expanded(child: Text(label, style: context.bodyCaptionStyle)),
        const SizedBox(width: AppSpacing.s12),
        FSwitch(value: value, onChange: onChanged),
      ],
    ),
  );
}

class _DecimalField extends StatelessWidget {
  const _DecimalField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) => FTextFormField(
    control: FTextFieldControl.managed(controller: controller),
    label: Text(label),
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
  );
}

String _sleeveLabel(AppLocalizations l10n, IncomeStrategySleeveKind sleeve) =>
    switch (sleeve) {
      IncomeStrategySleeveKind.dividends => l10n.incomeStrategySleeveDividends,
      IncomeStrategySleeveKind.wheel => l10n.incomeStrategySleeveWheel,
      IncomeStrategySleeveKind.leapsCall => l10n.incomeStrategySleeveLeaps,
    };
