import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/features/finance/data/domain/account.dart';
import 'package:naviwealth/features/finance/data/domain/asset.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/domain/manual_asset_metadata.dart';
import 'package:naviwealth/features/finance/data/repositories/manual_asset_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';

import '../../app/route_paths.dart';
import '../../core/ai/write/write.dart';
import '../../core/haptics/haptics.dart';
import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';
import '../shared/account_l10n.dart';
import '../shared/forms/forms.dart';

/// Create / edit form for a cash balance asset.
class CashFormPage extends ConsumerStatefulWidget {
  const CashFormPage({super.key, this.assetId});

  final String? assetId;

  bool get isEdit => assetId != null;

  @override
  ConsumerState<CashFormPage> createState() => _CashFormPageState();
}

class _CashFormPageState extends ConsumerState<CashFormPage>
    with FormDirtyGuard<CashFormPage> {
  @override
  String get leaveFallback => AppRoutes.wealth;

  final _formKey = GlobalKey<FormState>();
  final _balanceController = TextEditingController();
  final _nicknameController = TextEditingController();

  final _balanceFocus = FocusNode();
  final _nicknameFocus = FocusNode();

  String? _accountId;
  String? _currency = 'CNY';
  bool _busy = false;
  Asset? _initial;
  Asset? _selectedExistingCash;
  bool _hydratedFromList = false;
  int _cashLookupSeq = 0;

  static const _eligibleAccountTypes = {
    AccountCategory.bank,
    AccountCategory.cash,
    AccountCategory.broker,
    AccountCategory.crypto,
    AccountCategory.asset,
  };

  @override
  void initState() {
    super.initState();
    dirty.bindTextControllers([_balanceController, _nicknameController]);
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
    await _hydrateExistingCash(existing, locked: true);
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
      final repo = await ref.read(manualAssetRepositoryProvider.future);
      final balance = Decimal.parse(_balanceController.text.trim());
      var editing = _editingAsset;
      var createdNew = false;
      // Check for existing cash on the same account — each account can
      // have at most one cash asset (double-entry invariant).
      editing ??= await repo.findCashByAccountId(accountId);
      if (editing == null) {
        createdNew = true;
        await repo.createCash(
          accountId: accountId,
          currency: currency,
          balance: balance,
          nickname: _nicknameController.text.trim().isEmpty
              ? null
              : _nicknameController.text.trim(),
        );
      } else {
        await repo.recordValuationAdjust(
          assetId: editing.id,
          newValuation: balance,
        );
        if (_nicknameController.text.trim() != (editing.name ?? '')) {
          await repo.updateBasics(
            id: editing.id,
            name: _nicknameController.text.trim(),
          );
        }
      }
      if (createdNew) {
        unawaited(
          ref
              .read(formDefaultsProvider.notifier)
              .rememberAsset(accountId: accountId, currency: currency),
        );
      }
      if (!mounted) return;
      dirty.markPristine();
      Haptics.success();
      popOrGo(context, fallback: AppRoutes.wealth);
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
    final ok = await confirmManualAssetDelete(context);
    if (ok != true) return;
    setState(() => _busy = true);
    dirty.busy = true;
    try {
      final repo = await ref.read(manualAssetRepositoryProvider.future);
      await repo.softDelete(_initial!.id);
      if (!mounted) return;
      dirty.markPristine();
      popOrGo(context, fallback: AppRoutes.wealth);
    } finally {
      dirty.busy = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _balanceController.dispose();
    _nicknameController.dispose();
    _balanceFocus.dispose();
    _nicknameFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final accountsAsync = ref.watch(accountsStreamProvider);
    return guardedScope(
      child: AppFormPageScaffold(
        title: Text(
          _editingAsset == null
              ? l10n.cashFormCreateTitle
              : l10n.cashFormEditTitle,
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
          error: (e, _) => Center(child: Text(l10n.cashFormLoadError('$e'))),
          data: (accounts) => _buildForm(l10n, accounts),
        ),
      ),
    );
  }

  Widget _buildForm(AppLocalizations l10n, List<Account> accounts) {
    final eligible = accounts
        .where((a) => _eligibleAccountTypes.contains(a.type))
        .toList(growable: false);
    if (!widget.isEdit && eligible.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.cashFormNeedAccountHint, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.s12),
              FButton(
                variant: FButtonVariant.outline,
                onPress: () => context.go(AppRoutes.wealthAccountNew),
                prefix: const Icon(FLucideIcons.plus, size: AppIconSizes.sm),
                child: Text(l10n.cashFormCreateAccountAction),
              ),
            ],
          ),
        ),
      );
    }
    if (!_hydratedFromList && !widget.isEdit) {
      // Make sure the persisted last-used account is still around. If
      // the user archived/deleted it the persistence is stale; fall back
      // to the first eligible row instead of forcing the user to pick.
      // Keep the form currency locked to that effective account as well;
      // otherwise the picker can display one account while saving another
      // account/currency pairing.
      final current = _accountId == null
          ? null
          : eligible.where((a) => a.id == _accountId).firstOrNull;
      final effective = current ?? eligible.first;
      _accountId = effective.id;
      _currency = effective.currency;
      _hydratedFromList = true;
      _checkExistingCash(effective.id);
    }
    final linkedAccount = _accountId == null
        ? null
        : accounts.where((a) => a.id == _accountId).firstOrNull;
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: AppFormScaffoldBody(
        action: SizedBox(
          width: double.infinity,
          child: FButton(
            variant: FButtonVariant.primary,
            onPress: _busy ? null : () => unawaited(_save()),
            child: Text(_busy ? l10n.cashFormSaving : l10n.cashFormSave),
          ),
        ),
        children: [
          // AI provenance hint for assets touched by
          // `propose_asset_valuation`. Self-gating: hidden when no
          // recent touch on this asset id.
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
          _CashAccountField(
            isEdit: widget.isEdit,
            accounts: eligible,
            value: _accountId,
            lockedValue: _accountDisplayValue(l10n, linkedAccount),
            onChanged: (v) => _selectAccount(v, eligible),
          ),
          const SizedBox(height: AppSpacing.s12),
          AmountField(
            label: l10n.cashFormBalanceLabel,
            controller: _balanceController,
            currencyCode: _currency,
            focusNode: _balanceFocus,
            onFieldSubmitted: (_) => _nicknameFocus.requestFocus(),
          ),
          const SizedBox(height: AppSpacing.s12),
          FTextFormField(
            control: FTextFieldControl.managed(controller: _nicknameController),
            label: Text(l10n.cashFormNicknameLabel),
            description: Text(l10n.cashFormNicknameHelper),
            focusNode: _nicknameFocus,
            textInputAction: TextInputAction.done,
            onSubmit: (_) => _busy ? null : _save(),
          ),
        ],
      ),
    );
  }

  Asset? get _editingAsset => _initial ?? _selectedExistingCash;

  void _selectAccount(String? accountId, List<Account> eligible) {
    setState(() {
      _accountId = accountId;
      // Cash balance currency is the account currency. Keeping this derived
      // avoids creating a ledger row whose account and unit disagree.
      final account = eligible.where((a) => a.id == accountId).firstOrNull;
      if (account != null) _currency = account.currency;
      _selectedExistingCash = null;
      _balanceController.clear();
      _nicknameController.clear();
      dirty.markDirty();
    });
    _checkExistingCash(accountId);
  }

  String _accountDisplayValue(AppLocalizations l10n, Account? account) {
    if (account != null) {
      return '${localizedAccountName(l10n, account)} · ${account.currency}';
    }
    return _accountId?.isNotEmpty == true
        ? _accountId!
        : l10n.cashFormMissingAccount;
  }

  void _checkExistingCash(String? accountId) {
    if (widget.isEdit || accountId == null) return;
    final seq = ++_cashLookupSeq;
    scheduleMicrotask(() async {
      final repo = await ref.read(manualAssetRepositoryProvider.future);
      final existing = await repo.findCashByAccountId(accountId);
      if (!mounted || seq != _cashLookupSeq) return;
      if (existing == null) return;
      await _hydrateExistingCash(existing, locked: false);
    });
  }

  Future<void> _hydrateExistingCash(Asset asset, {required bool locked}) async {
    final repo = await ref.read(manualAssetRepositoryProvider.future);
    final meta = asset.manualMetadata;
    final accountId = meta is CashMetadata ? meta.accountId : null;
    final postingBalance = await repo.cashBalanceFromPostings(asset.id);
    final valuation = postingBalance ?? await repo.latestValuation(asset.id);
    if (!mounted) return;
    setState(() {
      if (locked) {
        _initial = asset;
      } else {
        _selectedExistingCash = asset;
      }
      _balanceController.text = (valuation ?? Decimal.zero).toString();
      _nicknameController.text = asset.name ?? '';
      _currency = asset.currency;
      _accountId = accountId;
    });
    dirty.snapshotBaseline();
  }
}

