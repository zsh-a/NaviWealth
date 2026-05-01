import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/haptics/haptics.dart';
import '../../../data/domain/enums.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import 'liability_l10n.dart';

/// Add-liability form. Edit support is intentionally out of scope for the
/// initial FIR-47 PR — the schedule is materialised at create time and
/// editing principal/rate/term would require a "regenerate the schedule
/// from period N" routine that's a non-trivial UX problem. The form is
/// scoped to creating new liabilities; user-driven edits become FIR-47-1.
class LiabilityFormPage extends ConsumerStatefulWidget {
  const LiabilityFormPage({super.key});

  @override
  ConsumerState<LiabilityFormPage> createState() =>
      _LiabilityFormPageState();
}

class _LiabilityFormPageState extends ConsumerState<LiabilityFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _principal = TextEditingController();
  final _rate = TextEditingController();
  final _term = TextEditingController();
  final _statementDay = TextEditingController();
  final _paymentDueDay = TextEditingController();
  final _currency = TextEditingController(text: 'CNY');

  LiabilityType _type = LiabilityType.mortgage;
  RepaymentMethod _method = RepaymentMethod.equalInstallment;
  LiabilityRateType _rateType = LiabilityRateType.fixed;
  DateTime _startDate = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _principal.dispose();
    _rate.dispose();
    _term.dispose();
    _statementDay.dispose();
    _paymentDueDay.dispose();
    _currency.dispose();
    super.dispose();
  }

  bool get _isCreditCard => _type == LiabilityType.creditCard;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.liabilitiesAddAction),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(l10n.liabilitySaveAction),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: Spacing.pageMobile,
          children: [
            DropdownButtonFormField<LiabilityType>(
              initialValue: _type,
              decoration: InputDecoration(
                labelText: l10n.liabilityFieldType,
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final t in LiabilityType.values)
                  DropdownMenuItem(
                    value: t,
                    child: Text(liabilityTypeLabel(l10n, t)),
                  ),
              ],
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
            const SizedBox(height: Spacing.s12),
            TextFormField(
              controller: _name,
              decoration: InputDecoration(
                labelText: l10n.liabilityFieldName,
                border: const OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? l10n.liabilityValidationRequired
                  : null,
            ),
            const SizedBox(height: Spacing.s12),
            TextFormField(
              controller: _principal,
              decoration: InputDecoration(
                labelText: l10n.liabilityFieldPrincipal,
                border: const OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: _validatePositive(l10n),
            ),
            const SizedBox(height: Spacing.s12),
            TextFormField(
              controller: _rate,
              decoration: InputDecoration(
                labelText: l10n.liabilityFieldInterestRate,
                border: const OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return l10n.liabilityValidationRequired;
                }
                final d = Decimal.tryParse(v.trim());
                if (d == null || d.sign < 0) {
                  return l10n.liabilityValidationPositive;
                }
                return null;
              },
            ),
            const SizedBox(height: Spacing.s12),
            DropdownButtonFormField<LiabilityRateType>(
              initialValue: _rateType,
              decoration: InputDecoration(
                labelText: l10n.liabilityFieldRateType,
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final r in LiabilityRateType.values)
                  DropdownMenuItem(
                    value: r,
                    child: Text(rateTypeLabel(l10n, r)),
                  ),
              ],
              onChanged: (v) => setState(() => _rateType = v ?? _rateType),
            ),
            const SizedBox(height: Spacing.s12),
            TextFormField(
              controller: _currency,
              decoration: InputDecoration(
                labelText: l10n.liabilityFieldCurrency,
                border: const OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().length < 3)
                  ? l10n.liabilityValidationRequired
                  : null,
            ),
            if (!_isCreditCard) ...[
              const SizedBox(height: Spacing.s12),
              TextFormField(
                controller: _term,
                decoration: InputDecoration(
                  labelText: l10n.liabilityFieldTerm,
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  final n = int.tryParse((v ?? '').trim());
                  if (n == null || n <= 0) {
                    return l10n.liabilityValidationPositive;
                  }
                  return null;
                },
              ),
              const SizedBox(height: Spacing.s12),
              _DateField(
                label: l10n.liabilityFieldStartDate,
                value: _startDate,
                onChanged: (v) => setState(() => _startDate = v),
              ),
              const SizedBox(height: Spacing.s12),
              DropdownButtonFormField<RepaymentMethod>(
                initialValue: _method,
                decoration: InputDecoration(
                  labelText: l10n.liabilityFieldMethod,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final m in RepaymentMethod.values)
                    DropdownMenuItem(
                      value: m,
                      child: Text(repaymentMethodLabel(l10n, m)),
                    ),
                ],
                onChanged: (v) => setState(() => _method = v ?? _method),
              ),
            ] else ...[
              const SizedBox(height: Spacing.s12),
              TextFormField(
                controller: _statementDay,
                decoration: InputDecoration(
                  labelText: l10n.liabilityFieldStatementDay,
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: _validateOptionalDay(l10n),
              ),
              const SizedBox(height: Spacing.s12),
              TextFormField(
                controller: _paymentDueDay,
                decoration: InputDecoration(
                  labelText: l10n.liabilityFieldPaymentDueDay,
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: _validateOptionalDay(l10n),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String? Function(String?) _validatePositive(AppLocalizations l10n) {
    return (String? v) {
      if (v == null || v.trim().isEmpty) {
        return l10n.liabilityValidationRequired;
      }
      final d = Decimal.tryParse(v.trim());
      if (d == null || d.sign <= 0) {
        return l10n.liabilityValidationPositive;
      }
      return null;
    };
  }

  String? Function(String?) _validateOptionalDay(AppLocalizations l10n) {
    return (String? v) {
      if (v == null || v.trim().isEmpty) return null;
      final n = int.tryParse(v.trim());
      if (n == null || n < 1 || n > 31) {
        return l10n.liabilityValidationDayOfMonth;
      }
      return null;
    };
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final repo = await ref.read(liabilityRepositoryProvider.future);
      // Convert percent (e.g. "4.85") to fraction (0.0485) since the model
      // stores rates as fractions but humans type percents.
      final ratePercent = Decimal.parse(_rate.text.trim());
      final rateFraction = (ratePercent / Decimal.fromInt(100)).toDecimal(
        scaleOnInfinitePrecision: 10,
      );
      await repo.create(
        type: _type,
        name: _name.text.trim(),
        principal: Decimal.parse(_principal.text.trim()),
        interestRate: rateFraction,
        currency: _currency.text.trim().toUpperCase(),
        paymentMethod: _method,
        rateType: _rateType,
        startDate: _isCreditCard ? null : _startDate,
        termMonths: _isCreditCard ? null : int.parse(_term.text.trim()),
        statementDay: _isCreditCard
            ? int.tryParse(_statementDay.text.trim())
            : null,
        paymentDueDay: _isCreditCard
            ? int.tryParse(_paymentDueDay.text.trim())
            : null,
      );
      if (mounted) {
        Haptics.success();
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime(1990),
          lastDate: DateTime(2100),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        child: Text('${value.year}-${_pad(value.month)}-${_pad(value.day)}'),
      ),
    );
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}
