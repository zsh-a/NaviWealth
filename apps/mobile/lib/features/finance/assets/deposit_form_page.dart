import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/ai/write/write.dart';
import 'package:naviwealth/core/haptics/haptics.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/data/repositories/manual_asset_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/manual_asset_metadata.dart';
import 'package:naviwealth/features/finance/shared/forms/forms.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

/// Create / edit form for term + demand bank deposits.
class DepositFormPage extends ConsumerStatefulWidget {
  const DepositFormPage({super.key, this.assetId});

  final String? assetId;

  bool get isEdit => assetId != null;

  @override
  ConsumerState<DepositFormPage> createState() => _DepositFormPageState();
}

class _DepositFormPageState extends ConsumerState<DepositFormPage>
    with FormDirtyGuard<DepositFormPage> {
  @override
  String get leaveFallback => FinanceRoutes.wealth;

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

  static const _eligibleAccountTypes = {
    AccountCategory.bank,
    AccountCategory.cash,
  };

  @override
  void initState() {
    super.initState();
    dirty.bindTextControllers([
      _nameController,
      _principalController,
      _ratePercentController,
      _valuationController,
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
    if (_kind == AssetType.bankDepositTerm && _maturityDate == null) {
      AppMessenger.show(context, ToastKind.error, l10n.depositMaturityRequired);
      return;
    }
    setState(() => _busy = true);
    dirty.busy = true;
    try {
      final principal = Decimal.tryParse(_principalController.text.trim());
      final ratePercent = Decimal.tryParse(_ratePercentController.text.trim());
      final valuation = _valuationController.text.trim().isEmpty
          ? null
          : Decimal.tryParse(_valuationController.text.trim());
      if (principal == null ||
          ratePercent == null ||
          (_valuationController.text.trim().isNotEmpty && valuation == null)) {
        AppMessenger.show(
          context,
          ToastKind.error,
          l10n.formAmountFieldInvalid,
        );
        return;
      }
      final repo = await ref.read(manualAssetRepositoryProvider.future);
      final rate = (ratePercent / Decimal.fromInt(100)).toDecimal(
        scaleOnInfinitePrecision: 12,
      );
      if (_initial == null) {
        await repo.createDeposit(
          accountId: accountId,
          type: _kind,
          name: _nameController.text.trim(),
          currency: currency,
          principal: principal,
          interestRate: rate,
          startDate: _startDate,
          maturityDate: _maturityDate,
          autoRenew: _autoRenew,
          currentValuation: valuation,
        );
      } else {
        final newMeta = DepositMetadata(
          accountId: accountId,
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
      title: Text(l10n.depositDeleteTitle),
      body: Text(l10n.depositDeleteBody),
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
    return guardedScope(
      child: AppFormPageScaffold(
        title: Text(
          widget.isEdit ? l10n.depositEditTitle : l10n.depositCreateTitle,
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
      return _PromptCreateAccount(
        onTap: () => context.go(FinanceRoutes.wealthAccountNew),
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
          // Surface AI provenance for assets touched by
          // `propose_asset_valuation`. Self-gating.
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
          SoftCard(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.s4),
              child: Row(
                children: [
                  Expanded(
                    child: _DepositKindChip(
                      icon: FLucideIcons.lock,
                      label: l10n.depositTypeTerm,
                      selected: _kind == AssetType.bankDepositTerm,
                      onTap: () {
                        Haptics.selection();
                        setState(() {
                          _kind = AssetType.bankDepositTerm;
                          dirty.markDirty();
                        });
                      },
                    ),
                  ),
                  Expanded(
                    child: _DepositKindChip(
                      icon: FLucideIcons.piggyBank,
                      label: l10n.depositTypeDemand,
                      selected: _kind == AssetType.bankDepositDemand,
                      onTap: () {
                        Haptics.selection();
                        setState(() {
                          _kind = AssetType.bankDepositDemand;
                          dirty.markDirty();
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
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
            label: Text(l10n.depositNameLabel),
            description: Text(l10n.depositNameHelper),
            focusNode: _nameFocus,
            textInputAction: TextInputAction.next,
            validator: (v) => (v == null || v.trim().isEmpty)
                ? l10n.depositNameRequired
                : null,
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
            label: l10n.depositPrincipalLabel,
            controller: _principalController,
            currencyCode: _currency,
            focusNode: _principalFocus,
            onFieldSubmitted: (_) => _rateFocus.requestFocus(),
          ),
          const SizedBox(height: AppSpacing.s12),
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
          const SizedBox(height: AppSpacing.s12),
          DateField(
            label: l10n.depositValueDateLabel,
            initialValue: _startDate,
            onChanged: (d) => setState(() {
              _startDate = d;
              dirty.markDirty();
            }),
          ),
          const SizedBox(height: AppSpacing.s12),
          DateField(
            label: l10n.depositMaturityDateLabel,
            initialValue: _maturityDate,
            required: _kind == AssetType.bankDepositTerm,
            onChanged: (d) => setState(() {
              _maturityDate = d;
              dirty.markDirty();
            }),
          ),
          const SizedBox(height: AppSpacing.s12),
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
          const SizedBox(height: AppSpacing.s12),
          if (_kind == AssetType.bankDepositTerm)
            FSwitch(
              label: Text(l10n.depositAutoRenewTitle),
              description: Text(l10n.depositAutoRenewSubtitle),
              value: _autoRenew,
              onChange: (v) => setState(() {
                _autoRenew = v;
                dirty.markDirty();
              }),
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
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.depositNoAccountHint, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.s12),
            FButton(
              variant: FButtonVariant.outline,
              onPress: onTap,
              prefix: const Icon(FLucideIcons.plus, size: AppIconSizes.sm),
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
    final colors = context.theme.colors;
    final stateColor = selected ? colors.primary : colors.mutedForeground;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s12,
          vertical: AppSpacing.s8,
        ),
        decoration: selected
            ? BoxDecoration(
                color: colors.primary.withValues(alpha: AppOpacity.medium),
                borderRadius: BorderRadius.circular(AppRadius.md),
              )
            : null,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: AppIconSizes.h18, color: stateColor),
            const SizedBox(width: AppSpacing.s4),
            Text(
              label,
              style: selected
                  ? context.labelStyle.copyWith(color: stateColor)
                  : context.mediumLabelStyle.copyWith(color: stateColor),
            ),
          ],
        ),
      ),
    );
  }
}
