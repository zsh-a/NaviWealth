import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/data/domain/account.dart';
import 'package:naviwealth/features/finance/data/domain/asset.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/domain/manual_asset_metadata.dart';
import 'package:naviwealth/features/finance/data/repositories/manual_asset_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';

import '../../core/ai/write/write.dart';
import '../../core/haptics/haptics.dart';
import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';
import '../finance/shared/forms/forms.dart';

/// Create / edit form for 理财产品 (manual-valuation wealth products).
class WealthProductFormPage extends ConsumerStatefulWidget {
  const WealthProductFormPage({super.key, this.assetId});

  final String? assetId;

  bool get isEdit => assetId != null;

  @override
  ConsumerState<WealthProductFormPage> createState() =>
      _WealthProductFormPageState();
}

class _WealthProductFormPageState extends ConsumerState<WealthProductFormPage>
    with FormDirtyGuard<WealthProductFormPage> {
  @override
  String get leaveFallback => FinanceRoutes.wealth;

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _principalController = TextEditingController();
  final _expectedReturnPctController = TextEditingController();
  final _valuationController = TextEditingController();
  final _issuerController = TextEditingController();
  final _productCodeController = TextEditingController();

  // Focus chain: name → issuer → productCode → principal → return → valuation.
  final _nameFocus = FocusNode();
  final _issuerFocus = FocusNode();
  final _productCodeFocus = FocusNode();
  final _principalFocus = FocusNode();
  final _returnFocus = FocusNode();
  final _valuationFocus = FocusNode();

  String? _accountId;
  String? _currency = 'CNY';
  DateTime? _startDate;
  DateTime? _maturityDate;
  bool _busy = false;
  Asset? _initial;
  bool _hydratedFromList = false;

  static const _eligibleAccountTypes = {
    AccountCategory.bank,
    AccountCategory.broker,
    AccountCategory.asset,
  };

  @override
  void initState() {
    super.initState();
    dirty.bindTextControllers([
      _nameController,
      _principalController,
      _expectedReturnPctController,
      _valuationController,
      _issuerController,
      _productCodeController,
    ]);
    if (widget.isEdit) {
      _loadInitial();
    } else {
      final defaults = ref.read(formDefaultsProvider);
      _accountId = defaults.assetAccountId;
      if (defaults.assetCurrency != null &&
          defaults.assetCurrency!.isNotEmpty) {
        _currency = defaults.assetCurrency;
      }
    }
  }

  Future<void> _loadInitial() async {
    final repo = await ref.read(manualAssetRepositoryProvider.future);
    final existing = await repo.findById(widget.assetId!);
    if (existing == null || !mounted) return;
    final meta = existing.manualMetadata;
    if (meta is! WealthProductMetadata) return;
    setState(() {
      _initial = existing;
      _nameController.text = existing.name ?? '';
      _accountId = meta.accountId;
      _currency = existing.currency;
      _principalController.text = meta.principal.toString();
      _expectedReturnPctController.text =
          (meta.expectedAnnualReturn * Decimal.fromInt(100)).toString();
      _valuationController.text = '';
      _startDate = meta.startDate;
      _maturityDate = meta.maturityDate;
      _issuerController.text = meta.issuer ?? '';
      _productCodeController.text = meta.productCode ?? '';
    });
    // Hydrating an existing record is not a user edit.
    dirty.snapshotBaseline();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    final accountId = _accountId;
    final currency = _currency;
    if (accountId == null || currency == null) {
      AppMessenger.show(
        context,
        ToastKind.error,
        l10n.formAccountPickerRequired,
      );
      return;
    }
    setState(() => _busy = true);
    dirty.busy = true;
    try {
      final principal = Decimal.tryParse(_principalController.text.trim());
      final returnPct = Decimal.tryParse(
        _expectedReturnPctController.text.trim(),
      );
      final valuation = _valuationController.text.trim().isEmpty
          ? null
          : Decimal.tryParse(_valuationController.text.trim());
      if (principal == null ||
          returnPct == null ||
          (_valuationController.text.trim().isNotEmpty && valuation == null)) {
        AppMessenger.show(
          context,
          ToastKind.error,
          l10n.formAmountFieldInvalid,
        );
        return;
      }
      final repo = await ref.read(manualAssetRepositoryProvider.future);
      final expectedReturn = (returnPct / Decimal.fromInt(100)).toDecimal(
        scaleOnInfinitePrecision: 12,
      );
      if (_initial == null) {
        await repo.createWealthProduct(
          accountId: accountId,
          name: _nameController.text.trim(),
          currency: currency,
          principal: principal,
          expectedAnnualReturn: expectedReturn,
          startDate: _startDate,
          maturityDate: _maturityDate,
          issuer: _emptyToNull(_issuerController.text),
          productCode: _emptyToNull(_productCodeController.text),
          currentValuation: valuation,
        );
      } else {
        final newMeta = WealthProductMetadata(
          accountId: accountId,
          principal: principal,
          expectedAnnualReturn: expectedReturn,
          startDate: _startDate,
          maturityDate: _maturityDate,
          issuer: _emptyToNull(_issuerController.text),
          productCode: _emptyToNull(_productCodeController.text),
        );
        await repo.updateMetadata(id: _initial!.id, metadata: newMeta);
        if (valuation != null) {
          await repo.recordValuationAdjust(
            assetId: _initial!.id,
            newValuation: valuation,
          );
        }
        if (_nameController.text.trim() != (_initial!.name ?? '')) {
          await repo.updateBasics(
            id: _initial!.id,
            name: _nameController.text.trim(),
          );
        }
      }
      unawaited(
        ref
            .read(formDefaultsProvider.notifier)
            .rememberAsset(accountId: accountId, currency: currency),
      );
      if (!mounted) return;
      dirty.markPristine();
      Haptics.success();
      popOrGo(context, fallback: FinanceRoutes.wealth);
    } on Object {
      if (!mounted) return;
      Haptics.error();
      AppMessenger.show(context, ToastKind.error, l10n.commonSaveFailed);
    } finally {
      dirty.busy = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_initial == null) return;
    final l10n = AppLocalizations.of(context);
    final ok = await showConfirmDialog(
      context: context,
      title: Text(l10n.wealthProductDeleteTitle),
      body: Text(l10n.wealthProductDeleteBody),
      cancelLabel: l10n.commonCancel,
      confirmLabel: l10n.commonDelete,
      destructive: true,
    );
    if (ok != true) return;
    setState(() => _busy = true);
    dirty.busy = true;
    try {
      final repo = await ref.read(manualAssetRepositoryProvider.future);
      await repo.softDelete(_initial!.id);
      if (!mounted) return;
      dirty.markPristine();
      popOrGo(context, fallback: FinanceRoutes.wealth);
    } finally {
      dirty.busy = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _emptyToNull(String s) {
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _principalController.dispose();
    _expectedReturnPctController.dispose();
    _valuationController.dispose();
    _issuerController.dispose();
    _productCodeController.dispose();
    _nameFocus.dispose();
    _issuerFocus.dispose();
    _productCodeFocus.dispose();
    _principalFocus.dispose();
    _returnFocus.dispose();
    _valuationFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final accountsAsync = ref.watch(accountsStreamProvider);
    return guardedScope(
      child: AppFormPageScaffold(
        title: Text(
          widget.isEdit
              ? l10n.wealthProductEditTitle
              : l10n.wealthProductCreateTitle,
        ),
        confirmLeave: handleBackIntent,
        actions: [
          if (widget.isEdit)
            FHeaderAction(
              icon: const Icon(FLucideIcons.trash2),
              onPress: _busy ? null : _delete,
            ),
        ],
        child: accountsAsync.whenOrLoading(
          error: (e, _) => AppEmptyState.error(
            title: l10n.commonLoadFailed,
            message: l10n.commonLoadError('$e'),
            action: FButton(
              variant: FButtonVariant.ghost,
              onPress: () => ref.invalidate(accountsStreamProvider),
              child: Text(l10n.commonRetry),
            ),
          ),
          data: (accounts) => _buildForm(accounts),
        ),
      ),
    );
  }

  Widget _buildForm(List<Account> accounts) {
    final l10n = AppLocalizations.of(context);
    final eligible = accounts
        .where((a) => _eligibleAccountTypes.contains(a.type))
        .toList(growable: false);
    if (eligible.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.wealthProductNoAccountHint,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.s12),
              FButton(
                variant: FButtonVariant.outline,
                onPress: () => context.go(FinanceRoutes.wealthAccountNew),
                prefix: const Icon(FLucideIcons.plus, size: AppIconSizes.sm),
                child: Text(l10n.wealthProductCreateAccountAction),
              ),
            ],
          ),
        ),
      );
    }
    if (!_hydratedFromList && !widget.isEdit) {
      final hasCurrent =
          _accountId != null && eligible.any((a) => a.id == _accountId);
      if (!hasCurrent) {
        _accountId = eligible.first.id;
      }
      _hydratedFromList = true;
    }
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: AppFormScaffoldBody(
        action: SizedBox(
          width: double.infinity,
          child: FButton(
            variant: FButtonVariant.primary,
            onPress: _busy ? null : _save,
            child: Text(_busy ? l10n.formSaving : l10n.formSave),
          ),
        ),
        children: [
          // AI provenance for `propose_asset_valuation`.
          if (widget.isEdit && widget.assetId != null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: AiTouchMark(
                entityType: 'assets',
                entityId: widget.assetId!,
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
          ],
          AccountPicker(
            accounts: eligible,
            value: _accountId,
            onChanged: (v) => setState(() {
              _accountId = v;
              dirty.markDirty();
            }),
          ),
          const SizedBox(height: AppSpacing.s12),
          FTextFormField(
            control: FTextFieldControl.managed(controller: _nameController),
            label: Text(l10n.wealthProductNameLabel),
            focusNode: _nameFocus,
            textInputAction: TextInputAction.next,
            validator: (v) => (v == null || v.trim().isEmpty)
                ? l10n.wealthProductNameRequired
                : null,
            onSubmit: (_) => _issuerFocus.requestFocus(),
          ),
          const SizedBox(height: AppSpacing.s12),
          FTextFormField(
            control: FTextFieldControl.managed(controller: _issuerController),
            label: Text(l10n.wealthProductIssuerLabel),
            focusNode: _issuerFocus,
            textInputAction: TextInputAction.next,
            onSubmit: (_) => _productCodeFocus.requestFocus(),
          ),
          const SizedBox(height: AppSpacing.s12),
          FTextFormField(
            control: FTextFieldControl.managed(
              controller: _productCodeController,
            ),
            label: Text(l10n.wealthProductCodeLabel),
            focusNode: _productCodeFocus,
            textInputAction: TextInputAction.next,
            onSubmit: (_) => _principalFocus.requestFocus(),
          ),
          const SizedBox(height: AppSpacing.s12),
          CurrencyPicker(
            value: _currency,
            onChanged: (v) => setState(() {
              _currency = v;
              dirty.markDirty();
            }),
          ),
          const SizedBox(height: AppSpacing.s12),
          AmountField(
            label: l10n.wealthProductAmountLabel,
            controller: _principalController,
            currencyCode: _currency,
            focusNode: _principalFocus,
            onFieldSubmitted: (_) => _returnFocus.requestFocus(),
          ),
          const SizedBox(height: AppSpacing.s12),
          FTextFormField(
            control: FTextFieldControl.managed(
              controller: _expectedReturnPctController,
            ),
            label: Text(l10n.wealthProductExpectedReturnLabel),
            description: Text(l10n.wealthProductExpectedReturnHelper),
            focusNode: _returnFocus,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.next,
            validator: (v) {
              final trimmed = v?.trim() ?? '';
              if (trimmed.isEmpty) {
                return l10n.wealthProductExpectedReturnRequired;
              }
              final parsed = Decimal.tryParse(trimmed);
              if (parsed == null) return l10n.wealthProductInvalidFormat;
              return null;
            },
            onSubmit: (_) => _valuationFocus.requestFocus(),
          ),
          const SizedBox(height: AppSpacing.s12),
          DateField(
            label: l10n.wealthProductValueDateLabel,
            initialValue: _startDate,
            onChanged: (d) => setState(() {
              _startDate = d;
              dirty.markDirty();
            }),
          ),
          const SizedBox(height: AppSpacing.s12),
          DateField(
            label: l10n.wealthProductMaturityDateLabel,
            initialValue: _maturityDate,
            onChanged: (d) => setState(() {
              _maturityDate = d;
              dirty.markDirty();
            }),
          ),
          const SizedBox(height: AppSpacing.s12),
          AmountField(
            label: l10n.wealthProductValuationLabel,
            controller: _valuationController,
            currencyCode: _currency,
            required: false,
            helperText: l10n.wealthProductValuationHelper,
            focusNode: _valuationFocus,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _busy ? null : _save(),
          ),
        ],
      ),
    );
  }
}
