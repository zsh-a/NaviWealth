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

/// Create / edit form for a cash balance asset.
class CashFormPage extends ConsumerStatefulWidget {
  const CashFormPage({super.key, this.assetId});

  final String? assetId;

  bool get isEdit => assetId != null;

  @override
  ConsumerState<CashFormPage> createState() => _CashFormPageState();
}

class _CashFormPageState extends ConsumerState<CashFormPage> {
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
    AccountType.bank,
    AccountType.cash,
    AccountType.brokerage,
    AccountType.cryptoWallet,
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
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final repo = await ref.read(manualAssetRepositoryProvider.future);
      final balance = Decimal.parse(_balanceController.text.trim());
      if (_initial == null) {
        // Check for existing cash on the same account — each account can
        // have at most one cash asset (double-entry invariant).
        final existing = await repo.findCashByAccountId(_accountId!);
        if (existing != null && mounted) {
          final l10n = AppLocalizations.of(context);
          final goEdit = await showGlassModalBottomSheet<bool>(
            context: context,
            builder: (ctx) => Padding(
              padding: const EdgeInsets.all(Spacing.s16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.cashFormDuplicateTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: Spacing.s8),
                  Text(l10n.cashFormDuplicateMessage),
                  const SizedBox(height: Spacing.s16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FButton(
                        variant: FButtonVariant.ghost,
                        onPress: () => Navigator.of(ctx).pop(false),
                        child: Text(l10n.cashFormDuplicateCancel),
                      ),
                      const SizedBox(width: Spacing.s8),
                      FButton(
                        variant: FButtonVariant.outline,
                        onPress: () => Navigator.of(ctx).pop(true),
                        child: Text(l10n.cashFormDuplicateEdit),
                      ),
                    ],
                  ),
                  SizedBox(height: MediaQuery.paddingOf(ctx).bottom),
                ],
              ),
            ),
          );
          if (goEdit == true && mounted) {
            context.go(AppRoutes.portfolioAsset(existing.id));
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
      Haptics.success();
      context.go(AppRoutes.portfolio);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_initial == null) return;
    final ok = await confirmManualAssetDelete(context);
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
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          widget.isEdit ? l10n.cashFormEditTitle : l10n.cashFormCreateTitle,
        ),
        actions: [
          if (widget.isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: l10n.cashFormDeleteTooltip,
              onPressed: _busy ? null : _delete,
            ),
        ],
      ),
      body: accountsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l10n.cashFormLoadError('$e'))),
        data: (accounts) => _buildForm(l10n, accounts),
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
          padding: Spacing.pageMobile,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.cashFormNeedAccountHint, textAlign: TextAlign.center),
              const SizedBox(height: Spacing.s12),
              FButton(
                variant: FButtonVariant.outline,
                onPress: () => context.go(AppRoutes.accountNew),
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
      child: ListView(
        padding: Spacing.pageMobile,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          AccountPicker(
            accounts: eligible,
            value: _accountId,
            onChanged: (v) => setState(() {
              _accountId = v;
              // Lock currency to the account's currency — double-entry
              // bookkeeping requires each account to hold a single currency.
              final account = eligible.where((a) => a.id == v).firstOrNull;
              if (account != null) _currency = account.currency;
            }),
          ),
          const SizedBox(height: Spacing.s12),
          CurrencyPicker(
            value: _currency,
            // Disabled — currency is derived from the selected account.
            onChanged: (_) {},
            enabled: false,
          ),
          const SizedBox(height: Spacing.s12),
          AmountField(
            label: l10n.cashFormBalanceLabel,
            controller: _balanceController,
            currencyCode: _currency,
            focusNode: _balanceFocus,
            onFieldSubmitted: (_) => _nicknameFocus.requestFocus(),
          ),
          const SizedBox(height: Spacing.s12),
          TextFormField(
            controller: _nicknameController,
            focusNode: _nicknameFocus,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _busy ? null : _save(),
            decoration: InputDecoration(
              labelText: l10n.cashFormNicknameLabel,
              border: const OutlineInputBorder(),
              helperText: l10n.cashFormNicknameHelper,
            ),
          ),
          const SizedBox(height: Spacing.s24),
          FButton(
            variant: FButtonVariant.primary,
            onPress: _busy ? null : _save,
            child: Text(_busy ? l10n.cashFormSaving : l10n.cashFormSave),
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
  return showGlassModalBottomSheet<bool>(
    context: context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(Spacing.s16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.manualAssetDeleteTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: Spacing.s8),
          Text(l10n.manualAssetDeleteContent),
          const SizedBox(height: Spacing.s16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FButton(
                variant: FButtonVariant.ghost,
                onPress: () => Navigator.of(ctx).pop(false),
                child: Text(l10n.manualAssetDeleteCancel),
              ),
              const SizedBox(width: Spacing.s8),
              FButton(
                variant: FButtonVariant.outline,
                onPress: () => Navigator.of(ctx).pop(true),
                child: Text(l10n.manualAssetDeleteConfirm),
              ),
            ],
          ),
          SizedBox(height: MediaQuery.paddingOf(ctx).bottom),
        ],
      ),
    ),
  );
}
