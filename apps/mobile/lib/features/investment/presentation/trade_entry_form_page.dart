import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/domain/account.dart';
import '../../../data/domain/asset.dart';
import '../../../data/domain/enums.dart';
import '../../../data/domain/hlc.dart';
import '../../../data/domain/sync_meta.dart';
import '../../../data/market/market_data_providers.dart';
import '../../../data/repositories/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../domain/entities/symbol_info.dart';
import '../../../domain/values/asset_market.dart';
import '../../shared/forms/forms.dart';
import '../data/providers.dart';
import '../domain/models/lot.dart';
import '../domain/trade_entry/trade_draft.dart';
import '../domain/trade_entry/trade_entry_errors.dart';

/// Create / edit form for a security trade (stock / ETF / crypto).
///
/// The form collects a [TradeDraft], calls [TradeEntryService.buildPlan],
/// then persists via [TransactionRepository.recordTrade]. When [assetId] is
/// supplied the form pre-selects the asset and skips the search field (edit
/// mode is a future follow-up).
class TradeEntryFormPage extends ConsumerStatefulWidget {
  const TradeEntryFormPage({super.key, this.assetId, this.accountId});

  /// Pre-selected asset id. When null the user picks via [AssetSearchField].
  final String? assetId;

  /// Pre-selected account id.
  final String? accountId;

  @override
  ConsumerState<TradeEntryFormPage> createState() => _TradeEntryFormPageState();
}

