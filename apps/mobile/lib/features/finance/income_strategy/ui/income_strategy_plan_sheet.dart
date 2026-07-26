import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/forms/form_dirty_guard.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/shared/ui/forms/symbol_field.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:uuid/uuid.dart';

import '../composition/income_strategy_presentation.dart';
import '../data/providers.dart';
import '../domain/income_strategy.dart';
import '../domain/income_strategy_plan.dart';

/// The single write surface for per-underlying income strategy plans.
///
/// Owns every sleeve intent (dividends / Wheel / LEAPS) including the
/// Wheel put/call approval and price bounds that used to live in the
/// legacy approved-underlying sheet.
Future<void> showIncomeStrategyPlanSheet(
  BuildContext context, {
  IncomeStrategyAsset? asset,
  IncomeStrategyPlan? existing,
}) => showGuardedFormSheet<void>(
  context: context,
  builder: (_, dirty) =>
      _IncomeStrategyPlanForm(asset: asset, existing: existing, dirty: dirty),
);

class _IncomeStrategyPlanForm extends ConsumerStatefulWidget {
  const _IncomeStrategyPlanForm({
    required this.dirty,
    this.asset,
    this.existing,
  });

  final IncomeStrategyAsset? asset;
  final IncomeStrategyPlan? existing;
  final FormDirtyController dirty;

  @override
  ConsumerState<_IncomeStrategyPlanForm> createState() =>
      _IncomeStrategyPlanFormState();
}

