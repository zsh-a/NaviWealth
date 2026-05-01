import 'package:flutter/material.dart';

import '../../../data/domain/enums.dart';
import '../../../design_system/design_system.dart';
import '../../../domain/values/asset_market.dart';
import 'currency_picker.dart';
import 'local_securities_picker.dart';

/// Bottom sheet for hand-adding a security that's missing from the local
/// catalog. Returns a [LocalSecurityChoice] via `Navigator.pop` so the
/// caller can immediately use it without round-tripping through the
/// repository — actual `upsertSecurity` happens at trade-submit time.
///
/// Fully offline: every field is filled by the user, nothing is fetched.
class ManualSecuritySheet extends StatefulWidget {
  const ManualSecuritySheet({super.key, this.prefillSymbol});

  final String? prefillSymbol;

  @override
  State<ManualSecuritySheet> createState() => _ManualSecuritySheetState();
}

class _ManualSecuritySheetState extends State<ManualSecuritySheet> {
  final _formKey = GlobalKey<FormState>();
  final _symbolCtl = TextEditingController();
  final _nameCtl = TextEditingController();
  final _isinCtl = TextEditingController();

  AssetMarket _market = AssetMarket.usStock;
  AssetType _type = AssetType.stock;
  String _currency = 'USD';

  static const _supportedMarkets = <AssetMarket>[
    AssetMarket.cnA,
    AssetMarket.hkStock,
    AssetMarket.usStock,
    AssetMarket.crypto,
  ];

  static const _marketLabels = <AssetMarket, String>{
    AssetMarket.cnA: 'A 股',
    AssetMarket.hkStock: '港股',
    AssetMarket.usStock: '美股',
    AssetMarket.crypto: '加密',
  };

  static const _supportedTypes = <AssetType>[
    AssetType.stock,
    AssetType.etf,
    AssetType.mutualFund,
    AssetType.bond,
    AssetType.crypto,
  ];

  static const _typeLabels = <AssetType, String>{
    AssetType.stock: '股票',
    AssetType.etf: 'ETF',
    AssetType.mutualFund: '基金',
    AssetType.bond: '债券',
    AssetType.crypto: '加密货币',
  };

  @override
  void initState() {
    super.initState();
    final prefill = widget.prefillSymbol?.trim() ?? '';
    if (prefill.isNotEmpty) {
      _symbolCtl.text = prefill;
      _market = _inferMarket(prefill);
      _currency = _defaultCurrencyFor(_market);
      if (_market == AssetMarket.crypto) {
        _type = AssetType.crypto;
      }
    }
  }

  @override
  void dispose() {
    _symbolCtl.dispose();
    _nameCtl.dispose();
    _isinCtl.dispose();
    super.dispose();
  }

  AssetMarket _inferMarket(String symbol) {
    final inferred = inferAssetMarket(symbol);
    return _supportedMarkets.contains(inferred)
        ? inferred
        : AssetMarket.usStock;
  }

  String _defaultCurrencyFor(AssetMarket market) {
    switch (market) {
      case AssetMarket.cnA:
        return 'CNY';
      case AssetMarket.hkStock:
        return 'HKD';
      case AssetMarket.usStock:
        return 'USD';
      case AssetMarket.crypto:
        return 'USD';
      case AssetMarket.fx:
      case AssetMarket.unknown:
        return 'USD';
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final symbol = _symbolCtl.text.trim();
    final name = _nameCtl.text.trim();
    final isin = _isinCtl.text.trim();
    final choice = LocalSecurityChoice(
      symbol: symbol,
      market: _market,
      type: _type,
      currency: _currency,
      fromCatalog: false,
      name: name.isEmpty ? null : name,
      isin: isin.isEmpty ? null : isin,
    );
    Navigator.of(context).pop(choice);
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            Spacing.s16,
            Spacing.s16,
            Spacing.s16,
            Spacing.s24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '手动添加证券',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: Spacing.s4),
              Text(
                '本地保存，不会联网。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: Spacing.s16),
              TextFormField(
                key: const Key('manual-security-symbol'),
                controller: _symbolCtl,
                decoration: const InputDecoration(
                  labelText: '代码',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.characters,
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) return '请输入代码';
                  if (t.contains(':')) return '代码不能包含 “:”';
                  return null;
                },
              ),
              const SizedBox(height: Spacing.s12),
              TextFormField(
                key: const Key('manual-security-name'),
                controller: _nameCtl,
                decoration: const InputDecoration(
                  labelText: '名称（可选）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: Spacing.s12),
              DropdownButtonFormField<AssetMarket>(
                key: const Key('manual-security-market'),
                // ignore: deprecated_member_use
                value: _market,
                decoration: const InputDecoration(
                  labelText: '市场',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final m in _supportedMarkets)
                    DropdownMenuItem(
                      value: m,
                      child: Text(_marketLabels[m] ?? m.wire),
                    ),
                ],
                onChanged: (m) {
                  if (m == null) return;
                  setState(() {
                    _market = m;
                    _currency = _defaultCurrencyFor(m);
                    if (m == AssetMarket.crypto) {
                      _type = AssetType.crypto;
                    } else if (_type == AssetType.crypto) {
                      _type = AssetType.stock;
                    }
                  });
                },
              ),
              const SizedBox(height: Spacing.s12),
              DropdownButtonFormField<AssetType>(
                key: const Key('manual-security-type'),
                // ignore: deprecated_member_use
                value: _type,
                decoration: const InputDecoration(
                  labelText: '类型',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final t in _supportedTypes)
                    DropdownMenuItem(
                      value: t,
                      child: Text(_typeLabels[t] ?? t.name),
                    ),
                ],
                onChanged: (t) {
                  if (t == null) return;
                  setState(() => _type = t);
                },
              ),
              const SizedBox(height: Spacing.s12),
              CurrencyPicker(
                value: _currency,
                onChanged: (v) {
                  if (v != null) setState(() => _currency = v);
                },
              ),
              const SizedBox(height: Spacing.s12),
              TextFormField(
                key: const Key('manual-security-isin'),
                controller: _isinCtl,
                decoration: const InputDecoration(
                  labelText: 'ISIN（可选）',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: Spacing.s24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: Spacing.s12),
                  Expanded(
                    child: FilledButton(
                      key: const Key('manual-security-submit'),
                      onPressed: _submit,
                      child: const Text('添加'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
