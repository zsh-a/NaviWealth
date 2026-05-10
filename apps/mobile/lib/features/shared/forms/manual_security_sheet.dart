import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/haptics/haptics.dart';
import '../../../data/domain/enums.dart';
import '../../../data/market/market_data_providers.dart';
import '../../../design_system/design_system.dart';
import '../../../domain/entities/symbol_info.dart';
import '../../../domain/services/market_data_service.dart';
import '../../../domain/values/asset_market.dart';
import '../../../l10n/gen/app_localizations.dart';
import 'currency_picker.dart';
import 'local_securities_picker.dart';

/// Bottom sheet for hand-adding a security that's missing from the local
/// catalog. Returns a [LocalSecurityChoice] via `Navigator.pop` so the
/// caller can immediately use it without round-tripping through the
/// repository — actual `upsertSecurity` happens at trade-submit time.
///
/// Default flow is fully offline: every field is user-entered. FIR-78
/// surfaces a "从网络导入" affordance that calls
/// [MarketDataService.searchSymbol] for one-shot metadata import; that
/// path is best-effort, falls back to manual entry on any failure, and
/// never blocks the form from saving.
class ManualSecuritySheet extends ConsumerStatefulWidget {
  const ManualSecuritySheet({super.key, this.prefillSymbol});

  final String? prefillSymbol;

  @override
  ConsumerState<ManualSecuritySheet> createState() =>
      _ManualSecuritySheetState();
}

class _ManualSecuritySheetState extends ConsumerState<ManualSecuritySheet> {
  final _formKey = GlobalKey<FormState>();
  final _symbolCtl = TextEditingController();
  final _nameCtl = TextEditingController();
  final _isinCtl = TextEditingController();

  AssetMarket _market = AssetMarket.usStock;
  AssetType _type = AssetType.stock;
  String _currency = 'USD';
  bool _importing = false;

  static const _supportedMarkets = <AssetMarket>[
    AssetMarket.cnA,
    AssetMarket.hkStock,
    AssetMarket.usStock,
    AssetMarket.crypto,
  ];

  Map<AssetMarket, String> _marketLabels(AppLocalizations l10n) => {
    AssetMarket.cnA: l10n.manualSecurityMarketCnA,
    AssetMarket.hkStock: l10n.manualSecurityMarketHk,
    AssetMarket.usStock: l10n.manualSecurityMarketUs,
    AssetMarket.crypto: l10n.manualSecurityMarketCrypto,
  };

  static const _supportedTypes = <AssetType>[
    AssetType.stock,
    AssetType.etf,
    AssetType.mutualFund,
    AssetType.bond,
    AssetType.crypto,
  ];

