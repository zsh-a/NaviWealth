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

  AssetType _kind = AssetType.bankDepositTerm;
  String? _accountId;
  String? _currency = 'CNY';
  DateTime? _startDate;
  DateTime? _maturityDate;
  bool _autoRenew = false;
  bool _busy = false;
  Asset? _initial;

  static const _eligibleAccountTypes = {AccountType.bank, AccountType.cash};

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
      _valuationController.text = existing.lastPrice?.toString() ?? '';
      _startDate = meta.startDate;
      _maturityDate = meta.maturityDate;
      _autoRenew = meta.autoRenew;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_kind == AssetType.bankDepositTerm && _maturityDate == null) {
      Haptics.error();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('定期存款必须填写到期日')));
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
          await repo.updateValuation(id: _initial!.id, newValuation: valuation);
        }
        if (_nameController.text.trim() != (_initial!.name ?? '')) {
          await repo.updateBasics(
            id: _initial!.id,
            name: _nameController.text.trim(),
          );
        }
      }
      if (!mounted) return;
      Haptics.success();
      context.go('/assets');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_initial == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除存款'),
        content: const Text('确认删除该存款记录？'),
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
    _nameController.dispose();
    _principalController.dispose();
    _ratePercentController.dispose();
    _valuationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsStreamProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEdit ? '编辑存款' : '录入存款'),
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
      return _PromptCreateAccount(onTap: () => context.go('/accounts/new'));
    }
    return Form(
      key: _formKey,
      child: ListView(
        padding: Spacing.pageMobile,
        children: [
          SegmentedButton<AssetType>(
            segments: const [
              ButtonSegment(
                value: AssetType.bankDepositTerm,
                icon: Icon(Icons.lock_clock),
                label: Text('定期'),
              ),
              ButtonSegment(
                value: AssetType.bankDepositDemand,
                icon: Icon(Icons.savings_outlined),
                label: Text('活期'),
              ),
            ],
            selected: {_kind},
            onSelectionChanged: (s) {
              Haptics.selection();
              setState(() => _kind = s.first);
            },
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
            decoration: const InputDecoration(
              labelText: '名称',
              helperText: '例如：招行 1 年期定期、工行活期储蓄',
              border: OutlineInputBorder(),
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? '请输入名称' : null,
          ),
          const SizedBox(height: Spacing.s12),
          CurrencyPicker(
            value: _currency,
            onChanged: (v) => setState(() => _currency = v),
          ),
          const SizedBox(height: Spacing.s12),
          AmountField(
            label: '本金',
            controller: _principalController,
            currencyCode: _currency,
          ),
          const SizedBox(height: Spacing.s12),
          TextFormField(
            controller: _ratePercentController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: '年化利率 (%)',
              border: OutlineInputBorder(),
              helperText: '例如：3.25 表示 3.25%',
            ),
            validator: (v) {
              final trimmed = v?.trim() ?? '';
              if (trimmed.isEmpty) return '请输入利率';
              final parsed = Decimal.tryParse(trimmed);
              if (parsed == null) return '利率格式不正确';
              if (parsed < Decimal.zero) return '利率不能为负';
              return null;
            },
          ),
          const SizedBox(height: Spacing.s12),
          DateField(
            label: '起息日',
            initialValue: _startDate,
            onChanged: (d) => setState(() => _startDate = d),
          ),
          const SizedBox(height: Spacing.s12),
          DateField(
            label: '到期日',
            initialValue: _maturityDate,
            required: _kind == AssetType.bankDepositTerm,
            onChanged: (d) => setState(() => _maturityDate = d),
          ),
          const SizedBox(height: Spacing.s12),
          AmountField(
            label: '当前估值（可选）',
            controller: _valuationController,
            currencyCode: _currency,
            required: false,
            helperText: '不填则使用本金作为当前估值',
          ),
          const SizedBox(height: Spacing.s12),
          if (_kind == AssetType.bankDepositTerm)
            SwitchListTile(
              title: const Text('自动续存'),
              subtitle: const Text('到期后系统提示重新登记，不会自动创建新存款'),
              value: _autoRenew,
              onChanged: (v) => setState(() => _autoRenew = v),
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

class _PromptCreateAccount extends StatelessWidget {
  const _PromptCreateAccount({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: Spacing.pageMobile,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('请先创建一个银行账户。', textAlign: TextAlign.center),
            const SizedBox(height: Spacing.s12),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.add),
              label: const Text('新建账户'),
              onPressed: onTap,
            ),
          ],
        ),
      ),
    );
  }
}
