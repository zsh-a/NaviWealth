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
import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';
import '../shared/forms/forms.dart';

/// Create / edit form for term + demand bank deposits.
class DepositFormPage extends ConsumerStatefulWidget {
  const DepositFormPage({super.key, this.assetId});

  final String? assetId;

  bool get isEdit => assetId != null;

  @override
  ConsumerState<DepositFormPage> createState() => _DepositFormPageState();
}

class _DepositFormPageState extends ConsumerState<DepositFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _principalController = TextEditingController();
  final _ratePercentController = TextEditingController();
  final _valuationController = TextEditingController();

  // Focus chain: name → principal → rate → valuation. Pickers and date
  // taps interrupt the chain naturally — we don't try to push focus
  // through them.
  final _nameFocus = FocusNode();
  final _principalFocus = FocusNode();
  final _rateFocus = FocusNode();
  final _valuationFocus = FocusNode();

  AssetType _kind = AssetType.bankDepositTerm;
  String? _accountId;
  String? _currency = 'CNY';
  DateTime? _startDate;
  DateTime? _maturityDate;
  bool _autoRenew = false;
  bool _busy = false;
  Asset? _initial;
  bool _hydratedFromList = false;

  static const _eligibleAccountTypes = {AccountCategory.bank, AccountCategory.cash};

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
    if (meta is! DepositMetadata) return;
    setState(() {
      _initial = existing;
      _kind = existing.type;
      _nameController.text = existing.name ?? '';
      _accountId = meta.accountId;
      _currency = existing.currency;
      _principalController.text = meta.principal.toString();
      _ratePercentController.text = (meta.interestRate * Decimal.fromInt(100))
          .toString();
      _valuationController.text = '';
      _startDate = meta.startDate;
      _maturityDate = meta.maturityDate;
      _autoRenew = meta.autoRenew;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_kind == AssetType.bankDepositTerm && _maturityDate == null) {
      Haptics.error();
      AppMessenger.show(
        context,
        ToastKind.error,
        AppLocalizations.of(context).depositMaturityRequired,
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final repo = await ref.read(manualAssetRepositoryProvider.future);
      final principal = Decimal.parse(_principalController.text.trim());
      final ratePercent = Decimal.parse(_ratePercentController.text.trim());
      final rate = (ratePercent / Decimal.fromInt(100)).toDecimal(
        scaleOnInfinitePrecision: 12,
      );
      final valuation = _valuationController.text.trim().isEmpty
          ? null
          : Decimal.parse(_valuationController.text.trim());
      if (_initial == null) {
        await repo.createDeposit(
          accountId: _accountId!,
          type: _kind,
          name: _nameController.text.trim(),
          currency: _currency!,
          principal: principal,
          interestRate: rate,
          startDate: _startDate,
          maturityDate: _maturityDate,
          autoRenew: _autoRenew,
          currentValuation: valuation,
        );
      } else {
        final newMeta = DepositMetadata(
          accountId: _accountId!,
          principal: principal,
          interestRate: rate,
          startDate: _startDate,
          maturityDate: _maturityDate,
          autoRenew: _autoRenew,
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
      context.go(AppRoutes.accounts);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_initial == null) return;
    final l10n = AppLocalizations.of(context);
    final ok = await showFSheet<bool>(
      side: FLayout.btt,
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.depositDeleteTitle,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(l10n.depositDeleteBody),
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
      context.go(AppRoutes.accounts);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _principalController.dispose();
    _ratePercentController.dispose();
    _valuationController.dispose();
    _nameFocus.dispose();
    _principalFocus.dispose();
    _rateFocus.dispose();
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
          widget.isEdit ? l10n.depositEditTitle : l10n.depositCreateTitle,
        ),
        prefixes: [backHeaderAction(context)],
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
      return _PromptCreateAccount(
        onTap: () => context.go(AppRoutes.accountListNew),
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
          FCard.raw(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  Expanded(
                    child: _DepositKindChip(
                      icon: Icons.lock_clock,
                      label: l10n.depositTypeTerm,
                      selected: _kind == AssetType.bankDepositTerm,
                      onTap: () {
                        Haptics.selection();
                        setState(() => _kind = AssetType.bankDepositTerm);
                      },
                    ),
                  ),
                  Expanded(
                    child: _DepositKindChip(
                      icon: Icons.savings_outlined,
                      label: l10n.depositTypeDemand,
                      selected: _kind == AssetType.bankDepositDemand,
                      onTap: () {
                        Haptics.selection();
                        setState(() => _kind = AssetType.bankDepositDemand);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          AccountPicker(
            accounts: eligible,
            value: _accountId,
            onChanged: (v) => setState(() => _accountId = v),
          ),
          const SizedBox(height: 12),
          FTextFormField(
            control: FTextFieldControl.managed(controller: _nameController),
            label: Text(l10n.depositNameLabel),
            description: Text(l10n.depositNameHelper),
            focusNode: _nameFocus,
            textInputAction: TextInputAction.next,
            validator: (v) => (v == null || v.trim().isEmpty)
                ? l10n.depositNameRequired
                : null,
            onSubmit: (_) => _principalFocus.requestFocus(),
          ),
          const SizedBox(height: 12),
          CurrencyPicker(
            value: _currency,
            onChanged: (v) => setState(() => _currency = v),
          ),
          const SizedBox(height: 12),
          AmountField(
            label: l10n.depositPrincipalLabel,
            controller: _principalController,
            currencyCode: _currency,
            focusNode: _principalFocus,
            onFieldSubmitted: (_) => _rateFocus.requestFocus(),
          ),
          const SizedBox(height: 12),
          FTextFormField(
            control: FTextFieldControl.managed(
              controller: _ratePercentController,
            ),
            label: Text(l10n.depositRateLabel),
            description: Text(l10n.depositRateHelper),
            focusNode: _rateFocus,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.next,
            validator: (v) {
              final trimmed = v?.trim() ?? '';
              if (trimmed.isEmpty) return l10n.depositRateRequired;
              final parsed = Decimal.tryParse(trimmed);
              if (parsed == null) return l10n.depositRateInvalid;
              if (parsed < Decimal.zero) return l10n.depositRateNegative;
              return null;
            },
            onSubmit: (_) => _valuationFocus.requestFocus(),
          ),
          const SizedBox(height: 12),
          DateField(
            label: l10n.depositValueDateLabel,
            initialValue: _startDate,
            onChanged: (d) => setState(() => _startDate = d),
          ),
          const SizedBox(height: 12),
          DateField(
            label: l10n.depositMaturityDateLabel,
            initialValue: _maturityDate,
            required: _kind == AssetType.bankDepositTerm,
            onChanged: (d) => setState(() => _maturityDate = d),
          ),
          const SizedBox(height: 12),
          AmountField(
            label: l10n.depositCurrentValuationLabel,
            controller: _valuationController,
            currencyCode: _currency,
            required: false,
            helperText: l10n.depositCurrentValuationHelper,
            focusNode: _valuationFocus,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _busy ? null : _save(),
          ),
          const SizedBox(height: 12),
          if (_kind == AssetType.bankDepositTerm)
            FSwitch(
              label: Text(l10n.depositAutoRenewTitle),
              description: Text(l10n.depositAutoRenewSubtitle),
              value: _autoRenew,
              onChange: (v) => setState(() => _autoRenew = v),
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

class _PromptCreateAccount extends StatelessWidget {
  const _PromptCreateAccount({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.depositNoAccountHint, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FButton(
              variant: FButtonVariant.outline,
              onPress: onTap,
              prefix: const Icon(Icons.add, size: 16),
              child: Text(l10n.depositCreateAccountAction),
            ),
          ],
        ),
      ),
    );
  }
}

class _DepositKindChip extends StatelessWidget {
  const _DepositKindChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: selected
            ? BoxDecoration(
                color: context.theme.colors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              )
            : null,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected
                  ? context.theme.colors.primary
                  : context.theme.colors.mutedForeground,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: context.theme.typography.sm.copyWith(
                color: selected
                    ? context.theme.colors.primary
                    : context.theme.colors.mutedForeground,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
