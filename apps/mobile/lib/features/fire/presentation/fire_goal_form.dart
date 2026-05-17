import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/haptics/haptics.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/fire_goal_preferences.dart';
import '../domain/fire_goal.dart';

/// Bottom-sheet form for the FIRE goal inputs.
///
/// Open with [showFireGoalSheet] — the sheet pulls the current goal from
/// [fireGoalProvider], lets the user edit it, and persists via
/// [FireGoalController.save] on submit. Cancellation discards changes.
Future<void> showFireGoalSheet(BuildContext context) {
  return showAppFormSheet<void>(
    context: context,
    builder: (_) => const _FireGoalSheet(),
  );
}

class _FireGoalSheet extends ConsumerStatefulWidget {
  const _FireGoalSheet();

  @override
  ConsumerState<_FireGoalSheet> createState() => _FireGoalSheetState();
}

class _FireGoalSheetState extends ConsumerState<_FireGoalSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _targetCtrl;
  late final TextEditingController _expensesCtrl;
  late final TextEditingController _surplusCtrl;
  late double _inflation;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final goal = ref.read(fireGoalProvider);
    _targetCtrl = TextEditingController(
      text: _decimalToText(goal.targetAmount),
    );
    _expensesCtrl = TextEditingController(
      text: _decimalToText(goal.monthlyExpenses),
    );
    _surplusCtrl = TextEditingController(
      text: _decimalToText(goal.monthlySurplus),
    );
    _inflation = goal.inflationRate;
  }

  @override
  void dispose() {
    _targetCtrl.dispose();
    _expensesCtrl.dispose();
    _surplusCtrl.dispose();
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
            const SizedBox(height: 12),
            _MoneyField(
              controller: _expensesCtrl,
              label: l10n.fireGoalFieldMonthlyExpenses,
              helper: l10n.fireGoalFieldMonthlyExpensesHelper,
            ),
            const SizedBox(height: 12),
            _MoneyField(
              controller: _surplusCtrl,
              label: l10n.fireGoalFieldMonthlySurplus,
              helper: l10n.fireGoalFieldMonthlySurplusHelper,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.fireGoalFieldInflation(
                (_inflation * 100).toStringAsFixed(1),
              ),
              style: context.theme.typography.sm,
            ),
            FSlider(
              control: FSliderControl.managedContinuous(
                initial: FSliderValue(max: _inflation / 0.10),
                onChange: (v) => setState(() => _inflation = v.max * 0.10),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final goal = FireGoal(
        targetAmount: _parseDecimal(_targetCtrl.text),
        monthlyExpenses: _parseDecimal(_expensesCtrl.text),
        monthlySurplus: _parseDecimal(_surplusCtrl.text),
        inflationRate: _inflation,
      );
      await ref.read(fireGoalProvider.notifier).save(goal);
      if (!mounted) return;
      Haptics.success();
      Navigator.of(context).pop();
    } finally {
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
