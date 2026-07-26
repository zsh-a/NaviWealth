import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';

import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../accounts/domain/account_semantics.dart';
import '../../data/repositories/providers.dart';
import '../../shared/ui/forms/forms.dart';
import '../data/providers.dart';
import 'liability_l10n.dart';

/// Add/edit liability form.
///
/// Edit mode is intentionally metadata-only: principal, rate, term and
/// repayment method remain locked because changing them requires schedule
/// regeneration semantics.
class LiabilityFormPage extends ConsumerStatefulWidget {
  const LiabilityFormPage({super.key, this.liabilityId});

  final String? liabilityId;

  @override
  ConsumerState<LiabilityFormPage> createState() => _LiabilityFormPageState();
}

class _LiabilityFormPageState extends ConsumerState<LiabilityFormPage>
    with FormSubmission<LiabilityFormPage>, FormDirtyGuard<LiabilityFormPage> {
  @override
  String get leaveFallback => FinanceRoutes.wealthLiabilities;

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _principal = TextEditingController();
  final _rate = TextEditingController();
  final _term = TextEditingController();
  final _statementDay = TextEditingController();
  final _paymentDueDay = TextEditingController();
  final _currency = TextEditingController(text: 'CNY');
  final _note = TextEditingController();

  // Focus chain (loan):     name → principal → rate → currency → term.
  // Focus chain (cardCC):   name → principal → rate → currency → statementDay → paymentDueDay.
  final _nameFocus = FocusNode();
  final _principalFocus = FocusNode();
  final _rateFocus = FocusNode();
  final _currencyFocus = FocusNode();
  final _termFocus = FocusNode();
  final _statementDayFocus = FocusNode();
  final _paymentDueDayFocus = FocusNode();
  final _noteFocus = FocusNode();
  final _detailsFocus = FocusNode(debugLabel: 'liability-details');

  LiabilityType _type = LiabilityType.mortgage;
  RepaymentMethod _method = RepaymentMethod.equalInstallment;
  LiabilityRateType _rateType = LiabilityRateType.fixed;
  DateTime _startDate = DateTime.now();
  bool _loadingInitial = false;
  bool _saving = false;
  bool _detailsExpanded = false;
  Object? _loadError;
  String? _accountId;

  @override
  void initState() {
    super.initState();
    final liabilityId = widget.liabilityId;
    if (liabilityId != null) {
      _loadingInitial = true;
      unawaited(_loadExisting(liabilityId));
      return;
    }
    final defaults = ref.read(formDefaultsProvider);
    if (defaults.assetCurrency != null && defaults.assetCurrency!.isNotEmpty) {
      _currency.text = defaults.assetCurrency!;
    }
    _bindDirtyControllers(includeScheduleFields: true);
  }

  void _bindDirtyControllers({required bool includeScheduleFields}) {
    dirty.bindTextControllers([
      _name,
      _note,
      if (includeScheduleFields) ...[
        _principal,
        _rate,
        _term,
        _statementDay,
        _paymentDueDay,
        _currency,
      ],
    ]);
  }

  Future<void> _loadExisting(String id) async {
    try {
      final repo = await ref.read(liabilityRepositoryProvider.future);
      final liability = await repo.findById(id);
      if (!mounted) return;
      if (liability == null) {
        setState(() {
          _loadError = StateError('Liability $id not found');
          _loadingInitial = false;
        });
        return;
      }
      _name.text = liability.name;
      _currency.text = liability.currency;
      _note.text = liability.note ?? '';
      _accountId = liability.accountId;
      _bindDirtyControllers(includeScheduleFields: false);
      dirty.markPristine();
      setState(() {
        _loadError = null;
        _loadingInitial = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loadingInitial = false;
      });
    }
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
    _note.dispose();
    _nameFocus.dispose();
    _principalFocus.dispose();
    _rateFocus.dispose();
    _currencyFocus.dispose();
    _termFocus.dispose();
    _statementDayFocus.dispose();
    _paymentDueDayFocus.dispose();
    _noteFocus.dispose();
    _detailsFocus.dispose();
    super.dispose();
  }

  bool get _isCreditCard => _type == LiabilityType.creditCard;
  bool get _isEdit => widget.liabilityId != null;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final loadError = _loadError;
    final accountsAsync = ref.watch(accountsStreamProvider);
    final eligibleAccounts = _eligiblePayerAccounts(
      accountsAsync.value ?? const <Account>[],
    );
    final canSave =
        !_saving && accountsAsync.hasValue && eligibleAccounts.isNotEmpty;
    return guardedScope(
      child: AppFormPageScaffold(
        title: Text(
          _isEdit ? l10n.liabilityEditAction : l10n.liabilitiesAddAction,
        ),
        confirmLeave: handleBackIntent,
        child: _loadingInitial
            ? const Center(child: FCircularProgress())
            : loadError != null
            ? AppEmptyState.error(
                title: userSafeErrorMessage(context, loadError),
                retryLabel: l10n.commonRetry,
                onRetry: () {
                  final liabilityId = widget.liabilityId;
                  if (liabilityId == null) return;
                  setState(() {
                    _loadingInitial = true;
                    _loadError = null;
                  });
                  unawaited(_loadExisting(liabilityId));
                },
              )
            : Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: AppFormScaffoldBody(
                  action: SizedBox(
                    width: double.infinity,
                    child: AppBusyButton(
                      label: l10n.liabilitySaveAction,
                      busyLabel: l10n.commonSaving,
                      busy: _saving,
                      onPress: canSave ? _save : null,
                    ),
                  ),
                  children: [
                    if (submissionFailureMessage != null) ...[
                      AppStatusBanner(
                        kind: AppStatusKind.error,
                        message: submissionFailureMessage!,
                        compact: true,
                      ),
                      const SizedBox(height: AppSpacing.s12),
                    ],
                    ...(_isEdit
                        ? _editFields(l10n, accountsAsync)
                        : _createFields(l10n, accountsAsync)),
                  ],
                ),
              ),
      ),
    );
  }

  List<Widget> _editFields(
    AppLocalizations l10n,
    AsyncValue<List<Account>> accountsAsync,
  ) {
    return [
      AppStatusBanner(
        kind: AppStatusKind.info,
        message: l10n.liabilityEditMetadataOnlyHint,
        compact: true,
      ),
      const SizedBox(height: AppSpacing.s12),
      FTextFormField(
        control: FTextFieldControl.managed(controller: _name),
        label: RequiredLabel(l10n.liabilityFieldName),
        focusNode: _nameFocus,
        textInputAction: TextInputAction.next,
        validator: (v) => (v == null || v.trim().isEmpty)
            ? l10n.liabilityValidationRequired
            : null,
        onSubmit: (_) => _noteFocus.requestFocus(),
      ),
      const SizedBox(height: AppSpacing.s12),
      _payerAccountField(l10n, accountsAsync),
      const SizedBox(height: AppSpacing.s12),
      FTextFormField(
        control: FTextFieldControl.managed(controller: _note),
        label: Text(l10n.liabilityFieldNote),
        focusNode: _noteFocus,
        minLines: 3,
        maxLines: 6,
        textInputAction: TextInputAction.done,
        onSubmit: (_) => _saving ? null : _save(),
      ),
    ];
  }

  List<Widget> _createFields(
    AppLocalizations l10n,
    AsyncValue<List<Account>> accountsAsync,
  ) {
    return [
      FSelect<LiabilityType>(
        key: const Key('liability-type-field'),
        items: {
          for (final t in LiabilityType.values) liabilityTypeLabel(l10n, t): t,
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
        label: RequiredLabel(l10n.liabilityFieldName),
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
        label: RequiredLabel(l10n.liabilityFieldPrincipal),
        focusNode: _principalFocus,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.next,
        validator: _validatePositive(l10n),
        onSubmit: (_) => _rateFocus.requestFocus(),
      ),
      const SizedBox(height: AppSpacing.s12),
      FTextFormField(
        control: FTextFieldControl.managed(controller: _rate),
        label: RequiredLabel(l10n.liabilityFieldInterestRate),
        focusNode: _rateFocus,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
      FTextFormField(
        control: FTextFieldControl.managed(controller: _currency),
        label: RequiredLabel(l10n.liabilityFieldCurrency),
        focusNode: _currencyFocus,
        textInputAction: TextInputAction.next,
        textCapitalization: TextCapitalization.characters,
        validator: (v) {
          if (v == null || v.trim().length < 3) {
            return l10n.liabilityValidationRequired;
          }
          final selectedAccount = accountsAsync.value
              ?.where((account) => account.id == _accountId)
              .firstOrNull;
          if (selectedAccount != null &&
              selectedAccount.currency.toUpperCase() !=
                  v.trim().toUpperCase()) {
            return l10n.liabilityValidationAccountCurrency(
              selectedAccount.currency,
            );
          }
          return null;
        },
        onSubmit: (_) => _isCreditCard
            ? _detailsFocus.requestFocus()
            : _termFocus.requestFocus(),
      ),
      const SizedBox(height: AppSpacing.s12),
      _payerAccountField(l10n, accountsAsync),
      if (!_isCreditCard) ...[
        const SizedBox(height: AppSpacing.s12),
        FTextFormField(
          control: FTextFieldControl.managed(controller: _term),
          label: RequiredLabel(l10n.liabilityFieldTerm),
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
      ],
      const SizedBox(height: AppSpacing.s12),
      FAccordion(
        control: FAccordionControl.lifted(
          expanded: (_) => _detailsExpanded,
          onChange: (_, expanded) =>
              setState(() => _detailsExpanded = expanded),
        ),
        children: [
          FAccordionItem(
            key: const Key('liability-details-disclosure'),
            focusNode: _detailsFocus,
            title: Semantics(
              key: const Key('liability-details-toggle-label'),
              expanded: _detailsExpanded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.liabilityDetailsTitle),
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    _isCreditCard
                        ? l10n.liabilityDetailsCardSummary
                        : l10n.liabilityDetailsLoanSummary,
                    style: context.captionStyle,
                  ),
                ],
              ),
            ),
            child: Offstage(
              key: const Key('liability-details-fields'),
              offstage: !_detailsExpanded,
              child: ExcludeFocus(
                excluding: !_detailsExpanded,
                child: ExcludeSemantics(
                  excluding: !_detailsExpanded,
                  child: Column(
                    children: [
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
                      if (!_isCreditCard) ...[
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
                          key: const Key('liability-statement-day-field'),
                          control: FTextFieldControl.managed(
                            controller: _statementDay,
                          ),
                          label: Text(l10n.liabilityFieldStatementDay),
                          focusNode: _statementDayFocus,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          validator: _validateOptionalDay(l10n),
                          onSubmit: (_) => _paymentDueDayFocus.requestFocus(),
                        ),
                        const SizedBox(height: AppSpacing.s12),
                        FTextFormField(
                          key: const Key('liability-payment-due-day-field'),
                          control: FTextFieldControl.managed(
                            controller: _paymentDueDay,
                          ),
                          label: Text(l10n.liabilityFieldPaymentDueDay),
                          focusNode: _paymentDueDayFocus,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          validator: _validateOptionalDay(l10n),
                          onSubmit: (_) => _noteFocus.requestFocus(),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.s12),
                      FTextFormField(
                        control: FTextFieldControl.managed(controller: _note),
                        label: Text(l10n.liabilityFieldNote),
                        focusNode: _noteFocus,
                        minLines: 3,
                        maxLines: 6,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ];
  }

  List<Account> _eligiblePayerAccounts(List<Account> accounts) {
    final custody = accounts
        .where((account) => isCustodyAccountCategory(account.type))
        .toList(growable: false);
    if (!_isEdit) return custody;
    final currency = _currency.text.trim().toUpperCase();
    return custody
        .where((account) => account.currency.toUpperCase() == currency)
        .toList(growable: false);
  }

  Widget _payerAccountField(
    AppLocalizations l10n,
    AsyncValue<List<Account>> accountsAsync,
  ) {
    return accountsAsync.when(
      loading: () => const SkeletonCard(
        padding: EdgeInsets.all(AppSpacing.s12),
        child: SkeletonBox(height: 48),
      ),
      error: (error, stackTrace) => AppStatusBanner(
        kind: AppStatusKind.error,
        message: l10n.commonLoadFailed,
        details: userSafeErrorMessage(context, error, stackTrace: stackTrace),
        action: AppQuietButton(
          label: l10n.commonRetry,
          onPress: () => ref.invalidate(accountsStreamProvider),
        ),
      ),
      data: (accounts) {
        final eligible = _eligiblePayerAccounts(accounts);
        if (eligible.isEmpty) {
          return AppStatusBanner(
            kind: AppStatusKind.warning,
            message: l10n.liabilityPayerAccountEmpty,
            action: AppQuietButton(
              label: l10n.accountsCreateAction,
              onPress: () => context.push(FinanceRoutes.wealthAccountNew),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AccountPicker(
              key: const Key('liability-payer-account-field'),
              accounts: eligible,
              value: _accountId,
              label: l10n.liabilityFieldPayerAccount,
              onChanged: (value) => setState(() {
                _accountId = value;
                final account = eligible
                    .where((candidate) => candidate.id == value)
                    .firstOrNull;
                if (!_isEdit && account != null) {
                  _currency.text = account.currency;
                }
                dirty.markDirty();
              }),
            ),
            const SizedBox(height: AppSpacing.s6),
            Text(l10n.liabilityPayerAccountHint, style: context.captionStyle),
          ],
        );
      },
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
    if (_accountId == null) {
      AppMessenger.show(
        context,
        ToastKind.error,
        AppLocalizations.of(context).liabilityPayerAccountRequired,
      );
      return;
    }
    if (!_formKey.currentState!.validate()) {
      if (!_detailsAreValid && !_detailsExpanded) {
        setState(() => _detailsExpanded = true);
      }
      return;
    }
    final l10n = AppLocalizations.of(context);

    final liabilityId = widget.liabilityId;
    final note = _note.text.trim();
    if (liabilityId != null) {
      await submitFormAndLeave<void>(
        dirty: dirty,
        onBusyChanged: _setSaving,
        leaveFallback: FinanceRoutes.wealthLiability(liabilityId),
        tag: 'liability',
        failureMessage: (_) => l10n.commonSaveFailed,
        successMessage: l10n.commonSaved,
        commit: () async {
          final repo = await ref.read(liabilityRepositoryProvider.future);
          await repo.updateMetadata(
            id: liabilityId,
            name: _name.text.trim(),
            accountId: _accountId,
            note: note.isEmpty ? null : note,
          );
        },
      );
      return;
    }

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

    await submitFormAndLeave<void>(
      dirty: dirty,
      onBusyChanged: _setSaving,
      leaveFallback: FinanceRoutes.wealthLiabilities,
      tag: 'liability',
      failureMessage: (_) => l10n.commonSaveFailed,
      successMessage: l10n.commonSaved,
      commit: () async {
        final repo = await ref.read(liabilityRepositoryProvider.future);
        await repo.create(
          type: type,
          name: name,
          principal: principal,
          interestRate: rateFraction,
          currency: currency,
          paymentMethod: method,
          rateType: rateType,
          accountId: _accountId,
          startDate: startDate,
          termMonths: termMonths,
          statementDay: statementDay,
          paymentDueDay: paymentDueDay,
          note: note.isEmpty ? null : note,
        );
      },
    );
  }

  void _setSaving(bool value) {
    if (mounted && _saving != value) setState(() => _saving = value);
  }

  bool get _detailsAreValid {
    if (!_isCreditCard) return true;
    return _isOptionalDayValid(_statementDay.text) &&
        _isOptionalDayValid(_paymentDueDay.text);
  }

  bool _isOptionalDayValid(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return true;
    final day = int.tryParse(text);
    return day != null && day >= 1 && day <= 31;
  }
}
