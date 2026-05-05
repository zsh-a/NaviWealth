import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  return showGlassModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
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

  @override
  void initState() {
    super.initState();
    final goal = ref.read(fireGoalProvider);
    _targetCtrl = TextEditingController(text: _decimalToText(goal.targetAmount));
    _expensesCtrl =
        TextEditingController(text: _decimalToText(goal.monthlyExpenses));
    _surplusCtrl =
        TextEditingController(text: _decimalToText(goal.monthlySurplus));
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
    final viewInsets = MediaQuery.viewInsetsOf(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          Spacing.s16,
          0,
          Spacing.s16,
          Spacing.s16 + viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.fireGoalSheetTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: Spacing.s4),
                Text(
                  l10n.fireGoalSheetSubtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: Spacing.s16),
                _MoneyField(
                  controller: _targetCtrl,
                  label: l10n.fireGoalFieldTarget,
                  helper: l10n.fireGoalFieldTargetHelper,
                  required: true,
                ),
                const SizedBox(height: Spacing.s12),
                _MoneyField(
                  controller: _expensesCtrl,
                  label: l10n.fireGoalFieldMonthlyExpenses,
                  helper: l10n.fireGoalFieldMonthlyExpensesHelper,
                ),
                const SizedBox(height: Spacing.s12),
                _MoneyField(
                  controller: _surplusCtrl,
                  label: l10n.fireGoalFieldMonthlySurplus,
                  helper: l10n.fireGoalFieldMonthlySurplusHelper,
                ),
                const SizedBox(height: Spacing.s16),
                Text(
                  l10n.fireGoalFieldInflation(
                    (_inflation * 100).toStringAsFixed(1),
                  ),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Slider(
                  value: _inflation,
                  min: 0,
                  max: 0.10,
                  divisions: 20,
                  label: '${(_inflation * 100).toStringAsFixed(1)}%',
                  onChanged: (v) => setState(() => _inflation = v),
                ),
                const SizedBox(height: Spacing.s8),
                Row(
                  children: [
                    Expanded(
                      child: AppButton.secondary(
                        label: l10n.fireGoalSheetCancel,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                    const SizedBox(width: Spacing.s12),
                    Expanded(
                      child: AppButton.primary(
                        label: l10n.fireGoalSheetSave,
                        onPressed: _submit,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final goal = FireGoal(
      targetAmount: _parseDecimal(_targetCtrl.text),
      monthlyExpenses: _parseDecimal(_expensesCtrl.text),
      monthlySurplus: _parseDecimal(_surplusCtrl.text),
      inflationRate: _inflation,
    );
    await ref.read(fireGoalProvider.notifier).save(goal);
    if (mounted) {
      Haptics.success();
      Navigator.of(context).pop();
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
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        border: const OutlineInputBorder(),
      ),
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
