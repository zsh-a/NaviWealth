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
import '../../l10n/gen/app_localizations.dart';
import 'physical/data/physical_asset.dart';
import 'physical/data/providers.dart';
import 'physical/ui/physical_asset_card.dart';
import 'physical/ui/physical_asset_create_sheet.dart';

/// Tab body for `/assets`. Shows the manual-valuation asset book
/// (cash, deposits, wealth products) grouped by type, plus a "real estate
/// & vehicles" section for non-financial assets, and a FAB that opens a
/// bottom sheet to choose which kind of asset to add.
///
/// Securities / crypto holdings will be appended once their feature ticket
/// lands; this page intentionally only knows about manually-valued rows so
/// the two surfaces can evolve independently.
class AssetsPage extends ConsumerWidget {
  const AssetsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manualAsync = ref.watch(manualAssetsStreamProvider);
    final physicalAsync = ref.watch(physicalAssetsListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('资产'),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_balance_outlined),
            tooltip: '账户管理',
            onPressed: () => context.go('/accounts'),
          ),
          IconButton(
            icon: const Icon(Icons.payments_outlined),
            tooltip: '负债与还款计划',
            onPressed: () => context.push('/assets/liabilities'),
          ),
        ],
      ),
      body: _AssetsBody(
        manualAsync: manualAsync,
        physicalAsync: physicalAsync,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('录入资产'),
      ),
    );
  }

  void _showAddSheet(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
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
            ListTile(
              leading: const Icon(Icons.home_outlined),
              title: Text(l10n.physicalAssetAddRealEstate),
              subtitle: const Text('地址、购入价、当前估值,可关联房贷'),
              onTap: () {
                Navigator.of(ctx).pop();
                _openPhysicalCreate(context, AssetType.realEstate);
              },
            ),
            ListTile(
              leading: const Icon(Icons.directions_car_outlined),
              title: Text(l10n.physicalAssetAddVehicle),
              subtitle: const Text('购入价、年度残值率、自动折旧'),
              onTap: () {
                Navigator.of(ctx).pop();
                _openPhysicalCreate(context, AssetType.vehicle);
              },
            ),
            ListTile(
              leading: const Icon(Icons.account_balance_outlined),
              title: const Text('负债（房贷 / 车贷 / 信用卡 / 消费贷）'),
              subtitle: const Text('录入并跟踪还款计划'),
              onTap: () {
                Navigator.of(ctx).pop();
                context.push('/assets/liabilities');
              },
            ),
            ListTile(
              leading: const Icon(Icons.account_tree_outlined),
              title: Text(l10n.assetsCorporateActionAction),
              subtitle: const Text('分红 / 拆股 / 配股 / 红股 / DRIP'),
              onTap: () {
                Navigator.of(ctx).pop();
                context.push('/assets/corporate-action');
              },
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz_outlined),
              title: const Text('证券交易'),
              subtitle: const Text('买入 / 卖出股票、ETF、加密货币'),
              onTap: () {
                Navigator.of(ctx).pop();
                context.push('/assets/trade');
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openPhysicalCreate(
    BuildContext context,
    AssetType type,
  ) async {
    final created = await PhysicalAssetCreateSheet.show(context, type: type);
    if (created != null && context.mounted) {
      context.goNamed(
        'physicalAssetDetail',
        pathParameters: {'id': created.id},
      );
    }
  }
}

class _AssetsBody extends StatelessWidget {
  const _AssetsBody({
    required this.manualAsync,
    required this.physicalAsync,
  });

  final AsyncValue<List<Asset>> manualAsync;
  final AsyncValue<List<PhysicalAsset>> physicalAsync;

  @override
  Widget build(BuildContext context) {
    if (manualAsync.isLoading || physicalAsync.isLoading) {
      return const _AssetsSkeleton();
    }
    final manualErr = manualAsync.hasError ? manualAsync.error : null;
    final physicalErr = physicalAsync.hasError ? physicalAsync.error : null;
    if (manualErr != null && physicalErr != null) {
      return Center(child: Text('加载失败：$manualErr'));
    }
    final manual = manualAsync.value ?? const <Asset>[];
    final physical = physicalAsync.value ?? const <PhysicalAsset>[];
    if (manual.isEmpty && physical.isEmpty) {
      return const _EmptyHint();
    }
    return ListView(
      padding: Spacing.pageMobile,
      children: [
        if (manual.isNotEmpty) _ManualAssetsSection(assets: manual),
        if (physical.isNotEmpty) _PhysicalAssetsSection(assets: physical),
      ],
    );
  }
}

class _AssetsSkeleton extends StatelessWidget {
  const _AssetsSkeleton();

  Widget _row() {
    return const Padding(
      padding: EdgeInsets.symmetric(
        horizontal: Spacing.s16,
        vertical: Spacing.s12,
      ),
      child: Row(
        children: [
          SkeletonBox(width: 36, height: 36, radius: Radii.full),
          SizedBox(width: Spacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 140, height: 14),
                SizedBox(height: Spacing.s6),
                SkeletonBox(width: 88, height: 12),
              ],
            ),
          ),
          SizedBox(width: Spacing.s12),
          SkeletonBox(width: 80, height: 16),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: Spacing.pageMobile,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: Spacing.s8),
          child: SkeletonBox(width: 100, height: 18),
        ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _row(),
              const Divider(height: 1),
              _row(),
              const Divider(height: 1),
              _row(),
            ],
          ),
        ),
        const SizedBox(height: Spacing.s12),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: Spacing.s8),
          child: SkeletonBox(width: 120, height: 18),
        ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _row(),
              const Divider(height: 1),
              _row(),
            ],
          ),
        ),
      ],
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
            Text(
              '尚未录入资产。点击右下角添加现金、存款、理财、房产或车辆。',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ManualAssetsSection extends StatelessWidget {
  const _ManualAssetsSection({required this.assets});

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final type in order) ...[
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
              children: [
                for (final asset in grouped[type]!) _AssetTile(asset: asset),
              ],
            ),
          ),
          const SizedBox(height: Spacing.s12),
        ],
      ],
    );
  }
}

