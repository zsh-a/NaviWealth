import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/ai/write/write.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/data/repositories/manual_asset_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/manual_asset_metadata.dart';
import 'package:naviwealth/features/finance/shared/l10n/account_l10n.dart';
import 'package:naviwealth/features/finance/shared/ui/forms/forms.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

/// Create / edit form for a cash balance asset.
class CashFormPage extends ConsumerStatefulWidget {
  const CashFormPage({super.key, this.assetId});

  final String? assetId;

  bool get isEdit => assetId != null;

  @override
  ConsumerState<CashFormPage> createState() => _CashFormPageState();
}

class _CashFormPageState extends ConsumerState<CashFormPage>
    with FormSubmission<CashFormPage>, FormDirtyGuard<CashFormPage> {
  @override
  String get leaveFallback => FinanceRoutes.wealth;

  final _formKey = GlobalKey<FormState>();
  final _balanceController = TextEditingController();
  final _nicknameController = TextEditingController();

  final _balanceFocus = FocusNode();
  final _nicknameFocus = FocusNode();

  String? _accountId;
  String? _currency = 'CNY';
  bool _busy = false;
  bool _loadingInitial = false;
  bool _checkingExistingCash = false;
  Object? _loadError;
  Asset? _initial;
  Asset? _selectedExistingCash;
  bool _hydratedFromList = false;
  int _cashLookupSeq = 0;

  static const _eligibleAccountTypes = {
    AccountCategory.bank,
    AccountCategory.cash,
    AccountCategory.broker,
    AccountCategory.crypto,
  };

  @override
  void initState() {
    super.initState();
    dirty.bindTextControllers([_balanceController, _nicknameController]);
    if (widget.isEdit) {
      _loadingInitial = true;
      unawaited(_loadInitial());
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
    try {
      final repo = await ref.read(manualAssetRepositoryProvider.future);
      final existing = await repo.findById(widget.assetId!);
      if (existing == null) {
        throw StateError('cash asset not found');
      }
      if (!mounted) return;
      await _hydrateExistingCash(existing, locked: true);
      // Hydrating an existing record is not a user edit.
      dirty.snapshotBaseline();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loadingInitial = false;
      });
    }
  }

  Future<void> _save() async {
    if (_busy || _checkingExistingCash) return;
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
    final balance = Decimal.tryParse(_balanceController.text.trim());
    if (balance == null) {
      AppMessenger.show(context, ToastKind.error, l10n.formAmountFieldInvalid);
      return;
    }
    final nickname = _nicknameController.text.trim();
    final initial = _editingAsset;
    await submitFormAndLeave<void>(
      dirty: dirty,
      onBusyChanged: _setBusy,
      leaveFallback: FinanceRoutes.wealth,
      failureMessage: (_) => l10n.commonSaveFailed,
      successMessage: l10n.commonSaved,
      tag: 'cash-balance',
      commit: () async {
        final repo = await ref.read(manualAssetRepositoryProvider.future);
        var editing = initial;
        var createdNew = false;
        // Each account can have at most one cash asset. Re-resolve immediately
        // before committing so a concurrent create cannot duplicate it.
        editing ??= await repo.findCashByAccountId(accountId);
        if (editing == null) {
          createdNew = true;
          await repo.createCash(
            accountId: accountId,
            currency: currency,
            balance: balance,
            nickname: nickname.isEmpty ? null : nickname,
          );
        } else {
          await repo.recordValuationAdjust(
            assetId: editing.id,
            newValuation: balance,
          );
          if (nickname != (editing.name ?? '')) {
            await repo.updateBasics(id: editing.id, name: nickname);
          }
        }
        if (createdNew) {
          unawaited(
            ref
                .read(formDefaultsProvider.notifier)
                .rememberAsset(accountId: accountId, currency: currency),
          );
        }
      },
    );
  }

  Future<void> _delete() async {
    if (_initial == null) return;
    final l10n = AppLocalizations.of(context);
    final ok = await confirmManualAssetDelete(context);
    if (ok != true) return;
    final id = _initial!.id;
    await submitFormAndLeave<void>(
      dirty: dirty,
      onBusyChanged: _setBusy,
      leaveFallback: FinanceRoutes.wealth,
      failureMessage: (_) => l10n.commonDeleteFailed,
      successMessage: l10n.commonDeleted,
      tag: 'cash-balance-delete',
      commit: () async {
        final repo = await ref.read(manualAssetRepositoryProvider.future);
        await repo.softDelete(id);
      },
    );
  }

  void _setBusy(bool value) {
    if (mounted && _busy != value) setState(() => _busy = value);
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
            AppHeaderAction(
              semanticsLabel: l10n.cashFormDeleteTooltip,
              icon: const Icon(FLucideIcons.trash2),
              onPress: _busy ? null : _delete,
            ),
        ],
        child: _loadingInitial
            ? const Center(child: FCircularProgress())
            : _loadError != null
            ? AppEmptyState.error(
                title: l10n.commonLoadFailed,
                message: l10n.cashFormLoadError(
                  userSafeErrorMessage(context, _loadError!),
                ),
                retryLabel: l10n.commonRetry,
                onRetry: () {
                  setState(() {
                    _loadError = null;
                    _loadingInitial = true;
                  });
                  unawaited(_loadInitial());
                },
              )
            : accountsAsync.whenOrLoading(
                context: context,
                error: (e, _) => AppEmptyState.error(
                  title: l10n.commonLoadFailed,
                  message: l10n.cashFormLoadError(
                    userSafeErrorMessage(context, e),
                  ),
                  retryLabel: l10n.commonRetry,
                  onRetry: () => ref.invalidate(accountsStreamProvider),
                ),
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
                onPress: () => context.go(FinanceRoutes.wealthAccountNew),
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
    final onSubmit = _busy || _checkingExistingCash ? null : _save;
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: AppFormScaffoldBody(
        onSubmit: onSubmit,
        action: SizedBox(
          width: double.infinity,
          child: AppBusyButton(
            label: l10n.cashFormSave,
            busyLabel: l10n.cashFormSaving,
            busy: _busy,
            onPress: onSubmit == null ? null : () => unawaited(onSubmit()),
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
          if (_checkingExistingCash)
            _CashLookupStatus(message: l10n.cashFormCheckingExisting)
          else ...[
            if (!widget.isEdit && _selectedExistingCash != null) ...[
              const _ExistingCashNotice(),
              const SizedBox(height: AppSpacing.s12),
            ],
            AmountField(
              key: const Key('cash-balance-field'),
              label: l10n.cashFormBalanceLabel,
              controller: _balanceController,
              currencyCode: _currency,
              focusNode: _balanceFocus,
              onFieldSubmitted: (_) => _nicknameFocus.requestFocus(),
            ),
            const SizedBox(height: AppSpacing.s12),
            FTextFormField(
              key: const Key('cash-nickname-field'),
              control: FTextFieldControl.managed(
                controller: _nicknameController,
              ),
              label: Text(l10n.cashFormNicknameLabel),
              description: Text(l10n.cashFormNicknameHelper),
              focusNode: _nicknameFocus,
              textInputAction: TextInputAction.done,
              onSubmit: (_) => _busy ? null : _save(),
            ),
          ],
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
    if (widget.isEdit) return;
    final seq = ++_cashLookupSeq;
    if (accountId == null) {
      _checkingExistingCash = false;
      return;
    }
    _checkingExistingCash = true;
    scheduleMicrotask(() async {
      try {
        final repo = await ref.read(manualAssetRepositoryProvider.future);
        final existing = await repo.findCashByAccountId(accountId);
        if (!mounted || seq != _cashLookupSeq) return;
        if (existing == null) {
          setState(() => _checkingExistingCash = false);
          return;
        }
        await _hydrateExistingCash(existing, locked: false);
      } catch (error) {
        if (!mounted || seq != _cashLookupSeq) return;
        setState(() => _checkingExistingCash = false);
        AppMessenger.show(
          context,
          ToastKind.error,
          AppLocalizations.of(
            context,
          ).cashFormLoadError(userSafeErrorMessage(context, error)),
        );
      }
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
      _loadingInitial = false;
      _checkingExistingCash = false;
      _loadError = null;
    });
    dirty.snapshotBaseline();
  }
}

class _CashLookupStatus extends StatelessWidget {
  const _CashLookupStatus({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return SoftCard.flat(
      child: Row(
        children: [
          const SizedBox(
            width: AppIconSizes.h18,
            height: AppIconSizes.h18,
            child: FCircularProgress(),
          ),
          const SizedBox(width: AppSpacing.s10),
          Expanded(child: Text(message, style: context.captionStyle)),
        ],
      ),
    );
  }
}

class _ExistingCashNotice extends StatelessWidget {
  const _ExistingCashNotice();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    return SoftCard.flat(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            FLucideIcons.info,
            size: AppIconSizes.h18,
            color: colors.primary,
          ),
          const SizedBox(width: AppSpacing.s10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.cashFormExistingFoundTitle,
                  style: context.labelStyle,
                ),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  l10n.cashFormExistingFoundBody,
                  style: context.captionStyle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
