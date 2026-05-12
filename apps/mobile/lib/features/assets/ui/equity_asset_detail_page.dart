import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../core/ai/write/write.dart';
import '../../../data/domain/asset.dart';
import '../../../data/market/market_data_providers.dart';
import '../../../data/repositories/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../domain/entities/symbol_info.dart';
import '../../../domain/values/asset_market.dart';
import '../../../l10n/gen/app_localizations.dart';
import 'asset_detail_sections.dart';

/// Detail view for equity-type assets. Watches the repository so a successful
/// metadata enrichment immediately reflects in the rendered card without a
/// full route round-trip.
class EquityAssetDetailPage extends ConsumerStatefulWidget {
  const EquityAssetDetailPage({super.key, required this.assetId});

  final String assetId;

  @override
  ConsumerState<EquityAssetDetailPage> createState() =>
      _EquityAssetDetailPageState();
}

class _EquityAssetDetailPageState extends ConsumerState<EquityAssetDetailPage> {
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
    final l10n = AppLocalizations.of(context);
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
        AppMessenger.show(
          context,
          ToastKind.error,
          l10n.assetDetailNoMetadataMatch,
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
      AppMessenger.show(
        context,
        ToastKind.success,
        filledName
            ? l10n.assetDetailMetadataSynced
            : l10n.assetDetailMetadataUpToDate,
      );
      setState(_reload);
    } catch (_) {
      if (!mounted) return;
      AppMessenger.show(
        context,
        ToastKind.error,
        l10n.assetDetailNetworkUnavailable,
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

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
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<Asset?>(
      future: _assetFuture,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const FScaffold(
            childPad: false,
            child: Material(
              color: Colors.transparent,
              child: Center(child: FCircularProgress()),
            ),
          );
        }
        final asset = snap.data;
        if (asset == null) {
          return FScaffold(
            childPad: false,
            child: Material(
              color: Colors.transparent,
              child: Center(child: Text(l10n.assetDetailNotFound)),
            ),
          );
        }
        return FScaffold(
          header: FHeader.nested(
            title: OptionalHero(
              tag: 'asset-${asset.id}-name',
              child: Text(asset.name ?? asset.symbol),
            ),
            suffixes: [
              FHeaderAction(
                icon: _syncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: FCircularProgress(),
                      )
                    : const Icon(Icons.cloud_sync_outlined),
                onPress: _syncing ? null : () => _syncMetadata(asset),
              ),
            ],
          ),
          childPad: false,
          child: Material(
            color: Colors.transparent,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Wave 40.1 — AI provenance hint for stock/etf/crypto
                // assets touched by `propose_asset_valuation`. Self-
                // gating; absent when no recent touch on this id.
                Align(
                  alignment: Alignment.centerLeft,
                  child: AiTouchMark(
                    entityType: 'assets',
                    entityId: asset.id,
                  ),
                ),
                const SizedBox(height: 8),
                AssetSummaryCard(asset: asset),
                const SizedBox(height: 12),
                AssetHoldingCard(asset: asset),
                const SizedBox(height: 12),
                AssetPnLCard(asset: asset),
                const SizedBox(height: 12),
                AssetTrendMiniChartCard(asset: asset),
                const SizedBox(height: 16),
                FButton(
                  variant: FButtonVariant.primary,
                  onPress: () =>
                      context.push(AppRoutes.tradeForAsset(asset.id)),
                  prefix: const Icon(Icons.add, size: 16),
                  child: Text(l10n.assetDetailNewTradeLabel),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