class _PhysicalAssetsSection extends StatelessWidget {
  const _PhysicalAssetsSection({required this.assets});

  final List<PhysicalAsset> assets;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            top: Spacing.s8,
            bottom: Spacing.s8,
          ),
          child: Text(
            l10n.physicalAssetsSectionTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        for (final asset in assets) ...[
          PhysicalAssetCard(asset: asset),
          const SizedBox(height: Spacing.s8),
        ],
        const SizedBox(height: Spacing.s12),
      ],
    );
  }
}

class _AssetTile extends StatelessWidget {
  const _AssetTile({required this.asset});

  final Asset asset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final price = asset.lastPrice ?? Decimal.zero;
    final chips = _chipsFor(asset);
    return InkWell(
      onTap: () => context.go('/assets/${asset.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.s16,
          vertical: Spacing.s12,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    asset.name ?? asset.symbol,
                    style: theme.textTheme.bodyLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (chips.isNotEmpty) ...[
                    const SizedBox(height: Spacing.s6),
                    Wrap(
                      spacing: Spacing.s6,
                      runSpacing: Spacing.s4,
                      children: chips,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: Spacing.s12),
            MoneyText(
              amount: price.toDouble(),
              currencyCode: asset.currency,
              style: TypographyTokens.numericBody,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _chipsFor(Asset asset) {
    final chips = <Widget>[];
    if (asset.symbol.isNotEmpty &&
        asset.symbol != asset.name &&
        asset.type != AssetType.cash) {
      chips.add(_MetaChip(label: asset.symbol));
    }
    final meta = asset.manualMetadata;
    if (meta is DepositMetadata) {
      chips.add(
        _MetaChip(label: '利率 ${_formatRatePercent(meta.interestRate)}%'),
      );
      if (meta.maturityDate != null) {
        final d = meta.maturityDate!;
        chips.add(
          _MetaChip(label: '${d.year}-${_two(d.month)}-${_two(d.day)} 到期'),
        );
      }
    } else if (meta is WealthProductMetadata) {
      chips.add(
        _MetaChip(
          label: '预期 ${_formatRatePercent(meta.expectedAnnualReturn)}%',
        ),
      );
      if (meta.issuer != null && meta.issuer!.isNotEmpty) {
        chips.add(_MetaChip(label: meta.issuer!));
      }
    }
    chips.add(_MetaChip(label: asset.currency));
    return chips;
  }

  static String _formatRatePercent(Decimal rate) {
    final pct = (rate * Decimal.fromInt(100)).toDouble();
    return pct
        .toStringAsFixed(2)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNumeric = RegExp(r'\d').hasMatch(label);
    final base = theme.textTheme.labelSmall ?? TypographyTokens.labelSmall;
    final textStyle = base.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontFeatures: isNumeric ? TypographyTokens.tabularFigures : null,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: Radii.brSm,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.s8,
          vertical: Spacing.s2,
        ),
        child: Text(label, style: textStyle),
      ),
    );
  }
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