class _CashAccountField extends StatelessWidget {
  const _CashAccountField({
    required this.isEdit,
    required this.accounts,
    required this.value,
    required this.lockedValue,
    required this.onChanged,
  });

  final bool isEdit;
  final List<Account> accounts;
  final String? value;
  final String lockedValue;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (!isEdit) {
      return AccountPicker(
        accounts: accounts,
        value: value,
        onChanged: onChanged,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FormPickerRow(
          label: l10n.formAccountPickerLabelDefault,
          value: lockedValue,
          leading: const Icon(FLucideIcons.wallet, size: AppIconSizes.sm),
          trailing: const Icon(FLucideIcons.lock, size: AppIconSizes.sm),
        ),
        const SizedBox(height: AppSpacing.s6),
        Text(l10n.cashFormAccountLockedHint, style: context.captionStyle),
      ],
    );
  }
}

/// Shared confirmation dialog for soft-deleting a manually-tracked asset
/// (cash, deposit, wealth product). Returns `true` when the user confirms.
/// The strings live in ARB so every "delete asset" surface stays in sync.
Future<bool?> confirmManualAssetDelete(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showConfirmDialog(
    context: context,
    title: Text(l10n.manualAssetDeleteTitle),
    body: Text(l10n.manualAssetDeleteContent),
    cancelLabel: l10n.manualAssetDeleteCancel,
    confirmLabel: l10n.manualAssetDeleteConfirm,
    destructive: true,
  );
}
