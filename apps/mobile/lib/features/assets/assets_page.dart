import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/domain/asset.dart';
import '../../data/domain/enums.dart';
import '../../data/domain/manual_asset_metadata.dart';
import '../../data/repositories/manual_asset_repository.dart';
import '../../data/repositories/providers.dart';
import '../../design_system/design_system.dart';

/// Tab body for `/assets`. Shows the manual-valuation asset book
/// (cash, deposits, wealth products) grouped by type, with a FAB that
/// opens a bottom sheet to choose which kind of asset to add.
///
/// Securities / crypto holdings will be appended once their feature ticket
/// lands; this page intentionally only knows about manual-valuation rows
/// so the two surfaces can evolve independently.
class AssetsPage extends ConsumerWidget {
  const AssetsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assetsAsync = ref.watch(manualAssetsStreamProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('资产'),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_balance_outlined),
            tooltip: '账户管理',
            onPressed: () => context.go('/accounts'),
          ),
        ],
      ),
      body: assetsAsync.when(
        data: (assets) =>
            assets.isEmpty ? const _EmptyHint() : _AssetsByType(assets: assets),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('录入资产'),
      ),
    );
  }

  void _showAddSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: const Text('现金 / 多币种余额'),
              subtitle: const Text('登记银行活期或现金账户中的可用余额'),
              onTap: () {
                Navigator.of(ctx).pop();
                context.go('/assets/new/cash');
              },
            ),
            ListTile(
              leading: const Icon(Icons.savings_outlined),
              title: const Text('存款（定期 / 活期）'),
              subtitle: const Text('记录利率、起息日、到期日'),
              onTap: () {
                Navigator.of(ctx).pop();
                context.go('/assets/new/deposit');
              },
            ),
            ListTile(
              leading: const Icon(Icons.auto_graph_outlined),
              title: const Text('理财产品'),
              subtitle: const Text('预期年化、当前估值手动维护'),
              onTap: () {
                Navigator.of(ctx).pop();
                context.go('/assets/new/wealth');
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: Spacing.pageMobile,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_balance_wallet_outlined, size: 48),
            SizedBox(height: Spacing.s12),
            Text('尚未录入资产。点击右下角添加现金、存款或理财产品。', textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _AssetsByType extends StatelessWidget {
  const _AssetsByType({required this.assets});

  final List<Asset> assets;

  @override
  Widget build(BuildContext context) {
    final grouped = <AssetType, List<Asset>>{};
    for (final a in assets) {
      grouped.putIfAbsent(a.type, () => []).add(a);
    }
    final order = [
      AssetType.cash,
      AssetType.bankDepositDemand,
      AssetType.bankDepositTerm,
      AssetType.wealthProduct,
    ].where(grouped.containsKey).toList(growable: false);

    return ListView.builder(
      padding: Spacing.pageMobile,
      itemCount: order.length,
      itemBuilder: (context, i) {
        final type = order[i];
        final group = grouped[type]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                top: Spacing.s8,
                bottom: Spacing.s8,
              ),
              child: Text(
                manualAssetTypeLabel(type),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [for (final asset in group) _AssetTile(asset: asset)],
              ),
            ),
            const SizedBox(height: Spacing.s12),
          ],
        );
      },
    );
  }
}

class _AssetTile extends StatelessWidget {
  const _AssetTile({required this.asset});

  final Asset asset;

  @override
  Widget build(BuildContext context) {
    final price = asset.lastPrice ?? Decimal.zero;
    return ListTile(
      title: Text(asset.name ?? asset.symbol),
      subtitle: Text(_subtitle(asset)),
      trailing: MoneyText(
        amount: price.toDouble(),
        currencyCode: asset.currency,
      ),
      onTap: () => context.go('/assets/${asset.id}'),
    );
  }

  String _subtitle(Asset asset) {
    final parts = <String>[];
    if (asset.symbol.isNotEmpty &&
        asset.symbol != asset.name &&
        asset.type != AssetType.cash) {
      parts.add(asset.symbol);
    }
    final meta = asset.manualMetadata;
    if (meta is DepositMetadata) {
      parts.add('利率 ${(meta.interestRate * Decimal.fromInt(100))}%');
      if (meta.maturityDate != null) {
        final d = meta.maturityDate!;
        parts.add('${d.year}-${_two(d.month)}-${_two(d.day)} 到期');
      }
    } else if (meta is WealthProductMetadata) {
      parts.add('预期 ${(meta.expectedAnnualReturn * Decimal.fromInt(100))}%');
      if (meta.issuer != null && meta.issuer!.isNotEmpty) {
        parts.add(meta.issuer!);
      }
    } else {
      parts.add(asset.currency);
    }
    return parts.join(' · ');
  }

  String _two(int n) => n.toString().padLeft(2, '0');
}

String manualAssetTypeLabel(AssetType t) {
  return switch (t) {
    AssetType.cash => '现金',
    AssetType.bankDepositTerm => '定期存款',
    AssetType.bankDepositDemand => '活期存款',
    AssetType.wealthProduct => '理财产品',
    _ => t.name,
  };
}