class _IncomeStrategyPlanFormState
    extends ConsumerState<_IncomeStrategyPlanForm> {
  final _formKey = GlobalKey<FormState>();
  late Set<IncomeStrategySleeveKind> _enabled;
  final Map<IncomeStrategySleeveKind, Map<IncomeStrategySettingKey, bool>>
  _boolSettings = {};
  final Map<
    IncomeStrategySleeveKind,
    Map<IncomeStrategySettingKey, TextEditingController>
  >
  _decimalSettings = {};
  static const _kNoGroup = '';
  static const _kNewGroup = '__new__';

  LocalSecurityChoice? _choice;
  bool _advanced = false;
  bool _busy = false;
  String _groupSelection = _kNoGroup;
  late final TextEditingController _capitalBudget;
  late final TextEditingController _annualIncomeTarget;
  late final TextEditingController _maxPositionWeight;
  late final TextEditingController _notes;
  late final TextEditingController _groupName;

  bool get _isEdit => widget.existing != null || widget.asset != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final modules = ref.read(incomeStrategyModulesProvider);
    _enabled =
        existing?.enabledSleeves.toSet() ??
        modules.map((module) => module.id).toSet();
    for (final module in modules) {
      final existingIntent = existing?.intent(module.id);
      final boolValues = <IncomeStrategySettingKey, bool>{};
      final decimalValues = <IncomeStrategySettingKey, TextEditingController>{};
      for (final setting in module.presentation.settings) {
        switch (setting.control) {
          case IncomeStrategySettingControl.toggle:
            boolValues[setting.key] =
                existingIntent?.boolValue(
                  setting.key,
                  fallback: setting.defaultBool,
                ) ??
                setting.defaultBool;
          case IncomeStrategySettingControl.decimal:
            decimalValues[setting.key] = _controller(
              existingIntent?.decimalValue(setting.key),
            );
        }
      }
      _boolSettings[module.id] = boolValues;
      _decimalSettings[module.id] = decimalValues;
    }
    _capitalBudget = _controller(existing?.capitalBudget);
    _annualIncomeTarget = _controller(existing?.annualIncomeTarget);
    _maxPositionWeight = _controller(
      existing?.maxPositionWeight == null
          ? null
          : existing!.maxPositionWeight! * Decimal.fromInt(100),
    );
    _notes = TextEditingController(text: existing?.notes ?? '');
    _groupName = TextEditingController();
    _groupSelection = existing?.groupId ?? _kNoGroup;
    widget.dirty.bindTextControllers([
      _capitalBudget,
      _annualIncomeTarget,
      _maxPositionWeight,
      _notes,
      _groupName,
      for (final values in _decimalSettings.values) ...values.values,
    ]);
  }

  TextEditingController _controller(Decimal? value) =>
      TextEditingController(text: value?.toString() ?? '');

  @override
  void dispose() {
    for (final controller in [
      _capitalBudget,
      _annualIncomeTarget,
      _maxPositionWeight,
      _notes,
      _groupName,
      for (final values in _decimalSettings.values) ...values.values,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Existing explicit groups across all plans: id → display label.
  Map<String, String> _existingGroups() {
    final plans = ref.read(incomeStrategyPlansProvider).value ?? const [];
    final groups = <String, String>{};
    for (final plan in plans) {
      final groupId = plan.groupId;
      if (groupId == null || groupId.isEmpty) continue;
      groups.putIfAbsent(
        groupId,
        () => plan.groupLabel?.trim().isNotEmpty == true
            ? plan.groupLabel!.trim()
            : plan.symbol,
      );
    }
    return groups;
  }

  (String?, String?)? _resolveGroup(
    AppLocalizations l10n,
    Map<String, String> groups,
  ) {
    switch (_groupSelection) {
      case _kNoGroup:
        return (null, null);
      case _kNewGroup:
        final name = _groupName.text.trim();
        if (name.isEmpty) {
          AppMessenger.show(
            context,
            ToastKind.error,
            l10n.incomeStrategyPlanGroupNameRequired,
          );
          return null;
        }
        return (const Uuid().v4(), name);
      default:
        return (_groupSelection, groups[_groupSelection]);
    }
  }

  Decimal? _decimal(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : Decimal.tryParse(value);
  }

  String? _assetIdForSave() {
    final existing = widget.existing;
    if (existing != null) return existing.assetId;
    final asset = widget.asset;
    if (asset != null) return asset.assetId;
    final choice = _choice;
    if (choice == null) return null;
    return Asset.idFor(choice.market, choice.symbol);
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final assetId = _assetIdForSave();
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
    final existing = widget.existing;
    final fallback = widget.asset;
    final choice = _choice;
    final symbol =
        existing?.symbol ?? fallback?.symbol ?? choice!.symbol.toUpperCase();
    final market = existing?.market ?? fallback?.market ?? choice!.market.wire;
    final currency =
        existing?.currency ?? fallback?.currency ?? choice!.currency;
    final maxWeightPercent = _decimal(_maxPositionWeight);
    final resolvedGroup = _resolveGroup(l10n, _existingGroups());
    if (resolvedGroup == null) return;
    final (groupId, groupLabel) = resolvedGroup;
    setState(() => _busy = true);
    widget.dirty.busy = true;
    try {
      final modules = ref.read(incomeStrategyModulesProvider);
      final intents = <IncomeStrategySleeveKind, IncomeStrategySleeveIntent>{};
      for (final module in modules) {
        final settings =
            <IncomeStrategySettingKey, IncomeStrategySettingValue>{};
        final boolSettings = _boolSettings[module.id]!;
        final decimalSettings = _decimalSettings[module.id]!;
        for (final entry in boolSettings.entries) {
          settings[entry.key] = IncomeStrategyBoolSetting(entry.value);
        }
        for (final entry in decimalSettings.entries) {
          final value = _decimal(entry.value);
          if (value != null) {
            settings[entry.key] = IncomeStrategyDecimalSetting(value);
          }
        }
        intents[module.id] = IncomeStrategySleeveIntent(
          kind: module.id,
          enabled: _enabled.contains(module.id),
          settings: Map.unmodifiable(settings),
        );
      }
      final repository = await ref.read(
        incomeStrategyPlanRepositoryProvider.future,
      );
      await repository.upsert(
        assetId: assetId,
        symbol: symbol,
        market: market,
        currency: currency,
        sleeveIntents: intents,
        capitalBudget: _decimal(_capitalBudget),
        annualIncomeTarget: _decimal(_annualIncomeTarget),
        maxPositionWeight: maxWeightPercent == null
            ? null
            : (maxWeightPercent / Decimal.fromInt(100)).toDecimal(
                scaleOnInfinitePrecision: 8,
              ),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        groupId: groupId,
        groupLabel: groupLabel,
      );
      widget.dirty.markPristine();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        AppMessenger.show(context, ToastKind.error, l10n.commonSaveFailed);
      }
    } finally {
      widget.dirty.busy = false;
      if (mounted) setState(() => _busy = false);
    }
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
    widget.dirty.busy = true;
    try {
      final repository = await ref.read(
        incomeStrategyPlanRepositoryProvider.future,
      );
      await repository.remove(existing);
      widget.dirty.markPristine();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        AppMessenger.show(context, ToastKind.error, l10n.commonDeleteFailed);
      }
    } finally {
      widget.dirty.busy = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _validateNonNegative(AppLocalizations l10n, String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return null;
    final parsed = Decimal.tryParse(raw);
    if (parsed == null || parsed < Decimal.zero) {
      return l10n.incomeStrategyPlanNumberInvalid;
    }
    return null;
  }

  String? _validateWeight(AppLocalizations l10n, String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return null;
    final parsed = Decimal.tryParse(raw);
    if (parsed == null ||
        parsed < Decimal.zero ||
        parsed > Decimal.fromInt(100)) {
      return l10n.incomeStrategyPlanNumberInvalid;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final modules = ref.watch(incomeStrategyModulesProvider);
    return AppSheet(
      title: widget.existing == null
          ? l10n.incomeStrategyPlanAdd
          : l10n.incomeStrategyPlanEdit,
      subtitle: l10n.incomeStrategyPlanSubtitle,
      footer: AppSheetFooter(
        submitLabel: l10n.incomePlannerSaveAction,
        cancelLabel: l10n.commonCancel,
        onSubmit: _save,
        busy: _busy,
      ),
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isEdit)
              _ReadOnlyAsset(
                label: l10n.incomeStrategyPlanAsset,
                value:
                    widget.asset?.displayLabel ?? widget.existing?.symbol ?? '',
              )
            else
              SymbolField(
                label: l10n.incomeStrategyPlanAsset,
                hint: l10n.incomePlannerSymbolHint,
                initialValue: _choice,
                onChanged: (choice) {
                  widget.dirty.markDirty();
                  setState(() => _choice = choice);
                },
              ),
            const SizedBox(height: AppSpacing.s16),
            Text(
              l10n.incomeStrategyPlanSleeves,
              style: context.captionLabelStyle,
            ),
            const SizedBox(height: AppSpacing.s6),
            for (final module in modules) ...[
              _ToggleRow(
                label: module.presentation.label(l10n),
                value: _enabled.contains(module.id),
                onChanged: (value) {
                  widget.dirty.markDirty();
                  setState(() {
                    if (value) {
                      _enabled.add(module.id);
                    } else {
                      _enabled.remove(module.id);
                    }
                  });
                },
              ),
              if (_enabled.contains(module.id))
                for (final setting in module.presentation.settings.where(
                  (setting) =>
                      setting.control == IncomeStrategySettingControl.toggle,
                ))
                  Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.s16),
                    child: _ToggleRow(
                      label: setting.label(l10n),
                      value:
                          _boolSettings[module.id]?[setting.key] ??
                          setting.defaultBool,
                      onChanged: (value) {
                        widget.dirty.markDirty();
                        setState(() {
                          _boolSettings[module.id]?[setting.key] = value;
                        });
                      },
                    ),
                  ),
            ],
            const SizedBox(height: AppSpacing.s16),
            Builder(
              builder: (context) {
                final groups = _existingGroups();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FSelect<String>(
                      items: {
                        l10n.incomeStrategyPlanGroupNone: _kNoGroup,
                        for (final entry in groups.entries)
                          entry.value: entry.key,
                        l10n.incomeStrategyPlanGroupNew: _kNewGroup,
                      },
                      control: FSelectControl<String>.managed(
                        initial: _groupSelection,
                        onChange: (value) {
                          if (value == null) return;
                          widget.dirty.markDirty();
                          setState(() => _groupSelection = value);
                        },
                      ),
                      label: Text(l10n.incomeStrategyPlanGroup),
                      description: Text(l10n.incomeStrategyPlanGroupHint),
                    ),
                    AnimatedSizeFade(
                      visible: _groupSelection == _kNewGroup,
                      child: Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.s12),
                        child: FTextFormField(
                          control: FTextFieldControl.managed(
                            controller: _groupName,
                          ),
                          label: Text(l10n.incomeStrategyPlanGroupNameLabel),
                        ),
                      ),
                    ),
                  ],
                );
              },
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
                      validator: (value) => _validateNonNegative(l10n, value),
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    _DecimalField(
                      controller: _annualIncomeTarget,
                      label: l10n.incomeStrategyPlanAnnualTarget,
                      validator: (value) => _validateNonNegative(l10n, value),
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    _DecimalField(
                      controller: _maxPositionWeight,
                      label: l10n.incomeStrategyPlanMaxWeight,
                      validator: (value) => _validateWeight(l10n, value),
                    ),
                    for (final module in modules)
                      if (_enabled.contains(module.id))
                        for (final setting
                            in module.presentation.settings.where(
                              (setting) =>
                                  setting.control ==
                                  IncomeStrategySettingControl.decimal,
                            )) ...[
                          const SizedBox(height: AppSpacing.s12),
                          _DecimalField(
                            controller:
                                _decimalSettings[module.id]![setting.key]!,
                            label: setting.label(l10n),
                            validator: (value) =>
                                _validateNonNegative(l10n, value),
                          ),
                        ],
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
        ),
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
  const _DecimalField({
    required this.controller,
    required this.label,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) => FTextFormField(
    control: FTextFieldControl.managed(controller: controller),
    label: Text(label),
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    validator: validator,
  );
}
