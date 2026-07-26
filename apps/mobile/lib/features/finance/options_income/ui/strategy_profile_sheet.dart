import 'package:decimal/decimal.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import 'package:naviwealth/core/forms/form_dirty_guard.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '../domain/options_strategy_profile.dart';
import 'income_planner_labels.dart';

/// Edit-or-create the strategy profile. Returns `true` on save.
Future<bool> showStrategyProfileSheet(BuildContext context) async {
  final result = await showGuardedFormSheet<bool>(
    context: context,
    builder: (_, dirty) => _StrategyProfileSheet(dirty: dirty),
  );
  return result ?? false;
}

class _StrategyProfileSheet extends ConsumerStatefulWidget {
  const _StrategyProfileSheet({required this.dirty});

  final FormDirtyController dirty;

  @override
  ConsumerState<_StrategyProfileSheet> createState() =>
      _StrategyProfileSheetState();
}

class _StrategyProfileSheetState extends ConsumerState<_StrategyProfileSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _minDteCtrl;
  late final TextEditingController _maxDteCtrl;
  late final TextEditingController _minYieldCtrl;
  late final TextEditingController _minOpenInterestCtrl;
  late final TextEditingController _minVolumeCtrl;
  late final TextEditingController _maxSpreadCtrl;
  late final TextEditingController _maxCapitalCtrl;
  late final TextEditingController _putDeltaLowCtrl;
  late final TextEditingController _putDeltaHighCtrl;
  late final TextEditingController _callDeltaLowCtrl;
  late final TextEditingController _callDeltaHighCtrl;
  late final TextEditingController _leapsMinDteCtrl;
  late final TextEditingController _leapsMaxDteCtrl;
  late final TextEditingController _leapsDeltaLowCtrl;
  late final TextEditingController _leapsDeltaHighCtrl;
  late final TextEditingController _leapsSpreadCtrl;
  late OptionsStrategyProfile _draft;
  bool _busy = false;
  bool _advancedOpen = false;
  bool _leapsOpen = false;
  bool _suppressControllerListeners = false;

  @override
  void initState() {
    super.initState();
    final asyncProfile = ref.read(optionsStrategyProfileProvider);
    _draft = asyncProfile.maybeWhen(
      data: (p) => p ?? defaultProfileForMode(OptionsStrategyMode.balanced),
      orElse: () => defaultProfileForMode(OptionsStrategyMode.balanced),
    );
    _minDteCtrl = TextEditingController();
    _maxDteCtrl = TextEditingController();
    _minYieldCtrl = TextEditingController();
    _minOpenInterestCtrl = TextEditingController();
    _minVolumeCtrl = TextEditingController();
    _maxSpreadCtrl = TextEditingController();
    _maxCapitalCtrl = TextEditingController();
    _putDeltaLowCtrl = TextEditingController();
    _putDeltaHighCtrl = TextEditingController();
    _callDeltaLowCtrl = TextEditingController();
    _callDeltaHighCtrl = TextEditingController();
    _leapsMinDteCtrl = TextEditingController();
    _leapsMaxDteCtrl = TextEditingController();
    _leapsDeltaLowCtrl = TextEditingController();
    _leapsDeltaHighCtrl = TextEditingController();
    _leapsSpreadCtrl = TextEditingController();
    for (final controller in _controllers) {
      controller.addListener(_markAdvancedCustom);
    }
    _seedControllers(_draft);
    widget.dirty.bindTextControllers(_controllers);
  }

  List<TextEditingController> get _controllers => [
    _minDteCtrl,
    _maxDteCtrl,
    _minYieldCtrl,
    _minOpenInterestCtrl,
    _minVolumeCtrl,
    _maxSpreadCtrl,
    _maxCapitalCtrl,
    _putDeltaLowCtrl,
    _putDeltaHighCtrl,
    _callDeltaLowCtrl,
    _callDeltaHighCtrl,
    _leapsMinDteCtrl,
    _leapsMaxDteCtrl,
    _leapsDeltaLowCtrl,
    _leapsDeltaHighCtrl,
    _leapsSpreadCtrl,
  ];

  void _setMode(OptionsStrategyMode mode) {
    widget.dirty.markDirty();
    if (mode == OptionsStrategyMode.custom) {
      setState(() => _draft = _draft.copyWith(mode: mode));
      return;
    }
    final next = defaultProfileForMode(mode).copyWith(
      // Preserve the disclosure ack across mode switches — re-presenting
      // the OCC ODD just because the user toggled Balanced → Aggressive
      // is hostile.
      riskDisclosureAckAt: _draft.riskDisclosureAckAt,
    );
    _seedControllers(next);
    setState(() => _draft = next);
  }

  void _toggleAllowed(OptionsStrategyKind kind, bool enabled) {
    widget.dirty.markDirty();
    final next = {..._draft.allowedStrategies};
    if (enabled) {
      next.add(kind);
    } else {
      next.remove(kind);
    }
    setState(() {
      _draft = _draft.copyWith(
        allowedStrategies: next,
        mode: OptionsStrategyMode.custom,
      );
    });
  }

  void _seedControllers(OptionsStrategyProfile profile) {
    _suppressControllerListeners = true;
    _minDteCtrl.text = profile.minDte.toString();
    _maxDteCtrl.text = profile.maxDte.toString();
    _minYieldCtrl.text = _percentText(profile.minAnnualizedYield);
    _minOpenInterestCtrl.text = profile.minOpenInterest.toString();
    _minVolumeCtrl.text = profile.minVolume.toString();
    _maxSpreadCtrl.text = _percentText(profile.maxBidAskSpreadPct);
    _maxCapitalCtrl.text = _percentText(profile.maxCapitalPerTradePct);
    _putDeltaLowCtrl.text = profile.deltaPutMax.abs().toString();
    _putDeltaHighCtrl.text = profile.deltaPutMin.abs().toString();
    _callDeltaLowCtrl.text = profile.deltaCallMin.toString();
    _callDeltaHighCtrl.text = profile.deltaCallMax.toString();
    _leapsMinDteCtrl.text = profile.leapsMinDte.toString();
    _leapsMaxDteCtrl.text = profile.leapsMaxDte.toString();
    _leapsDeltaLowCtrl.text = profile.leapsDeltaMin.toString();
    _leapsDeltaHighCtrl.text = profile.leapsDeltaMax.toString();
    _leapsSpreadCtrl.text = _percentText(profile.leapsMaxSpreadPct);
    _suppressControllerListeners = false;
  }

  void _markAdvancedCustom() {
    if (_suppressControllerListeners) return;
    if (_draft.mode == OptionsStrategyMode.custom) return;
    setState(() {
      _draft = _draft.copyWith(mode: OptionsStrategyMode.custom);
    });
  }

  OptionsStrategyProfile _profileFromForm(OptionsStrategyProfile draft) {
    return draft.copyWith(
      minDte: int.parse(_minDteCtrl.text.trim()),
      maxDte: int.parse(_maxDteCtrl.text.trim()),
      minAnnualizedYield: _parsePercent(_minYieldCtrl.text),
      minOpenInterest: int.parse(_minOpenInterestCtrl.text.trim()),
      minVolume: int.parse(_minVolumeCtrl.text.trim()),
      maxBidAskSpreadPct: _parsePercent(_maxSpreadCtrl.text),
      maxCapitalPerTradePct: _parsePercent(_maxCapitalCtrl.text),
      deltaPutMin: -Decimal.parse(_putDeltaHighCtrl.text.trim()),
      deltaPutMax: -Decimal.parse(_putDeltaLowCtrl.text.trim()),
      deltaCallMin: Decimal.parse(_callDeltaLowCtrl.text.trim()),
      deltaCallMax: Decimal.parse(_callDeltaHighCtrl.text.trim()),
      leapsMinDte: int.parse(_leapsMinDteCtrl.text.trim()),
      leapsMaxDte: int.parse(_leapsMaxDteCtrl.text.trim()),
      leapsDeltaMin: Decimal.parse(_leapsDeltaLowCtrl.text.trim()),
      leapsDeltaMax: Decimal.parse(_leapsDeltaHighCtrl.text.trim()),
      leapsMaxSpreadPct: _parsePercent(_leapsSpreadCtrl.text),
    );
  }

  Future<void> _save() async {
    final draft = _draft;
    final l10n = AppLocalizations.of(context);
    if (draft.allowedStrategies.isEmpty) {
      AppMessenger.show(
        context,
        ToastKind.error,
        l10n.incomePlannerProfileStrategyRequired,
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    final profile = _profileFromForm(draft);
    setState(() => _busy = true);
    widget.dirty.busy = true;
    try {
      final repo = await ref.read(
        optionsStrategyProfileRepositoryProvider.future,
      );
      await repo.upsert(profile);
      ref.invalidate(optionsStrategyProfileProvider);
      widget.dirty.markPristine();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      widget.dirty.busy = false;
      if (!mounted) return;
      setState(() => _busy = false);
      AppMessenger.show(
        context,
        ToastKind.error,
        AppLocalizations.of(context).incomePlannerProfileSaveError,
      );
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final draft = _draft;
    return AppSheet(
      title: l10n.incomePlannerProfileTitle,
      footer: AppSheetFooter(
        submitLabel: l10n.incomePlannerProfileSave,
        cancelLabel: l10n.incomePlannerProfileCancel,
        onSubmit: _save,
        busy: _busy,
      ),
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FSelect<OptionsStrategyMode>(
              key: ValueKey(draft.mode),
              items: {
                for (final mode in OptionsStrategyMode.values)
                  optionsStrategyModeLabel(l10n, mode): mode,
              },
              control: FSelectControl<OptionsStrategyMode>.managed(
                initial: draft.mode,
                onChange: (value) {
                  if (value != null) _setMode(value);
                },
              ),
              label: Text(l10n.incomePlannerProfileMode),
            ),
            const SizedBox(height: AppSpacing.s16),
            _SectionLabel(l10n.incomePlannerProfileAllowedStrategies),
            const SizedBox(height: AppSpacing.s8),
            _SwitchRow(
              label: l10n.incomePlannerProfileAllowPut,
              value: draft.allowedStrategies.contains(
                OptionsStrategyKind.cashSecuredPut,
              ),
              onChanged: (v) =>
                  _toggleAllowed(OptionsStrategyKind.cashSecuredPut, v),
            ),
            _SwitchRow(
              label: l10n.incomePlannerProfileAllowCall,
              value: draft.allowedStrategies.contains(
                OptionsStrategyKind.coveredCall,
              ),
              onChanged: (v) =>
                  _toggleAllowed(OptionsStrategyKind.coveredCall, v),
            ),
            const SizedBox(height: AppSpacing.s16),
            AppDisclosureHeader(
              title: l10n.incomePlannerProfileSellFilters,
              subtitle: l10n.incomePlannerProfileAdvancedSummary(
                draft.minDte,
                draft.maxDte,
                _percentText(draft.maxCapitalPerTradePct),
              ),
              expanded: _advancedOpen,
              onToggle: () => setState(() => _advancedOpen = !_advancedOpen),
            ),
            AnimatedSizeFade(
              visible: _advancedOpen,
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.s12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _IntegerField(
                            controller: _minDteCtrl,
                            label: l10n.incomePlannerProfileMinDte,
                            min: 0,
                            max: 365,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s12),
                        Expanded(
                          child: _IntegerField(
                            controller: _maxDteCtrl,
                            label: l10n.incomePlannerProfileMaxDte,
                            min: 1,
                            max: 365,
                            validator: (value) {
                              final base = _validateIntegerRange(
                                value,
                                l10n: l10n,
                                min: 1,
                                max: 365,
                              );
                              if (base != null) return base;
                              final minDte = int.tryParse(
                                _minDteCtrl.text.trim(),
                              );
                              final maxDte = int.tryParse((value ?? '').trim());
                              if (minDte != null &&
                                  maxDte != null &&
                                  maxDte < minDte) {
                                return l10n
                                    .incomePlannerProfileValidationDteOrder;
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    Row(
                      children: [
                        Expanded(
                          child: _PercentField(
                            controller: _minYieldCtrl,
                            label: l10n.incomePlannerProfileMinYield,
                            min: 0,
                            max: 500,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s12),
                        Expanded(
                          child: _PercentField(
                            controller: _maxSpreadCtrl,
                            label: l10n.incomePlannerProfileMaxSpread,
                            min: 0,
                            max: 100,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    Row(
                      children: [
                        Expanded(
                          child: _IntegerField(
                            controller: _minOpenInterestCtrl,
                            label: l10n.incomePlannerProfileMinOpenInterest,
                            min: 0,
                            max: 1000000,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s12),
                        Expanded(
                          child: _IntegerField(
                            controller: _minVolumeCtrl,
                            label: l10n.incomePlannerProfileMinVolume,
                            min: 0,
                            max: 1000000,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    _PercentField(
                      controller: _maxCapitalCtrl,
                      label: l10n.incomePlannerProfileMaxCapitalPerTrade,
                      min: 1,
                      max: 100,
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    _DeltaRangeRow(
                      lowController: _putDeltaLowCtrl,
                      highController: _putDeltaHighCtrl,
                      label: l10n.incomePlannerProfilePutDeltaRange,
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    _DeltaRangeRow(
                      lowController: _callDeltaLowCtrl,
                      highController: _callDeltaHighCtrl,
                      label: l10n.incomePlannerProfileCallDeltaRange,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            AppDisclosureHeader(
              title: l10n.incomePlannerProfileLeapsSection,
              subtitle: l10n.incomePlannerProfileLeapsSummary(
                draft.leapsMinDte,
                draft.leapsMaxDte,
                draft.leapsDeltaMin.toString(),
                draft.leapsDeltaMax.toString(),
              ),
              expanded: _leapsOpen,
              onToggle: () => setState(() => _leapsOpen = !_leapsOpen),
            ),
            AnimatedSizeFade(
              visible: _leapsOpen,
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.s12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _IntegerField(
                            controller: _leapsMinDteCtrl,
                            label: l10n.incomePlannerProfileLeapsMinDte,
                            min: 180,
                            max: 1460,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s12),
                        Expanded(
                          child: _IntegerField(
                            controller: _leapsMaxDteCtrl,
                            label: l10n.incomePlannerProfileLeapsMaxDte,
                            min: 180,
                            max: 1460,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    _DeltaRangeRow(
                      lowController: _leapsDeltaLowCtrl,
                      highController: _leapsDeltaHighCtrl,
                      label: l10n.incomePlannerProfileLeapsDeltaRange,
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    _PercentField(
                      controller: _leapsSpreadCtrl,
                      label: l10n.incomePlannerProfileLeapsMaxSpread,
                      min: 0,
                      max: 100,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Text(text, style: context.labelStyle),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
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
}

class _IntegerField extends StatelessWidget {
  const _IntegerField({
    required this.controller,
    required this.label,
    required this.min,
    required this.max,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final int min;
  final int max;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FTextFormField(
      control: FTextFieldControl.managed(controller: controller),
      label: Text(label),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      validator:
          validator ??
          (value) =>
              _validateIntegerRange(value, l10n: l10n, min: min, max: max),
    );
  }
}

class _PercentField extends StatelessWidget {
  const _PercentField({
    required this.controller,
    required this.label,
    required this.min,
    required this.max,
  });

  final TextEditingController controller;
  final String label;
  final int min;
  final int max;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FTextFormField(
      control: FTextFieldControl.managed(controller: controller),
      label: Text(label),
      description: Text(l10n.incomePlannerProfilePercentHelper),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      validator: (value) =>
          _validatePercentRange(value, l10n: l10n, min: min, max: max),
    );
  }
}

class _DeltaRangeRow extends StatelessWidget {
  const _DeltaRangeRow({
    required this.lowController,
    required this.highController,
    required this.label,
  });

  final TextEditingController lowController;
  final TextEditingController highController;
  final String label;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: context.captionLabelStyle),
        const SizedBox(height: AppSpacing.s6),
        Row(
          children: [
            Expanded(
              child: _DecimalField(
                controller: lowController,
                label: l10n.incomePlannerProfileDeltaLow,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.s8),
              child: Text('–'),
            ),
            Expanded(
              child: _DecimalField(
                controller: highController,
                label: l10n.incomePlannerProfileDeltaHigh,
                lowController: lowController,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DecimalField extends StatelessWidget {
  const _DecimalField({
    required this.controller,
    required this.label,
    this.lowController,
  });

  final TextEditingController controller;
  final TextEditingController? lowController;
  final String label;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FTextFormField(
      control: FTextFieldControl.managed(controller: controller),
      label: Text(label),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      validator: (value) {
        final parsed = Decimal.tryParse((value ?? '').trim());
        if (parsed == null || parsed <= Decimal.zero || parsed > Decimal.one) {
          return l10n.incomePlannerProfileDeltaValidation;
        }
        final low = Decimal.tryParse(lowController?.text.trim() ?? '');
        if (low != null && parsed < low) {
          return l10n.incomePlannerProfileDeltaOrderValidation;
        }
        return null;
      },
    );
  }
}

String? _validateIntegerRange(
  String? value, {
  required AppLocalizations l10n,
  required int min,
  required int max,
}) {
  final raw = (value ?? '').trim();
  final parsed = int.tryParse(raw);
  if (parsed == null) return l10n.incomePlannerProfileValidationNumber;
  if (parsed < min || parsed > max) {
    return l10n.incomePlannerProfileValidationRange(min, max);
  }
  return null;
}

String? _validatePercentRange(
  String? value, {
  required AppLocalizations l10n,
  required int min,
  required int max,
}) {
  final raw = (value ?? '').trim();
  final parsed = Decimal.tryParse(raw);
  if (parsed == null) return l10n.incomePlannerProfileValidationNumber;
  if (parsed < Decimal.fromInt(min) || parsed > Decimal.fromInt(max)) {
    return l10n.incomePlannerProfileValidationRange(min, max);
  }
  return null;
}

Decimal _parsePercent(String text) {
  return (Decimal.parse(text.trim()) / Decimal.fromInt(100)).toDecimal(
    scaleOnInfinitePrecision: 6,
  );
}

String _percentText(Decimal ratio) {
  final value = ratio * Decimal.fromInt(100);
  var fixed = value.toStringAsFixed(2);
  if (!fixed.contains('.')) return fixed;
  fixed = fixed.replaceFirst(RegExp(r'0+$'), '');
  return fixed.replaceFirst(RegExp(r'\.$'), '');
}
