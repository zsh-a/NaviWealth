import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

  static const _eligibleAccountTypes = {AccountType.bank, AccountType.cash};

  @override
  void initState() {
    super.initState();
    if (widget.isEdit) {
      _loadInitial();
    } else {
      final defaults = ref.read(formDefaultsProvider);
      _accountId = defaults.assetAccountId;
      if (defaults.assetCurrency != null && defaults.assetCurrency!.isNotEmpty) {
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
      AppMessenger.show(context, ToastKind.error, AppLocalizations.of(context).depositMaturityRequired);
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
      unawaited(ref.read(formDefaultsProvider.notifier).rememberAsset(
            accountId: _accountId,
            currency: _currency,
          ));
      if (!mounted) return;
      Haptics.success();
      context.go('/portfolio');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_initial == null) return;
    final l10n = AppLocalizations.of(context);
    final ok = await showGlassModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(Spacing.s16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.depositDeleteTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: Spacing.s8),
            Text(l10n.depositDeleteBody),
            const SizedBox(height: Spacing.s16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppButton.tertiary(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  label: l10n.commonCancel,
                ),
                const SizedBox(width: Spacing.s8),
                AppButton.secondary(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  label: l10n.commonDelete,
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
      context.go('/portfolio');
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
    return Scaffold(
      appBar: GlassAppBar(
        title: Text(widget.isEdit ? l10n.depositEditTitle : l10n.depositCreateTitle),
        actions: [
          if (widget.isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: l10n.depositDeleteTooltip,
              onPressed: _busy ? null : _delete,
            ),
        ],
      ),
      body: accountsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l10n.commonLoadError('$e'))),
        data: (accounts) => _buildForm(accounts),
      ),
    );
  }

  Widget _buildForm(List<Account> accounts) {
    final l10n = AppLocalizations.of(context);
    final eligible = accounts
        .where((a) => _eligibleAccountTypes.contains(a.type))
        .toList(growable: false);
    if (eligible.isEmpty) {
      return _PromptCreateAccount(onTap: () => context.go('/activity/accounts/new'));
    }
    if (!_hydratedFromList && !widget.isEdit) {
      final hasCurrent = _accountId != null &&
          eligible.any((a) => a.id == _accountId);
      if (!hasCurrent) {
        _accountId = eligible.first.id;
      }
      _hydratedFromList = true;
    }
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: ListView(
        padding: Spacing.pageMobile,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          LiquidGlassCard(
            layer: GlassLayer.tertiary,
            borderRadius: Radii.lg.toDouble(),
            padding: const EdgeInsets.all(Spacing.s4),
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
          const SizedBox(height: Spacing.s12),
          AccountPicker(
            accounts: eligible,
            value: _accountId,
            onChanged: (v) => setState(() => _accountId = v),
          ),
          const SizedBox(height: Spacing.s12),
          TextFormField(
            controller: _nameController,
            focusNode: _nameFocus,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => _principalFocus.requestFocus(),
            decoration: InputDecoration(
              labelText: l10n.depositNameLabel,
              helperText: l10n.depositNameHelper,
              border: const OutlineInputBorder(),
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? l10n.depositNameRequired : null,
          ),
          const SizedBox(height: Spacing.s12),
          CurrencyPicker(
            value: _currency,
            onChanged: (v) => setState(() => _currency = v),
          ),
          const SizedBox(height: Spacing.s12),
          AmountField(
            label: l10n.depositPrincipalLabel,
            controller: _principalController,
            currencyCode: _currency,
            focusNode: _principalFocus,
            onFieldSubmitted: (_) => _rateFocus.requestFocus(),
          ),
          const SizedBox(height: Spacing.s12),
          TextFormField(
            controller: _ratePercentController,
            focusNode: _rateFocus,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => _valuationFocus.requestFocus(),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: l10n.depositRateLabel,
              border: const OutlineInputBorder(),
              helperText: l10n.depositRateHelper,
            ),
            validator: (v) {
              final trimmed = v?.trim() ?? '';
              if (trimmed.isEmpty) return l10n.depositRateRequired;
              final parsed = Decimal.tryParse(trimmed);
              if (parsed == null) return l10n.depositRateInvalid;
              if (parsed < Decimal.zero) return l10n.depositRateNegative;
              return null;
            },
          ),
          const SizedBox(height: Spacing.s12),
          DateField(
            label: l10n.depositValueDateLabel,
            initialValue: _startDate,
            onChanged: (d) => setState(() => _startDate = d),
          ),
          const SizedBox(height: Spacing.s12),
          DateField(
            label: l10n.depositMaturityDateLabel,
            initialValue: _maturityDate,
            required: _kind == AssetType.bankDepositTerm,
            onChanged: (d) => setState(() => _maturityDate = d),
          ),
          const SizedBox(height: Spacing.s12),
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
          const SizedBox(height: Spacing.s12),
          if (_kind == AssetType.bankDepositTerm)
            SwitchListTile(
              title: Text(l10n.depositAutoRenewTitle),
              subtitle: Text(l10n.depositAutoRenewSubtitle),
              value: _autoRenew,
              onChanged: (v) => setState(() => _autoRenew = v),
            ),
          const SizedBox(height: Spacing.s24),
          AppButton.primary(
            onPressed: _busy ? null : _save,
            label: _busy ? l10n.formSaving : l10n.formSave,
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
        padding: Spacing.pageMobile,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.depositNoAccountHint, textAlign: TextAlign.center),
            const SizedBox(height: Spacing.s12),
            AppButton.secondary(
              icon: Icons.add,
              label: l10n.depositCreateAccountAction,
              onPressed: onTap,
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
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.s12,
          vertical: Spacing.s8,
        ),
        decoration: selected
            ? BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(Radii.md),
              )
            : null,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: Spacing.s4),
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
