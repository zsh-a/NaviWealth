import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/domain/account.dart';
import '../../data/domain/asset.dart';
import '../../data/domain/enums.dart';
import '../../data/domain/manual_asset_metadata.dart';
import '../../data/repositories/manual_asset_repository.dart';
import '../../data/repositories/providers.dart';
import '../../design_system/design_system.dart';
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

  String? _accountId;
  String? _currency = 'CNY';
  bool _busy = false;
  Asset? _initial;

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
    if (widget.isEdit) _loadInitial();
  }

  Future<void> _loadInitial() async {
    final repo = await ref.read(manualAssetRepositoryProvider.future);
    final existing = await repo.findById(widget.assetId!);
    if (existing == null || !mounted) return;
    final meta = existing.manualMetadata;
    final accountId = meta is CashMetadata ? meta.accountId : null;
    setState(() {
      _initial = existing;
      _balanceController.text = existing.lastPrice?.toString() ?? '';
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
        await repo.createCash(
          accountId: _accountId!,
          currency: _currency!,
          balance: balance,
          nickname: _nicknameController.text.trim().isEmpty
              ? null
              : _nicknameController.text.trim(),
        );
      } else {
        await repo.updateValuation(id: _initial!.id, newValuation: balance);
        if (_nicknameController.text.trim() != (_initial!.name ?? '')) {
          await repo.updateBasics(
            id: _initial!.id,
            name: _nicknameController.text.trim(),
          );
        }
      }
      if (!mounted) return;
      context.go('/assets');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_initial == null) return;
    final ok = await _confirmDelete(context);
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final repo = await ref.read(manualAssetRepositoryProvider.future);
      await repo.softDelete(_initial!.id);
      if (!mounted) return;
      context.go('/assets');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _balanceController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsStreamProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEdit ? '编辑现金余额' : '录入现金余额'),
        actions: [
          if (widget.isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除',
              onPressed: _busy ? null : _delete,
            ),
        ],
      ),
      body: accountsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (accounts) => _buildForm(accounts),
      ),
    );
  }

  Widget _buildForm(List<Account> accounts) {
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
              const Text('请先创建一个银行 / 现金账户。', textAlign: TextAlign.center),
              const SizedBox(height: Spacing.s12),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.add),
                label: const Text('新建账户'),
                onPressed: () => context.go('/accounts/new'),
              ),
            ],
          ),
        ),
      );
    }
    return Form(
      key: _formKey,
      child: ListView(
        padding: Spacing.pageMobile,
        children: [
          AccountPicker(
            accounts: eligible,
            value: _accountId,
            onChanged: (v) => setState(() => _accountId = v),
          ),
          const SizedBox(height: Spacing.s12),
          CurrencyPicker(
            value: _currency,
            onChanged: (v) => setState(() => _currency = v),
          ),
          const SizedBox(height: Spacing.s12),
          AmountField(
            label: '余额',
            controller: _balanceController,
            currencyCode: _currency,
          ),
          const SizedBox(height: Spacing.s12),
          TextFormField(
            controller: _nicknameController,
            decoration: const InputDecoration(
              labelText: '备注名（可选）',
              border: OutlineInputBorder(),
              helperText: '例如：招行港币活期、零钱通',
            ),
          ),
          const SizedBox(height: Spacing.s24),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? '保存中…' : '保存'),
          ),
        ],
      ),
    );
  }
}

Future<bool?> _confirmDelete(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('删除资产'),
      content: const Text('确认删除该资产记录？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('取消'),
        ),
        FilledButton.tonal(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('删除'),
        ),
      ],
    ),
  );
}
