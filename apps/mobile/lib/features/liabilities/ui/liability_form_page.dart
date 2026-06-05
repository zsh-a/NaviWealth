import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';

import '../../../app/route_paths.dart';
import '../../../core/haptics/haptics.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../shared/forms/forms.dart';
import '../data/providers.dart';
import 'liability_l10n.dart';

/// Add-liability form. Edit support is intentionally out of scope — the
/// schedule is materialised at create time and editing principal/rate/term
/// would require a "regenerate the schedule from period N" routine that's
/// a non-trivial UX problem. The form is scoped to creating new
/// liabilities.
class LiabilityFormPage extends ConsumerStatefulWidget {
  const LiabilityFormPage({super.key});

  @override
  ConsumerState<LiabilityFormPage> createState() => _LiabilityFormPageState();
}

class _LiabilityFormPageState extends ConsumerState<LiabilityFormPage>
    with
        OptimisticFormSubmit<LiabilityFormPage>,
        FormDirtyGuard<LiabilityFormPage> {
  @override
  String get leaveFallback => AppRoutes.wealthLiabilities;

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _principal = TextEditingController();
  final _rate = TextEditingController();
  final _term = TextEditingController();
  final _statementDay = TextEditingController();
  final _paymentDueDay = TextEditingController();
  final _currency = TextEditingController(text: 'CNY');

  // Focus chain (loan):     name → principal → rate → currency → term.
  // Focus chain (cardCC):   name → principal → rate → currency → statementDay → paymentDueDay.
  final _nameFocus = FocusNode();
  final _principalFocus = FocusNode();
  final _rateFocus = FocusNode();
  final _currencyFocus = FocusNode();
  final _termFocus = FocusNode();
  final _statementDayFocus = FocusNode();
  final _paymentDueDayFocus = FocusNode();

  LiabilityType _type = LiabilityType.mortgage;
  RepaymentMethod _method = RepaymentMethod.equalInstallment;
  LiabilityRateType _rateType = LiabilityRateType.fixed;
  DateTime _startDate = DateTime.now();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final defaults = ref.read(formDefaultsProvider);
    if (defaults.assetCurrency != null && defaults.assetCurrency!.isNotEmpty) {
      _currency.text = defaults.assetCurrency!;
    }
    // Bind after the currency pre-fill so the default does not count as
    // a user edit.
    dirty.bindTextControllers([
      _name,
      _principal,
      _rate,
      _term,
      _statementDay,
      _paymentDueDay,
      _currency,
    ]);
  }

  @override
  void dispose() {
    _name.dispose();
    _principal.dispose();
    _rate.dispose();
    _term.dispose();
    _statementDay.dispose();
    _paymentDueDay.dispose();
    _currency.dispose();
    _nameFocus.dispose();
    _principalFocus.dispose();
    _rateFocus.dispose();
    _currencyFocus.dispose();
    _termFocus.dispose();
    _statementDayFocus.dispose();
    _paymentDueDayFocus.dispose();
    super.dispose();
  }

  bool get _isCreditCard => _type == LiabilityType.creditCard;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return guardedScope(
      child: AppFormPageScaffold(
        title: Text(l10n.liabilitiesAddAction),
        confirmLeave: handleBackIntent,
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: AppFormScaffoldBody(
            action: SizedBox(
              width: double.infinity,
              child: FButton(
                variant: FButtonVariant.primary,
                onPress: _saving ? null : _save,
                child: Text(l10n.liabilitySaveAction),
              ),
            ),
            children: [
              FSelect<LiabilityType>(
                items: {
                  for (final t in LiabilityType.values)
                    liabilityTypeLabel(l10n, t): t,
                },
                control: FSelectControl<LiabilityType>.managed(
                  initial: _type,
                  onChange: (v) => setState(() {
                    _type = v ?? _type;
                    dirty.markDirty();
                  }),
                ),
                label: Text(l10n.liabilityFieldType),
              ),
              const SizedBox(height: AppSpacing.s12),
              FTextFormField(
                control: FTextFieldControl.managed(controller: _name),
                label: Text(l10n.liabilityFieldName),
                focusNode: _nameFocus,
                textInputAction: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? l10n.liabilityValidationRequired
                    : null,
                onSubmit: (_) => _principalFocus.requestFocus(),
              ),
              const SizedBox(height: AppSpacing.s12),
              FTextFormField(
                control: FTextFieldControl.managed(controller: _principal),
                label: Text(l10n.liabilityFieldPrincipal),
                focusNode: _principalFocus,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.next,
                validator: _validatePositive(l10n),
                onSubmit: (_) => _rateFocus.requestFocus(),
              ),
              const SizedBox(height: AppSpacing.s12),
              FTextFormField(
                control: FTextFieldControl.managed(controller: _rate),
                label: Text(l10n.liabilityFieldInterestRate),
                focusNode: _rateFocus,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.next,
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
                onSubmit: (_) => _currencyFocus.requestFocus(),
              ),
              const SizedBox(height: AppSpacing.s12),
              FSelect<LiabilityRateType>(
                items: {
                  for (final r in LiabilityRateType.values)
                    rateTypeLabel(l10n, r): r,
                },
                control: FSelectControl<LiabilityRateType>.managed(
                  initial: _rateType,
                  onChange: (v) => setState(() {
                    _rateType = v ?? _rateType;
                    dirty.markDirty();
                  }),
                ),
                label: Text(l10n.liabilityFieldRateType),
              ),
              const SizedBox(height: AppSpacing.s12),
              FTextFormField(
                control: FTextFieldControl.managed(controller: _currency),
                label: Text(l10n.liabilityFieldCurrency),
                focusNode: _currencyFocus,
                textInputAction: _isCreditCard
                    ? TextInputAction.next
                    : TextInputAction.next,
                textCapitalization: TextCapitalization.characters,
                validator: (v) => (v == null || v.trim().length < 3)
                    ? l10n.liabilityValidationRequired
                    : null,
                onSubmit: (_) => _isCreditCard
                    ? _statementDayFocus.requestFocus()
                    : _termFocus.requestFocus(),
              ),
              if (!_isCreditCard) ...[
                const SizedBox(height: AppSpacing.s12),
                FTextFormField(
                  control: FTextFieldControl.managed(controller: _term),
                  label: Text(l10n.liabilityFieldTerm),
                  focusNode: _termFocus,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  validator: (v) {
                    final n = int.tryParse((v ?? '').trim());
                    if (n == null || n <= 0) {
                      return l10n.liabilityValidationPositive;
                    }
                    return null;
                  },
                  onSubmit: (_) => _saving ? null : _save(),
                ),
                const SizedBox(height: AppSpacing.s12),
                DateField(
                  label: l10n.liabilityFieldStartDate,
                  initialValue: _startDate,
                  firstDate: DateTime(1990),
                  lastDate: DateTime(2100),
                  required: true,
                  enabled: !_saving,
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _startDate = v;
                      dirty.markDirty();
                    });
                  },
                ),
                const SizedBox(height: AppSpacing.s12),
                FSelect<RepaymentMethod>(
                  items: {
                    for (final m in RepaymentMethod.values)
                      repaymentMethodLabel(l10n, m): m,
                  },
                  control: FSelectControl<RepaymentMethod>.managed(
                    initial: _method,
                    onChange: (v) => setState(() {
                      _method = v ?? _method;
                      dirty.markDirty();
                    }),
                  ),
                  label: Text(l10n.liabilityFieldMethod),
                ),
              ] else ...[
                const SizedBox(height: AppSpacing.s12),
                FTextFormField(
                  control: FTextFieldControl.managed(controller: _statementDay),
                  label: Text(l10n.liabilityFieldStatementDay),
                  focusNode: _statementDayFocus,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  validator: _validateOptionalDay(l10n),
                  onSubmit: (_) => _paymentDueDayFocus.requestFocus(),
                ),
                const SizedBox(height: AppSpacing.s12),
                FTextFormField(
                  control: FTextFieldControl.managed(
                    controller: _paymentDueDay,
                  ),
                  label: Text(l10n.liabilityFieldPaymentDueDay),
                  focusNode: _paymentDueDayFocus,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  validator: _validateOptionalDay(l10n),
                  onSubmit: (_) => _saving ? null : _save(),
                ),
              ],
            ],
          ),
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
    final l10n = AppLocalizations.of(context);
    final repo = await ref.read(liabilityRepositoryProvider.future);
    if (!mounted) return;

    // Convert percent (e.g. "4.85") to fraction (0.0485) since the model
    // stores rates as fractions but humans type percents.
    final ratePercent = Decimal.parse(_rate.text.trim());
    final rateFraction = (ratePercent / Decimal.fromInt(100)).toDecimal(
      scaleOnInfinitePrecision: 10,
    );
    final type = _type;
    final name = _name.text.trim();
    final principal = Decimal.parse(_principal.text.trim());
    final currency = _currency.text.trim().toUpperCase();
    final method = _method;
    final rateType = _rateType;
    final startDate = _isCreditCard ? null : _startDate;
    final termMonths = _isCreditCard ? null : int.parse(_term.text.trim());
    final statementDay = _isCreditCard
        ? int.tryParse(_statementDay.text.trim())
        : null;
    final paymentDueDay = _isCreditCard
        ? int.tryParse(_paymentDueDay.text.trim())
        : null;
    unawaited(
      ref.read(formDefaultsProvider.notifier).rememberAsset(currency: currency),
    );

    // The record is being persisted — the post-save pop must not prompt.
    dirty.markPristine();
    await submitOptimisticAndLeave(
      leaveFallback: AppRoutes.wealthLiabilities,
      onBeforeLeave: Haptics.success,
      tag: 'liability',
      failureMessage: (_) => l10n.commonSaveFailed,
      retryLabel: l10n.commonRetry,
      write: () async {
        await repo.create(
          type: type,
          name: name,
          principal: principal,
          interestRate: rateFraction,
          currency: currency,
          paymentMethod: method,
          rateType: rateType,
          startDate: startDate,
          termMonths: termMonths,
          statementDay: statementDay,
          paymentDueDay: paymentDueDay,
        );
      },
    );
  }
}
