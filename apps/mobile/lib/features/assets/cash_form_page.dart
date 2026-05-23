import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../app/nav.dart';
import '../../app/route_paths.dart';
import '../../core/ai/write/write.dart';
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
  String get leaveFallback => AppRoutes.accounts;

  final _formKey = GlobalKey<FormState>();
  final _balanceController = TextEditingController();
  final _nicknameController = TextEditingController();

  final _balanceFocus = FocusNode();
  final _nicknameFocus = FocusNode();

  String? _accountId;
  String? _currency = 'CNY';
  bool _busy = false;
  Asset? _initial;
  bool _hydratedFromList = false;

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
    final meta = existing.manualMetadata;
    final accountId = meta is CashMetadata ? meta.accountId : null;
    final valuation = await repo.cashBalanceFromPostings(existing.id);
    if (!mounted) return;
    setState(() {
      _initial = existing;
      _balanceController.text = valuation?.toString() ?? '';
      _nicknameController.text = existing.name ?? '';
      _currency = existing.currency;
      _accountId = accountId;
    });
    // Hydrating an existing record is not a user edit.
    dirty.snapshotBaseline();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    dirty.busy = true;
    try {
      final repo = await ref.read(manualAssetRepositoryProvider.future);
      final balance = Decimal.parse(_balanceController.text.trim());
      if (_initial == null) {
        // Check for existing cash on the same account — each account can
        // have at most one cash asset (double-entry invariant).
        final existing = await repo.findCashByAccountId(_accountId!);
        if (existing != null && mounted) {
          final l10n = AppLocalizations.of(context);
          final goEdit = await showConfirmDialog(
            context: context,
            title: Text(l10n.cashFormDuplicateTitle),
            body: Text(l10n.cashFormDuplicateMessage),
            cancelLabel: l10n.cashFormDuplicateCancel,
            confirmLabel: l10n.cashFormDuplicateEdit,
          );
          if (goEdit == true && mounted) {
            context.go(AppRoutes.accountAsset(existing.id));
          }
          setState(() => _busy = false);
          return;
        }
        await repo.createCash(
          accountId: _accountId!,
          currency: _currency!,
          balance: balance,
          nickname: _nicknameController.text.trim().isEmpty
              ? null
              : _nicknameController.text.trim(),
        );
      } else {
        await repo.recordValuationAdjust(
          assetId: _initial!.id,
          newValuation: balance,
        );
        if (_nicknameController.text.trim() != (_initial!.name ?? '')) {
          await repo.updateBasics(
            id: _initial!.id,
            name: _nicknameController.text.trim(),
          );
        }
      }
      unawaited(
        ref
            .read(formDefaultsProvider.notifier)
            .rememberAsset(accountId: _accountId, currency: _currency),
      );
      if (!mounted) return;
      dirty.markPristine();
      Haptics.success();
      popOrGo(context, fallback: AppRoutes.accounts);
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
      popOrGo(context, fallback: AppRoutes.accounts);
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
      child: FScaffold(
        header: FHeader.nested(
          title: Text(
            widget.isEdit ? l10n.cashFormEditTitle : l10n.cashFormCreateTitle,
          ),
          prefixes: [backHeaderAction(context, confirmLeave: handleBackIntent)],
          suffixes: [
            if (widget.isEdit)
              FHeaderAction(
                icon: const Icon(Icons.delete_outline),
                onPress: _busy ? null : _delete,
              ),
          ],
        ),
        childPad: false,
        resizeToAvoidBottomInset: false,
        child: Material(
          color: Colors.transparent,
          child: accountsAsync.when(
            loading: () => const Center(child: FCircularProgress()),
            error: (e, _) => Center(child: Text(l10n.cashFormLoadError('$e'))),
            data: (accounts) => _buildForm(l10n, accounts),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(AppLocalizations l10n, List<Account> accounts) {
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
              Text(l10n.cashFormNeedAccountHint, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FButton(
                variant: FButtonVariant.outline,
                onPress: () => context.go(AppRoutes.accountListNew),
                prefix: const Icon(Icons.add, size: 16),
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
            child: Text(_busy ? l10n.cashFormSaving : l10n.cashFormSave),
          ),
        ),
        children: [
          // Wave 40 — AI provenance hint for assets touched by
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
            const SizedBox(height: 8),
          ],
          AccountPicker(
            accounts: eligible,
            value: _accountId,
            onChanged: (v) => setState(() {
              _accountId = v;
              // Lock currency to the account's currency — double-entry
              // bookkeeping requires each account to hold a single currency.
              final account = eligible.where((a) => a.id == v).firstOrNull;
              if (account != null) _currency = account.currency;
              dirty.markDirty();
            }),
          ),
          const SizedBox(height: 12),
          CurrencyPicker(
            value: _currency,
            // Disabled — currency is derived from the selected account.
            onChanged: (_) {},
            enabled: false,
          ),
          const SizedBox(height: 12),
          AmountField(
            label: l10n.cashFormBalanceLabel,
            controller: _balanceController,
            currencyCode: _currency,
            focusNode: _balanceFocus,
            onFieldSubmitted: (_) => _nicknameFocus.requestFocus(),
          ),
          const SizedBox(height: 12),
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
