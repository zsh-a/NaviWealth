import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../app/route_paths.dart';
import '../../core/haptics/haptics.dart';
import '../../data/domain/account.dart';
import '../../data/domain/asset.dart';
import '../../data/domain/enums.dart';
import '../../data/domain/manual_asset_metadata.dart';
import '../../data/repositories/manual_asset_repository.dart';
import '../../data/repositories/providers.dart';
import '../../l10n/gen/app_localizations.dart';
import '../shared/forms/forms.dart';

/// Create / edit form for 理财产品 (manual-valuation wealth products).
class WealthProductFormPage extends ConsumerStatefulWidget {
  const WealthProductFormPage({super.key, this.assetId});

  final String? assetId;

  bool get isEdit => assetId != null;

  @override
  ConsumerState<WealthProductFormPage> createState() =>
      _WealthProductFormPageState();
}

class _WealthProductFormPageState extends ConsumerState<WealthProductFormPage> {
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
    AccountType.bank,
    AccountType.brokerage,
    AccountType.other,
  };

  @override
  void initState() {
    super.initState();
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
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final repo = await ref.read(manualAssetRepositoryProvider.future);
      final principal = Decimal.parse(_principalController.text.trim());
      final returnPct = Decimal.parse(_expectedReturnPctController.text.trim());
      final expectedReturn = (returnPct / Decimal.fromInt(100)).toDecimal(
        scaleOnInfinitePrecision: 12,
      );
      final valuation = _valuationController.text.trim().isEmpty
          ? null
          : Decimal.parse(_valuationController.text.trim());
      if (_initial == null) {
        await repo.createWealthProduct(
          accountId: _accountId!,
          name: _nameController.text.trim(),
          currency: _currency!,
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
          accountId: _accountId!,
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
            .rememberAsset(accountId: _accountId, currency: _currency),
      );
      if (!mounted) return;
      Haptics.success();
      context.go(AppRoutes.portfolio);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_initial == null) return;
    final l10n = AppLocalizations.of(context);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.wealthProductDeleteTitle,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(l10n.wealthProductDeleteBody),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FButton(
                  variant: FButtonVariant.ghost,
                  onPress: () => Navigator.of(ctx).pop(false),
                  child: Text(l10n.commonCancel),
                ),
                const SizedBox(width: 8),
                FButton(
                  variant: FButtonVariant.outline,
                  onPress: () => Navigator.of(ctx).pop(true),
                  child: Text(l10n.commonDelete),
                ),
              ],
            ),
            SizedBox(height: MediaQuery.paddingOf(ctx).bottom),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final repo = await ref.read(manualAssetRepositoryProvider.future);
      await repo.softDelete(_initial!.id);
      if (!mounted) return;
      context.go(AppRoutes.portfolio);
    } finally {
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
    return FScaffold(
      header: FHeader.nested(
        title: Text(
          widget.isEdit
              ? l10n.wealthProductEditTitle
              : l10n.wealthProductCreateTitle,
        ),
        suffixes: [
          if (widget.isEdit)
            FHeaderAction(
              icon: const Icon(Icons.delete_outline),
              onPress: _busy ? null : _delete,
            ),
        ],
      ),
      childPad: false,
      child: Material(
        color: Colors.transparent,
        child: accountsAsync.when(
          loading: () => const Center(child: FCircularProgress()),
          error: (e, _) => Center(child: Text(l10n.commonLoadError('$e'))),
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
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.wealthProductNoAccountHint,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FButton(
                variant: FButtonVariant.outline,
                onPress: () => context.go(AppRoutes.accountNew),
                prefix: const Icon(Icons.add, size: 16),
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
      child: ListView(
        padding: const EdgeInsets.all(16),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          AccountPicker(
            accounts: eligible,
            value: _accountId,
            onChanged: (v) => setState(() => _accountId = v),
          ),
          const SizedBox(height: 12),
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
          const SizedBox(height: 12),
          FTextFormField(
            control: FTextFieldControl.managed(controller: _issuerController),
            label: Text(l10n.wealthProductIssuerLabel),
            focusNode: _issuerFocus,
            textInputAction: TextInputAction.next,
            onSubmit: (_) => _productCodeFocus.requestFocus(),
          ),
          const SizedBox(height: 12),
          FTextFormField(
            control: FTextFieldControl.managed(
              controller: _productCodeController,
            ),
            label: Text(l10n.wealthProductCodeLabel),
            focusNode: _productCodeFocus,
            textInputAction: TextInputAction.next,
            onSubmit: (_) => _principalFocus.requestFocus(),
          ),
          const SizedBox(height: 12),
          CurrencyPicker(
            value: _currency,
            onChanged: (v) => setState(() => _currency = v),
          ),
          const SizedBox(height: 12),
          AmountField(
            label: l10n.wealthProductAmountLabel,
            controller: _principalController,
            currencyCode: _currency,
            focusNode: _principalFocus,
            onFieldSubmitted: (_) => _returnFocus.requestFocus(),
          ),
          const SizedBox(height: 12),
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
          const SizedBox(height: 12),
          DateField(
            label: l10n.wealthProductValueDateLabel,
            initialValue: _startDate,
            onChanged: (d) => setState(() => _startDate = d),
          ),
          const SizedBox(height: 12),
          DateField(
            label: l10n.wealthProductMaturityDateLabel,
            initialValue: _maturityDate,
            onChanged: (d) => setState(() => _maturityDate = d),
          ),
          const SizedBox(height: 12),
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
          const SizedBox(height: 24),
          FButton(
            variant: FButtonVariant.primary,
            onPress: _busy ? null : _save,
            child: Text(_busy ? l10n.formSaving : l10n.formSave),
          ),
        ],
      ),
    );
  }
}
