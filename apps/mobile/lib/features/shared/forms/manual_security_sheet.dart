import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';

import '../../../core/haptics/haptics.dart';
import '../../../design_system/design_system.dart';
import '../../../domain/entities/symbol_info.dart';
import '../../../domain/services/market_data_service.dart';
import '../../../domain/values/asset_market.dart';
import '../../../features/finance/data/market/market_data_providers.dart';
import '../../../l10n/gen/app_localizations.dart';
import 'currency_picker.dart';
import 'symbol_field.dart';

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
  const ManualSecuritySheet({
    super.key,
    required this.dirty,
    this.prefillSymbol,
  });

  final FormDirtyController dirty;
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
    // Bind after the prefill so a passed-in symbol is the baseline.
    widget.dirty.bindTextControllers([_symbolCtl, _nameCtl, _isinCtl]);
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
    return showFDialog<SymbolInfo>(
      context: context,
      builder: (ctx, style, animation) => FDialog.raw(
        builder: (innerCtx, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.manualSecuritySelectMatchTitle,
                style: innerCtx.theme.typography.lg.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              for (final hit in hits)
                FTile(
                  key: Key(
                    'manual-security-import-candidate-${hit.symbol}-'
                    '${hit.exchange ?? 'unknown'}',
                  ),
                  title: Text(
                    hit.symbol,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    [
                      hit.name,
                      if (hit.exchange != null) hit.exchange!,
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  suffix: Text(hit.currency ?? '—'),
                  onPress: () => Navigator.of(ctx).pop(hit),
                ),
            ],
          ),
        ),
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
    widget.dirty.markPristine();
    Haptics.success();
    Navigator.of(context).pop(choice);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final marketLabels = _marketLabels(l10n);
    final typeLabels = _typeLabels(l10n);
    return AppSheet(
      title: l10n.manualSecuritySheetTitle,
      subtitle: l10n.manualSecuritySheetDescription,
      footer: AppSheetFooter(
        cancelLabel: l10n.commonCancel,
        submitLabel: l10n.manualSecurityAddAction,
        submitKey: const Key('manual-security-submit'),
        onSubmit: _submit,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FTextFormField(
              key: const Key('manual-security-symbol'),
              control: FTextFieldControl.managed(controller: _symbolCtl),
              label: Text(l10n.manualSecurityCodeLabel),
              textCapitalization: TextCapitalization.characters,
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.isEmpty) return l10n.manualSecurityCodeRequired;
                if (t.contains(':')) return l10n.manualSecurityCodeNoColon;
                return null;
              },
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FButton(
                key: const Key('manual-security-import'),
                variant: FButtonVariant.ghost,
                onPress: _importing ? null : _importFromNetwork,
                prefix: const Icon(FLucideIcons.cloudDownload, size: 16),
                child: Text(
                  _importing
                      ? l10n.manualSecurityImporting
                      : l10n.manualSecurityImportAction,
                ),
              ),
            ),
            const SizedBox(height: 12),
            FTextFormField(
              key: const Key('manual-security-name'),
              control: FTextFieldControl.managed(controller: _nameCtl),
              label: Text(l10n.manualSecurityNameLabel),
            ),
            const SizedBox(height: 12),
            FSelect<AssetMarket>(
              key: const Key('manual-security-market'),
              items: {
                for (final m in _supportedMarkets)
                  (marketLabels[m] ?? m.wire): m,
              },
              control: FSelectControl<AssetMarket>.managed(
                initial: _market,
                onChange: (m) {
                  if (m == null) return;
                  setState(() {
                    _market = m;
                    _currency = _defaultCurrencyFor(m);
                    if (m == AssetMarket.crypto) {
                      _type = AssetType.crypto;
                    } else if (_type == AssetType.crypto) {
                      _type = AssetType.stock;
                    }
                    widget.dirty.markDirty();
                  });
                },
              ),
              label: Text(l10n.manualSecurityMarketLabel),
            ),
            const SizedBox(height: 12),
            FSelect<AssetType>(
              key: const Key('manual-security-type'),
              items: {
                for (final t in _supportedTypes) (typeLabels[t] ?? t.name): t,
              },
              control: FSelectControl<AssetType>.managed(
                initial: _type,
                onChange: (t) {
                  if (t == null) return;
                  setState(() {
                    _type = t;
                    widget.dirty.markDirty();
                  });
                },
              ),
              label: Text(l10n.manualSecurityTypeLabel),
            ),
            const SizedBox(height: 12),
            CurrencyPicker(
              value: _currency,
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    _currency = v;
                    widget.dirty.markDirty();
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            FTextFormField(
              key: const Key('manual-security-isin'),
              control: FTextFieldControl.managed(controller: _isinCtl),
              label: Text(l10n.manualSecurityIsinLabel),
              textCapitalization: TextCapitalization.characters,
            ),
          ],
        ),
      ),
    );
  }
}