class _TradeEntryFormPageState extends ConsumerState<TradeEntryFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _priceController = TextEditingController();
  final _feeController = TextEditingController(text: '0');
  final _taxController = TextEditingController(text: '0');
  final _noteController = TextEditingController();

  TransactionType _type = TransactionType.buy;
  String? _accountId;
  String? _currency = 'CNY';
  DateTime _tradeDate = DateTime.now();
  SymbolInfo? _selectedSymbol;
  bool _busy = false;

  static const _tradeTypes = [
    TransactionType.buy,
    TransactionType.sell,
    TransactionType.transferIn,
    TransactionType.transferOut,
    TransactionType.valuationAdjust,
  ];

  static const _typeLabels = {
    TransactionType.buy: '买入',
    TransactionType.sell: '卖出',
    TransactionType.transferIn: '转入',
    TransactionType.transferOut: '转出',
    TransactionType.valuationAdjust: '估值调整',
  };

  @override
  void initState() {
    super.initState();
    _accountId = widget.accountId;
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _priceController.dispose();
    _feeController.dispose();
    _taxController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  AssetType _inferAssetType(SymbolInfo info) {
    final tag = info.assetType?.toUpperCase() ?? '';
    if (tag.contains('ETF')) return AssetType.etf;
    if (tag.contains('CRYPTO')) return AssetType.crypto;
    if (info.market == AssetMarket.crypto) return AssetType.crypto;
    return AssetType.stock;
  }

  int _decimalScale(AssetType type) {
    switch (type) {
      case AssetType.crypto:
        return 18;
      case AssetType.stock:
      case AssetType.etf:
      case AssetType.mutualFund:
        return 8;
      default:
        return 8;
    }
  }

  String? _marketTag(SymbolInfo info) {
    switch (info.market) {
      case AssetMarket.cnA:
        return 'cn';
      case AssetMarket.hkStock:
        return 'hk';
      case AssetMarket.usStock:
        return 'us';
      default:
        return null;
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final symbol = _selectedSymbol;
    if (symbol == null) return;

    setState(() => _busy = true);
    try {
      final assetType = _inferAssetType(symbol);
      final asset = Asset(
        id: symbol.symbol,
        type: assetType,
        symbol: symbol.symbol,
        currency: symbol.currency ?? _currency!,
        name: symbol.name,
        market: _marketTag(symbol),
        sync: SyncMeta(
          ownerUserId: 'local-user',
          updatedAt: DateTime.now().toUtc(),
          updatedByDevice: '',
          hlc: const Hlc(wallMillis: 0, counter: 0, nodeId: ''),
        ),
      );

      final draft = TradeDraft(
        type: _type,
        asset: asset,
        accountId: _accountId!,
        quantity: Decimal.parse(_quantityController.text.trim()),
        price: _priceController.text.trim().isEmpty
            ? null
            : Decimal.parse(_priceController.text.trim()),
        currency: _currency!,
        tradeDate: _tradeDate,
        fee: Decimal.tryParse(_feeController.text.trim()),
        tax: Decimal.tryParse(_taxController.text.trim()),
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      );

      final tradeService = await ref.read(tradeEntryServiceProvider.future);
      final plan = await tradeService.buildPlan(draft, openLots: <Lot>[]);

      final repo = await ref.read(transactionRepositoryProvider.future);
      await repo.recordTrade(plan);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('交易录入成功')),
      );
      context.pop();
    } on TradeEntryException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('录入失败：${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('录入失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('录入交易'),
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
        .where((a) =>
            a.type == AccountType.brokerage ||
            a.type == AccountType.cryptoWallet)
        .toList(growable: false);

    return Form(
      key: _formKey,
      child: ListView(
        padding: Spacing.pageMobile,
        children: [
          // Asset search
          _buildAssetSearch(),
          const SizedBox(height: Spacing.s12),

          // Transaction type selector
          _buildTypeSelector(),
          const SizedBox(height: Spacing.s12),

          // Account picker
          AccountPicker(
            accounts: eligible.isEmpty ? accounts : eligible,
            value: _accountId,
            onChanged: (v) => setState(() => _accountId = v),
          ),
          const SizedBox(height: Spacing.s12),

          // Quantity
          AmountField(
            label: '数量',
            controller: _quantityController,
            helperText: _decimalScaleHint(),
          ),
          const SizedBox(height: Spacing.s12),

          // Price (optional — service backfills from market)
          AmountField(
            label: '价格',
            controller: _priceController,
            currencyCode: _currency,
            required: false,
            helperText: '留空则自动从市场数据获取',
          ),
          const SizedBox(height: Spacing.s12),

          // Trade date
          DateField(
            label: '交易日期',
            initialValue: _tradeDate,
            required: true,
            onChanged: (d) {
              if (d != null) setState(() => _tradeDate = d);
            },
          ),
          const SizedBox(height: Spacing.s12),

          // Currency
          CurrencyPicker(
            value: _currency,
            onChanged: (v) => setState(() => _currency = v),
          ),
          const SizedBox(height: Spacing.s12),

          // Fee & Tax row
          Row(
            children: [
              Expanded(
                child: AmountField(
                  label: '手续费',
                  controller: _feeController,
                  currencyCode: _currency,
                  required: false,
                ),
              ),
              const SizedBox(width: Spacing.s12),
              Expanded(
                child: AmountField(
                  label: '税费',
                  controller: _taxController,
                  currencyCode: _currency,
                  required: false,
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.s12),

          // Note
          NoteField(controller: _noteController),
          const SizedBox(height: Spacing.s24),

          // Submit
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? '保存中…' : '保存'),
          ),
        ],
      ),
    );
  }

  Widget _buildAssetSearch() {
    return FutureBuilder(
      future: ref.read(marketDataServiceProvider.future),
      builder: (ctx, snapshot) {
        if (!snapshot.hasData) {
          return const LinearProgressIndicator();
        }
        return AssetSearchField(
          marketData: snapshot.data!,
          onSelected: (info) {
            setState(() {
              _selectedSymbol = info;
              if (info?.currency != null) {
                _currency = info!.currency;
              }
            });
          },
        );
      },
    );
  }

  Widget _buildTypeSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final t in _tradeTypes)
          ChoiceChip(
            label: Text(_typeLabels[t]!),
            selected: _type == t,
            onSelected: (s) {
              if (s) setState(() => _type = t);
            },
          ),
      ],
    );
  }

  String _decimalScaleHint() {
    if (_selectedSymbol == null) return '股票/ETF 最多 8 位小数，加密最多 18 位';
    final type = _inferAssetType(_selectedSymbol!);
    final scale = _decimalScale(type);
    return '最多 $scale 位小数';
  }
}
