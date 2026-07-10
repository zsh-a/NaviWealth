import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_draft.dart';
import 'package:naviwealth/features/finance/shared/ui/forms/forms.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../data/rebalance_providers.dart';
import '../domain/rebalance_execution.dart';

Future<bool?> showRebalanceExecutionReviewSheet({
  required BuildContext context,
  required RebalanceExecutionItem item,
}) {
  final l10n = AppLocalizations.of(context);
  return showAppSheet<bool>(
    context: context,
    title: l10n.rebalanceExecutionEditorTitle,
    maxHeightFactor: 0.94,
    builder: (_) => _ReviewEditor(item: item),
  );
}

class _ReviewEditor extends ConsumerStatefulWidget {
  const _ReviewEditor({required this.item});

  final RebalanceExecutionItem item;

  @override
  ConsumerState<_ReviewEditor> createState() => _ReviewEditorState();
}

class _ReviewEditorState extends ConsumerState<_ReviewEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _quantity;
  late final TextEditingController _price;
  late final TextEditingController _fee;
  late final TextEditingController _tax;
  late final TextEditingController _note;
  String? _accountId;
  String? _cashAccountId;
  String? _assetId;
  late String _currency;
  late DateTime _tradeDate;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final request = widget.item.request;
    _accountId = request?.account.id;
    _cashAccountId = request?.cashAccount?.id;
    _assetId = request?.asset.id ?? widget.item.suggestion.assetId;
    _currency = request?.currency ?? widget.item.suggestion.amount.currency;
    _tradeDate = request?.tradeDate ?? _utcFromComponents(DateTime.now());
    _quantity = TextEditingController(text: request?.quantity.toString() ?? '');
    _price = TextEditingController(text: request?.price?.toString() ?? '');
    _fee = TextEditingController(text: request?.fee?.toString() ?? '0');
    _tax = TextEditingController(text: request?.tax?.toString() ?? '0');
    _note = TextEditingController(text: request?.note ?? '');
  }

  @override
  void dispose() {
    _quantity.dispose();
    _price.dispose();
    _fee.dispose();
    _tax.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final accountsAsync = ref.watch(rebalanceOwnedAccountsProvider);
    final assetsAsync = ref.watch(rebalanceOwnedSecuritiesProvider);
    if (accountsAsync.isLoading || assetsAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final dependencyError = accountsAsync.error ?? assetsAsync.error;
    if (dependencyError != null) {
      return AppEmptyState(
        icon: FLucideIcons.triangleAlert,
        title: dependencyError.toString(),
        action: FButton(
          variant: FButtonVariant.outline,
          onPress: () {
            ref
              ..invalidate(rebalanceOwnedAccountsProvider)
              ..invalidate(rebalanceOwnedSecuritiesProvider);
          },
          child: Text(l10n.commonRetry),
        ),
      );
    }
    final accounts = accountsAsync.value ?? const <Account>[];
    final assets = assetsAsync.value ?? const <Asset>[];
    final primaryAccounts = accounts
        .where(
          (account) =>
              account.category == AccountSide.asset &&
              const {
                AccountCategory.broker,
                AccountCategory.crypto,
              }.contains(account.type),
        )
        .toList(growable: false);
    final cashAccounts = accounts
        .where(
          (account) =>
              account.category == AccountSide.asset &&
              const {
                AccountCategory.cash,
                AccountCategory.bank,
                AccountCategory.broker,
                AccountCategory.crypto,
              }.contains(account.type) &&
              (const {
                    AccountCategory.broker,
                    AccountCategory.crypto,
                  }.contains(account.type) ||
                  account.currency.toUpperCase() == _currency.toUpperCase()),
        )
        .toList(growable: false);
    final compatibleAssets = assets
        .where(
          (asset) =>
              categoryForAssetType(asset.type) ==
              widget.item.suggestion.category,
        )
        .toList(growable: false);
    final lockedAssetId = widget.item.suggestion.assetId;
    final visibleAssets = lockedAssetId == null
        ? compatibleAssets
        : compatibleAssets
              .where((asset) => asset.id == lockedAssetId)
              .toList(growable: false);

    return PopScope(
      canPop: !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _busy) {
          AppMessenger.show(
            context,
            ToastKind.warning,
            l10n.rebalanceExecutionBusyLeaveBlocked,
          );
        }
      },
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AccountSelect(
              accounts: primaryAccounts,
              value: _accountId,
              label: l10n.formAccountPickerLabelDefault,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _accountId = value),
            ),
            const SizedBox(height: AppSpacing.s12),
            _AccountSelect(
              accounts: cashAccounts,
              value: _cashAccountId,
              label: l10n.rebalanceExecutionCashAccountLabel,
              optional: true,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _cashAccountId = value),
            ),
            const SizedBox(height: AppSpacing.s12),
            _AssetSelect(
              assets: visibleAssets,
              value: _assetId,
              enabled: !_busy && lockedAssetId == null,
              label: l10n.rebalanceExecutionAssetLabel,
              onChanged: (value) => setState(() => _assetId = value),
            ),
            const SizedBox(height: AppSpacing.s12),
            AmountField(
              label: l10n.tradeEntryQuantityLabel,
              controller: _quantity,
            ),
            const SizedBox(height: AppSpacing.s12),
            AmountField(
              label: l10n.tradeEntryPriceLabel,
              controller: _price,
              currencyCode: _currency,
              required: false,
            ),
            const SizedBox(height: AppSpacing.s12),
            DateField(
              label: l10n.tradeEntryDateLabel,
              initialValue: _tradeDate,
              required: true,
              includeTime: true,
              onChanged: _busy
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _tradeDate = _utcFromComponents(value));
                      }
                    },
            ),
            const SizedBox(height: AppSpacing.s12),
            CurrencyPicker(
              value: _currency,
              onChanged: (value) {
                if (_busy || value == null) return;
                final selectedCash = _findById(accounts, _cashAccountId);
                setState(() {
                  _currency = value;
                  if (selectedCash != null &&
                      const {
                        AccountCategory.cash,
                        AccountCategory.bank,
                      }.contains(selectedCash.type) &&
                      selectedCash.currency.toUpperCase() !=
                          value.toUpperCase()) {
                    _cashAccountId = null;
                  }
                });
              },
            ),
            const SizedBox(height: AppSpacing.s12),
            Row(
              children: [
                Expanded(
                  child: AmountField(
                    label: l10n.tradeEntryFeeLabel,
                    controller: _fee,
                    currencyCode: _currency,
                    required: false,
                  ),
                ),
                const SizedBox(width: AppSpacing.s12),
                Expanded(
                  child: AmountField(
                    label: l10n.tradeEntryTaxLabel,
                    controller: _tax,
                    currencyCode: _currency,
                    required: false,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s12),
            FTextField(
              control: FTextFieldControl.managed(controller: _note),
              label: Text(l10n.planBudgetNoteLabel),
              maxLines: 3,
            ),
            const SizedBox(height: AppSpacing.s16),
            FButton(
              onPress: _busy
                  ? null
                  : () => _save(accounts: accounts, assets: assets),
              child: Text(l10n.rebalanceExecutionSaveReviewAction),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save({
    required List<Account> accounts,
    required List<Asset> assets,
  }) async {
    if (!_formKey.currentState!.validate()) return;
    final account = _findById(accounts, _accountId);
    final cash = _cashAccountId == null
        ? null
        : _findById(accounts, _cashAccountId);
    final asset = _findById(assets, _assetId);
    final quantity = Decimal.tryParse(_quantity.text.trim());
    final price = _optionalDecimal(_price.text);
    final fee = _optionalDecimal(_fee.text);
    final tax = _optionalDecimal(_tax.text);
    if (account == null || asset == null || quantity == null) return;
    if (quantity <= Decimal.zero) {
      AppMessenger.show(
        context,
        ToastKind.error,
        AppLocalizations.of(context).formAmountFieldInvalid,
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final gateway = await ref.read(
        rebalanceExecutionWorkspaceGatewayProvider.future,
      );
      await gateway.saveReviewedRequest(
        expected: widget.item,
        request: RebalanceExecutionRequest(
          transactionId: widget.item.id,
          account: account,
          cashAccount: cash,
          asset: asset,
          type: widget.item.suggestion.isBuy ? TradeType.buy : TradeType.sell,
          quantity: quantity,
          price: price,
          currency: _currency,
          tradeDate: _tradeDate,
          fee: fee,
          tax: tax,
          note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      AppMessenger.show(context, ToastKind.error, error.toString());
      setState(() => _busy = false);
    }
  }
}

class _AccountSelect extends StatelessWidget {
  const _AccountSelect({
    required this.accounts,
    required this.value,
    required this.label,
    required this.onChanged,
    this.optional = false,
  });

  final List<Account> accounts;
  final String? value;
  final String label;
  final ValueChanged<String?>? onChanged;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    final labels = {for (final account in accounts) account.id: account.name};
    return FSelect<String>.rich(
      format: (id) => id.isEmpty ? '' : labels[id] ?? '',
      control: FSelectControl<String>.lifted(
        value: value ?? (optional ? '' : null),
        onChange: (id) => onChanged?.call(id == null || id.isEmpty ? null : id),
      ),
      label: Text(label),
      enabled: onChanged != null && accounts.isNotEmpty,
      validator: (id) => optional || id != null && id.isNotEmpty ? null : label,
      children: [
        if (optional) const FSelectItem<String>(value: '', title: Text('—')),
        for (final account in accounts)
          FSelectItem<String>(
            value: account.id,
            title: Text('${account.name} · ${account.currency}'),
          ),
      ],
    );
  }
}

class _AssetSelect extends StatelessWidget {
  const _AssetSelect({
    required this.assets,
    required this.value,
    required this.enabled,
    required this.label,
    required this.onChanged,
  });

  final List<Asset> assets;
  final String? value;
  final bool enabled;
  final String label;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final labels = {
      for (final asset in assets)
        asset.id: '${asset.symbol} · ${asset.market ?? ''}',
    };
    return FSelect<String>.rich(
      format: (id) => labels[id] ?? '',
      control: FSelectControl<String>.lifted(value: value, onChange: onChanged),
      label: Text(label),
      enabled: enabled && assets.isNotEmpty,
      validator: (id) => id == null || id.isEmpty ? label : null,
      children: [
        for (final asset in assets)
          FSelectItem<String>(value: asset.id, title: Text(labels[asset.id]!)),
      ],
    );
  }
}

T? _findById<T>(List<T> values, String? id) {
  for (final value in values) {
    final valueId = switch (value) {
      Account account => account.id,
      Asset asset => asset.id,
      _ => null,
    };
    if (valueId == id) return value;
  }
  return null;
}

Decimal? _optionalDecimal(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final parsed = Decimal.tryParse(trimmed);
  return parsed == Decimal.zero ? null : parsed;
}

DateTime _utcFromComponents(DateTime value) => DateTime.utc(
  value.year,
  value.month,
  value.day,
  value.hour,
  value.minute,
  value.second,
  value.millisecond,
  value.microsecond,
);
