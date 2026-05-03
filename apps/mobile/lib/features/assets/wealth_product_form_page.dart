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
import '../shared/forms/forms.dart';

/// Create / edit form for 理财产品 (manual-valuation wealth products).
class WealthProductFormPage extends ConsumerStatefulWidget {
  const WealthProductFormPage({super.key, this.assetId});

  final String? assetId;

  bool get isEdit => assetId != null;

  @override
  ConsumerState<WealthProductFormPage> createState() =>
      _WealthProductFormPageState();
}

class _WealthProductFormPageState extends ConsumerState<WealthProductFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _principalController = TextEditingController();
  final _expectedReturnPctController = TextEditingController();
  final _valuationController = TextEditingController();
  final _issuerController = TextEditingController();
  final _productCodeController = TextEditingController();

  // Focus chain: name → issuer → productCode → principal → return → valuation.
  final _nameFocus = FocusNode();
  final _issuerFocus = FocusNode();
  final _productCodeFocus = FocusNode();
  final _principalFocus = FocusNode();
  final _returnFocus = FocusNode();
  final _valuationFocus = FocusNode();

  String? _accountId;
  String? _currency = 'CNY';
  DateTime? _startDate;
  DateTime? _maturityDate;
  bool _busy = false;
  Asset? _initial;
  bool _hydratedFromList = false;

  static const _eligibleAccountTypes = {
    AccountType.bank,
    AccountType.brokerage,
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
    if (meta is! WealthProductMetadata) return;
    setState(() {
      _initial = existing;
      _nameController.text = existing.name ?? '';
      _accountId = meta.accountId;
      _currency = existing.currency;
      _principalController.text = meta.principal.toString();
      _expectedReturnPctController.text =
          (meta.expectedAnnualReturn * Decimal.fromInt(100)).toString();
      _valuationController.text = '';
      _startDate = meta.startDate;
      _maturityDate = meta.maturityDate;
      _issuerController.text = meta.issuer ?? '';
      _productCodeController.text = meta.productCode ?? '';
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final repo = await ref.read(manualAssetRepositoryProvider.future);
      final principal = Decimal.parse(_principalController.text.trim());
      final returnPct = Decimal.parse(_expectedReturnPctController.text.trim());
      final expectedReturn = (returnPct / Decimal.fromInt(100)).toDecimal(
        scaleOnInfinitePrecision: 12,
      );
      final valuation = _valuationController.text.trim().isEmpty
          ? null
          : Decimal.parse(_valuationController.text.trim());
      if (_initial == null) {
        await repo.createWealthProduct(
          accountId: _accountId!,
          name: _nameController.text.trim(),
          currency: _currency!,
          principal: principal,
          expectedAnnualReturn: expectedReturn,
          startDate: _startDate,
          maturityDate: _maturityDate,
          issuer: _emptyToNull(_issuerController.text),
          productCode: _emptyToNull(_productCodeController.text),
          currentValuation: valuation,
        );
      } else {
        final newMeta = WealthProductMetadata(
          accountId: _accountId!,
          principal: principal,
          expectedAnnualReturn: expectedReturn,
          startDate: _startDate,
          maturityDate: _maturityDate,
          issuer: _emptyToNull(_issuerController.text),
          productCode: _emptyToNull(_productCodeController.text),
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除理财产品'),
        content: const Text('确认删除该理财产品记录？'),
        actions: [
          AppButton.tertiary(
            onPressed: () => Navigator.of(ctx).pop(false),
            label: '取消',
          ),
          AppButton.secondary(
            onPressed: () => Navigator.of(ctx).pop(true),
            label: '删除',
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
      context.go('/portfolio');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _emptyToNull(String s) {
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _principalController.dispose();
    _expectedReturnPctController.dispose();
    _valuationController.dispose();
    _issuerController.dispose();
    _productCodeController.dispose();
    _nameFocus.dispose();
    _issuerFocus.dispose();
    _productCodeFocus.dispose();
    _principalFocus.dispose();
    _returnFocus.dispose();
    _valuationFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsStreamProvider);
    return Scaffold(
      appBar: GlassAppBar(
        title: Text(widget.isEdit ? '编辑理财产品' : '录入理财产品'),
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
              const Text('请先创建银行 / 券商账户。', textAlign: TextAlign.center),
              const SizedBox(height: Spacing.s12),
              AppButton.secondary(
                icon: Icons.add,
                label: '新建账户',
                onPressed: () => context.go('/portfolio/accounts/new'),
              ),
            ],
          ),
        ),
      );
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
            onFieldSubmitted: (_) => _issuerFocus.requestFocus(),
            decoration: const InputDecoration(
              labelText: '产品名称',
              border: OutlineInputBorder(),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? '请输入产品名称' : null,
          ),
          const SizedBox(height: Spacing.s12),
          TextFormField(
            controller: _issuerController,
            focusNode: _issuerFocus,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => _productCodeFocus.requestFocus(),
            decoration: const InputDecoration(
              labelText: '发行机构（可选）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: Spacing.s12),
          TextFormField(
            controller: _productCodeController,
            focusNode: _productCodeFocus,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => _principalFocus.requestFocus(),
            decoration: const InputDecoration(
              labelText: '产品代码（可选）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: Spacing.s12),
          CurrencyPicker(
            value: _currency,
            onChanged: (v) => setState(() => _currency = v),
          ),
          const SizedBox(height: Spacing.s12),
          AmountField(
            label: '认购金额',
            controller: _principalController,
            currencyCode: _currency,
            focusNode: _principalFocus,
            onFieldSubmitted: (_) => _returnFocus.requestFocus(),
          ),
          const SizedBox(height: Spacing.s12),
          TextFormField(
            controller: _expectedReturnPctController,
            focusNode: _returnFocus,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => _valuationFocus.requestFocus(),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: '预期年化收益率 (%)',
              border: OutlineInputBorder(),
              helperText: '例如：4.5 表示 4.5%',
            ),
            validator: (v) {
              final trimmed = v?.trim() ?? '';
              if (trimmed.isEmpty) return '请输入预期年化';
              final parsed = Decimal.tryParse(trimmed);
              if (parsed == null) return '格式不正确';
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
            label: '到期日（可选）',
            initialValue: _maturityDate,
            onChanged: (d) => setState(() => _maturityDate = d),
          ),
          const SizedBox(height: Spacing.s12),
          AmountField(
            label: '当前估值（手动维护）',
            controller: _valuationController,
            currencyCode: _currency,
            required: false,
            helperText: '不填则以认购金额作为当前估值',
            focusNode: _valuationFocus,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _busy ? null : _save(),
          ),
          const SizedBox(height: Spacing.s24),
          AppButton.primary(
            onPressed: _busy ? null : _save,
            label: _busy ? '保存中…' : '保存',
          ),
        ],
      ),
    );
  }
}
