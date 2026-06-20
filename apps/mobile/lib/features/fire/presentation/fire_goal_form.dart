import 'package:decimal/decimal.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/haptics/haptics.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../shared/forms/forms.dart';
import '../data/fire_goal_preferences.dart';
import '../data/fire_plan_preferences.dart';
import '../domain/fire_goal.dart';
import '../domain/fire_plan.dart';

/// Bottom-sheet form for the FIRE goal inputs.
///
/// Open with [showFireGoalSheet] — the sheet pulls the current goal from
/// [fireGoalProvider], lets the user edit it, and persists via
/// [FireGoalController.save] on submit. Cancellation discards changes.
Future<void> showFireGoalSheet(BuildContext context) {
  return showGuardedFormSheet<void>(
    context: context,
    builder: (_, dirty) => _FireGoalSheet(dirty: dirty),
  );
}

class _FireGoalSheet extends ConsumerStatefulWidget {
  const _FireGoalSheet({required this.dirty});

  final FormDirtyController dirty;

  @override
  ConsumerState<_FireGoalSheet> createState() => _FireGoalSheetState();
}

class _FireGoalSheetState extends ConsumerState<_FireGoalSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _targetCtrl;
  late final TextEditingController _expensesCtrl;
  late final TextEditingController _surplusCtrl;
  late final TextEditingController _cashBucketCtrl;
  late double _inflation;
  late double _swr;
  late FireLifestyleMode _lifestyleMode;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final goal = ref.read(fireGoalProvider);
    final extras = ref.read(firePlanExtrasProvider);
    _targetCtrl = TextEditingController(
      text: _decimalToText(goal.targetAmount),
    );
    _expensesCtrl = TextEditingController(
      text: _decimalToText(goal.monthlyExpenses),
    );
    _surplusCtrl = TextEditingController(
      text: _decimalToText(goal.monthlySurplus),
    );
    _cashBucketCtrl = TextEditingController(
      text: extras.targetCashBucketMonths.toString(),
    );
    _inflation = goal.inflationRate;
    _swr = extras.safeWithdrawalRate;
    _lifestyleMode = extras.lifestyleMode;
    // Controllers were just seeded from the saved goal — that baseline
    // is not a user edit.
    widget.dirty.bindTextControllers([
      _targetCtrl,
      _expensesCtrl,
      _surplusCtrl,
      _cashBucketCtrl,
    ]);
  }

  @override
  void dispose() {
    _targetCtrl.dispose();
    _expensesCtrl.dispose();
    _surplusCtrl.dispose();
    _cashBucketCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppSheet(
      title: l10n.fireGoalSheetTitle,
      subtitle: l10n.fireGoalSheetSubtitle,
      footer: AppSheetFooter(
        submitLabel: l10n.fireGoalSheetSave,
        cancelLabel: l10n.fireGoalSheetCancel,
        onSubmit: _submit,
        busy: _saving,
      ),
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MoneyField(
              controller: _targetCtrl,
              label: l10n.fireGoalFieldTarget,
              helper: l10n.fireGoalFieldTargetHelper,
              required: true,
            ),
            const SizedBox(height: AppSpacing.s12),
            _MoneyField(
              controller: _expensesCtrl,
              label: l10n.fireGoalFieldMonthlyExpenses,
              helper: l10n.fireGoalFieldMonthlyExpensesHelper,
            ),
            const SizedBox(height: AppSpacing.s12),
            _MoneyField(
              controller: _surplusCtrl,
              label: l10n.fireGoalFieldMonthlySurplus,
              helper: l10n.fireGoalFieldMonthlySurplusHelper,
            ),
            const SizedBox(height: AppSpacing.s16),
            Text(
              l10n.fireGoalFieldInflation(
                (_inflation * 100).toStringAsFixed(1),
              ),
              style: context.theme.typography.sm,
            ),
            FSlider(
              control: FSliderControl.managedContinuous(
                initial: FSliderValue(max: _inflation / 0.10),
                onChange: (v) => setState(() {
                  _inflation = v.max * 0.10;
                  widget.dirty.markDirty();
                }),
              ),
            ),
            const SizedBox(height: AppSpacing.s24),
            // FIRE OS extras: advanced planning knobs. Stay folded into
            // the same sheet so saving stays a single confirm.
            Text(
              l10n.fireOsPlanFormAdvancedTitle,
              style: context.bodyCaptionStyle,
            ),
            const SizedBox(height: AppSpacing.s12),
            Text(
              '${l10n.fireOsPlanFormSwrLabel} · '
              '${l10n.fireOsPlanFormSwrValue((_swr * 100).toStringAsFixed(1))}',
              style: context.theme.typography.sm,
            ),
            FSlider(
              control: FSliderControl.managedContinuous(
                initial: FSliderValue(max: _swr / 0.10),
                onChange: (v) => setState(() {
                  _swr = v.max * 0.10;
                  widget.dirty.markDirty();
                }),
              ),
            ),
            Text(l10n.fireOsPlanFormSwrHelper, style: context.captionStyle),
            const SizedBox(height: AppSpacing.s12),
            FTextFormField(
              control: FTextFieldControl.managed(controller: _cashBucketCtrl),
              label: Text(l10n.fireOsPlanFormCashBucketLabel),
              description: Text(l10n.fireOsPlanFormCashBucketHelper),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
              ],
              validator: (value) {
                final raw = (value ?? '').trim();
                if (raw.isEmpty) return null;
                final parsed = int.tryParse(raw);
                if (parsed == null || parsed < 0 || parsed > 60) {
                  return l10n.fireGoalValidationInvalidNumber;
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.s12),
            Text(
              l10n.fireOsPlanFormLifestyleLabel,
              style: context.theme.typography.sm,
            ),
            const SizedBox(height: AppSpacing.s8),
            Wrap(
              spacing: AppSpacing.s8,
              runSpacing: AppSpacing.s8,
              children: [
                for (final mode in FireLifestyleMode.values)
                  FButton(
                    variant: _lifestyleMode == mode
                        ? FButtonVariant.primary
                        : FButtonVariant.outline,
                    onPress: () => setState(() {
                      _lifestyleMode = mode;
                      widget.dirty.markDirty();
                    }),
                    child: Text(_lifestyleLabel(l10n, mode)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _lifestyleLabel(AppLocalizations l10n, FireLifestyleMode m) {
    switch (m) {
      case FireLifestyleMode.lean:
        return l10n.fireOsPlanFormLifestyleLean;
      case FireLifestyleMode.standard:
        return l10n.fireOsPlanFormLifestyleStandard;
      case FireLifestyleMode.fat:
        return l10n.fireOsPlanFormLifestyleFat;
      case FireLifestyleMode.coast:
        return l10n.fireOsPlanFormLifestyleCoast;
      case FireLifestyleMode.barista:
        return l10n.fireOsPlanFormLifestyleBarista;
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    widget.dirty.busy = true;
    try {
      final goal = FireGoal(
        targetAmount: _parseDecimal(_targetCtrl.text),
        monthlyExpenses: _parseDecimal(_expensesCtrl.text),
        monthlySurplus: _parseDecimal(_surplusCtrl.text),
        inflationRate: _inflation,
      );
      final extras = ref.read(firePlanExtrasProvider);
      final cashMonths =
          int.tryParse(_cashBucketCtrl.text.trim()) ??
          FirePlan.defaultCashBucketMonths;
      final updatedExtras = extras.copyWith(
        safeWithdrawalRate: _swr,
        targetCashBucketMonths: cashMonths,
        lifestyleMode: _lifestyleMode,
      );
      await ref.read(fireGoalProvider.notifier).save(goal);
      await ref.read(firePlanExtrasProvider.notifier).save(updatedExtras);
      if (!mounted) return;
      widget.dirty.markPristine();
      Haptics.success();
      Navigator.of(context).pop();
    } on Object {
      if (!mounted) return;
      Haptics.error();
      AppMessenger.show(context, ToastKind.error, l10n.commonSaveFailed);
    } finally {
      widget.dirty.busy = false;
      if (mounted) setState(() => _saving = false);
    }
  }

  static String _decimalToText(Decimal value) {
    if (value == Decimal.zero) return '';
    return value.toString();
  }

  static Decimal _parseDecimal(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return Decimal.zero;
    return Decimal.parse(trimmed);
  }
}

class _MoneyField extends StatelessWidget {
  const _MoneyField({
    required this.controller,
    required this.label,
    required this.helper,
    this.required = false,
  });

  final TextEditingController controller;
  final String label;
  final String helper;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FTextFormField(
      control: FTextFieldControl.managed(controller: controller),
      label: Text(label),
      description: Text(helper),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      validator: (value) {
        final text = (value ?? '').trim();
        if (text.isEmpty) {
          return required ? l10n.fireGoalValidationRequired : null;
        }
        final parsed = Decimal.tryParse(text);
        if (parsed == null) return l10n.fireGoalValidationInvalidNumber;
        if (parsed < Decimal.zero) {
          return l10n.fireGoalValidationNonNegative;
        }
        if (required && parsed == Decimal.zero) {
          return l10n.fireGoalValidationPositive;
        }
        return null;
      },
    );
  }
}