  Map<AssetType, String> _typeLabels(AppLocalizations l10n) => {
    AssetType.stock: l10n.manualSecurityTypeStock,
    AssetType.etf: l10n.manualSecurityTypeEtf,
    AssetType.mutualFund: l10n.manualSecurityTypeMutualFund,
    AssetType.bond: l10n.manualSecurityTypeBond,
    AssetType.crypto: l10n.manualSecurityTypeCrypto,
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

  Future<void> _importFromNetwork() async {
    final l10n = AppLocalizations.of(context);
    final query = _symbolCtl.text.trim();
    if (query.isEmpty) {
      Haptics.error();
      AppMessenger.show(
        context,
        ToastKind.error,
        l10n.manualSecurityEnterCodeOrName,
      );
      return;
    }

    setState(() => _importing = true);
    final List<SymbolInfo> hits;
    try {
      final market = await ref.read(marketDataServiceProvider.future);
      // Pass the user's current market pick as a hint so the routing chain
      // can skip irrelevant providers (e.g. don't ask CoinGecko for a US
      // ticker). Falls back to the unrestricted chain when unknown.
      final response = await market.searchSymbol(
        query,
        market: _market == AssetMarket.unknown ? null : _market,
      );
      hits = response.data;
    } catch (_) {
      // The composite service throws NoMarketDataAvailableException when
      // every provider fails (offline or upstream outage); per FIR-78 we
      // collapse the whole failure surface to a single non-scary message
      // and let the user fall through to manual entry.
      if (!mounted) return;
      Haptics.error();
      AppMessenger.show(
        context,
        ToastKind.error,
        l10n.manualSecurityNetworkUnavailable,
      );
      setState(() => _importing = false);
      return;
    }

    if (!mounted) return;
    // Drop the spinner before opening the picker dialog. Otherwise the
    // CircularProgressIndicator keeps ticking while we're awaiting the
    // user's choice, which makes `pumpAndSettle` impossible in widget
    // tests and adds zero signal — the search has already returned.
    setState(() => _importing = false);

    if (hits.isEmpty) {
      Haptics.error();
      AppMessenger.show(context, ToastKind.error, l10n.manualSecurityNoMatch);
      return;
    }
    final picked = hits.length == 1
        ? hits.single
        : await _pickFromCandidates(hits);
    if (picked == null || !mounted) return;
    _applyImported(picked);
    AppMessenger.show(context, ToastKind.success, l10n.manualSecurityImported);
  }

  Future<SymbolInfo?> _pickFromCandidates(List<SymbolInfo> hits) {
    final l10n = AppLocalizations.of(context);
    return showDialog<SymbolInfo>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.manualSecuritySelectMatchTitle),
        children: [
          // Each row uses a self-contained `ListTile.onTap` rather than
          // wrapping in `SimpleDialogOption`. The ListTile's own gesture
          // detector swallows taps from its parent, which made the
          // `SimpleDialogOption` callback unreachable in widget tests.
          // Two listings can share a symbol (e.g. cross-listings), so the
          // key incorporates the exchange to stay unique in those cases.
          for (final hit in hits)
            ListTile(
              key: Key(
                'manual-security-import-candidate-${hit.symbol}-'
                '${hit.exchange ?? 'unknown'}',
              ),
              title: Text(
                hit.symbol,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                [hit.name, if (hit.exchange != null) hit.exchange!].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(hit.currency ?? '—'),
              onTap: () => Navigator.of(ctx).pop(hit),
            ),
        ],
      ),
    );
  }

  void _applyImported(SymbolInfo info) {
    setState(() {
      _symbolCtl.text = info.symbol;
      if (info.name.isNotEmpty) _nameCtl.text = info.name;
      // Only adopt the imported market if the picker actually offers it —
      // otherwise the dropdown's `value` would fall outside its `items`
      // and Flutter would assert in debug.
      if (_supportedMarkets.contains(info.market)) {
        _market = info.market;
        if (_market == AssetMarket.crypto) {
          _type = AssetType.crypto;
        } else if (_type == AssetType.crypto) {
          _type = AssetType.stock;
        }
      }
      if (info.currency != null && info.currency!.isNotEmpty) {
        _currency = info.currency!;
      } else {
        _currency = _defaultCurrencyFor(_market);
      }
    });
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
    Haptics.success();
    Navigator.of(context).pop(choice);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final marketLabels = _marketLabels(l10n);
    final typeLabels = _typeLabels(l10n);
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
                l10n.manualSecuritySheetTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: Spacing.s4),
              Text(
                l10n.manualSecuritySheetDescription,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: Spacing.s16),
              TextFormField(
                key: const Key('manual-security-symbol'),
                controller: _symbolCtl,
                decoration: InputDecoration(
                  labelText: l10n.manualSecurityCodeLabel,
                  border: const OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.characters,
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) return l10n.manualSecurityCodeRequired;
                  if (t.contains(':')) return l10n.manualSecurityCodeNoColon;
                  return null;
                },
              ),
              const SizedBox(height: Spacing.s8),
              Align(
                alignment: Alignment.centerLeft,
                child: FButton(
                  key: const Key('manual-security-import'),
                  variant: FButtonVariant.ghost,
                  onPress: _importing ? null : _importFromNetwork,
                  prefix: const Icon(Icons.cloud_download_outlined, size: 16),
                  child: Text(
                    _importing
                        ? l10n.manualSecurityImporting
                        : l10n.manualSecurityImportAction,
                  ),
                ),
              ),
              const SizedBox(height: Spacing.s12),
              TextFormField(
                key: const Key('manual-security-name'),
                controller: _nameCtl,
                decoration: InputDecoration(
                  labelText: l10n.manualSecurityNameLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: Spacing.s12),
              DropdownButtonFormField<AssetMarket>(
                isExpanded: true,
                key: const Key('manual-security-market'),
                initialValue: _market,
                decoration: InputDecoration(
                  labelText: l10n.manualSecurityMarketLabel,
                ),
                items: [
                  for (final m in _supportedMarkets)
                    DropdownMenuItem(
                      value: m,
                      child: Text(marketLabels[m] ?? m.wire),
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
                isExpanded: true,
                key: const Key('manual-security-type'),
                initialValue: _type,
                decoration: InputDecoration(
                  labelText: l10n.manualSecurityTypeLabel,
                ),
                items: [
                  for (final t in _supportedTypes)
                    DropdownMenuItem(
                      value: t,
                      child: Text(typeLabels[t] ?? t.name),
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
                decoration: InputDecoration(
                  labelText: l10n.manualSecurityIsinLabel,
                  border: const OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: Spacing.s24),
              Row(
                children: [
                  Expanded(
                    child: FButton(
                      variant: FButtonVariant.outline,
                      onPress: () => Navigator.of(context).pop(),
                      child: Text(l10n.commonCancel),
                    ),
                  ),
                  const SizedBox(width: Spacing.s12),
                  Expanded(
                    child: FButton(
                      key: const Key('manual-security-submit'),
                      variant: FButtonVariant.primary,
                      onPress: _submit,
                      child: Text(l10n.manualSecurityAddAction),
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
