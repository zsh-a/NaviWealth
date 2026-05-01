import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/domain/asset.dart';
import '../../data/domain/enums.dart';
import '../../data/market/market_data_providers.dart';
import '../../data/repositories/providers.dart';
import '../../domain/entities/symbol_info.dart';
import '../../domain/values/asset_market.dart';
import 'cash_form_page.dart';
import 'deposit_form_page.dart';
import 'wealth_product_form_page.dart';

/// Resolves an asset id to the type-specific edit form.
///
/// Centralising the dispatch keeps the route table flat — the router
/// doesn't need to know which sub-form belongs to which AssetType, and
/// adding new manual-valuation flavours later means changing only this
/// switch.
class AssetDetailPage extends ConsumerWidget {
  const AssetDetailPage({super.key, required this.assetId});

  final String assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repoAsync = ref.watch(manualAssetRepositoryProvider);
    return repoAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('加载失败：$e'))),
      data: (repo) {
        return FutureBuilder<Asset?>(
          future: repo.findById(assetId),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            final asset = snap.data;
            if (asset == null) {
              return const Scaffold(body: Center(child: Text('资产不存在或已删除')));
            }
            return switch (asset.type) {
              AssetType.cash => CashFormPage(assetId: asset.id),
              AssetType.bankDepositTerm ||
              AssetType.bankDepositDemand => DepositFormPage(assetId: asset.id),
              AssetType.wealthProduct => WealthProductFormPage(
                assetId: asset.id,
              ),
              AssetType.stock ||
              AssetType.etf ||
              AssetType.crypto ||
              AssetType.mutualFund =>
                _EquityAssetDetailPage(assetId: asset.id),
              _ => Scaffold(
                appBar: AppBar(title: Text(asset.name ?? asset.symbol)),
                body: const Center(child: Text('该资产类型暂不支持手动编辑')),
              ),
            };
          },
        );
      },
    );
  }
}

/// Detail view for equity-type assets with a "new trade" action and
/// FIR-78's "同步元数据" enrichment shortcut.
///
/// Watches the repository (rather than holding the [Asset] passed in)
/// so a successful enrichment immediately reflects in the rendered card
/// without a full route round-trip.
class _EquityAssetDetailPage extends ConsumerStatefulWidget {
  const _EquityAssetDetailPage({required this.assetId});

  final String assetId;

  @override
  ConsumerState<_EquityAssetDetailPage> createState() =>
      _EquityAssetDetailPageState();
}

class _EquityAssetDetailPageState
    extends ConsumerState<_EquityAssetDetailPage> {
  Future<Asset?>? _assetFuture;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final repoFuture = ref.read(securitiesAssetRepositoryProvider.future);
    _assetFuture = repoFuture.then((repo) => repo.findById(widget.assetId));
  }

  Future<void> _syncMetadata(Asset asset) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _syncing = true);
    try {
      final market = await ref.read(marketDataServiceProvider.future);
      final assetMarket = assetMarketFromWire(asset.market);
      final response = await market.searchSymbol(
        asset.symbol,
        market: (assetMarket == null || assetMarket == AssetMarket.unknown)
            ? null
            : assetMarket,
      );
      final SymbolInfo? best = _pickBest(response.data, asset);
      if (best == null) {
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(content: Text('未找到匹配的元数据')),
        );
        return;
      }

      final repo = await ref.read(securitiesAssetRepositoryProvider.future);
      final before = asset;
      await repo.enrichMetadata(
        id: asset.id,
        name: best.name.isEmpty ? null : best.name,
      );
      if (!mounted) return;

      final filledName = before.name == null && best.name.isNotEmpty;
      messenger.showSnackBar(
        SnackBar(
          content: Text(filledName ? '已补全元数据' : '元数据已是最新'),
        ),
      );
      setState(_reload);
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('网络不可用，无法同步元数据')),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  /// Pick the result whose `(market, symbol)` matches the asset (case
  /// insensitive on symbol). Falls back to a symbol-only match, then to
  /// the first hit. Anything weaker than that risks importing the wrong
  /// company under the same ticker (e.g. AAPL on ASX vs NASDAQ).
  SymbolInfo? _pickBest(List<SymbolInfo> hits, Asset asset) {
    if (hits.isEmpty) return null;
    final wantSymbol = asset.symbol.toUpperCase();
    final wantMarket = assetMarketFromWire(asset.market);
    for (final h in hits) {
      if (h.symbol.toUpperCase() == wantSymbol && h.market == wantMarket) {
        return h;
      }
    }
    for (final h in hits) {
      if (h.symbol.toUpperCase() == wantSymbol) return h;
    }
    return hits.first;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Asset?>(
      future: _assetFuture,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final asset = snap.data;
        if (asset == null) {
          return const Scaffold(body: Center(child: Text('资产不存在或已删除')));
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(asset.name ?? asset.symbol),
            actions: [
              IconButton(
                key: const Key('asset-detail-sync-metadata'),
                tooltip: '同步元数据',
                onPressed: _syncing ? null : () => _syncMetadata(asset),
                icon: _syncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_sync_outlined),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        asset.symbol,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (asset.name != null) ...[
                        const SizedBox(height: 4),
                        Text(asset.name!),
                      ],
                      const SizedBox(height: 8),
                      Text('市场：${asset.market ?? "未知"}'),
                      Text('币种：${asset.currency}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('新交易'),
                onPressed: () =>
                    context.push('/assets/trade?assetId=${asset.id}'),
              ),
            ],
          ),
        );
      },
    );
  }
}
