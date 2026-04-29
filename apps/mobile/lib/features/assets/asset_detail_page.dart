import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/domain/asset.dart';
import '../../data/domain/enums.dart';
import '../../data/repositories/providers.dart';
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
                _EquityAssetDetailPage(asset: asset),
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

/// Detail view for equity-type assets with a "new trade" action.
class _EquityAssetDetailPage extends StatelessWidget {
  const _EquityAssetDetailPage({required this.asset});

  final Asset asset;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(asset.name ?? asset.symbol),
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
  }
}
