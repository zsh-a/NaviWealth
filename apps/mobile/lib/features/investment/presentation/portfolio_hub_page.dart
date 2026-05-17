import 'dart:math' as math;

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/route_paths.dart';
import '../../../core/async/async_notifier_convention.dart';
import '../../../core/haptics/haptics.dart';
import '../../../data/domain/account.dart';
import '../../../data/domain/asset.dart';
import '../../../data/domain/enums.dart';
import '../../../data/repositories/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '../domain/models/holding_snapshot.dart';
import '../domain/models/lot.dart';
import '../domain/returns/portfolio_return.dart';

final portfolioHubProvider =
    AsyncNotifierProvider<PortfolioHubNotifier, PortfolioHubState>(
      PortfolioHubNotifier.new,
    );

class PortfolioHubNotifier
    extends ConventionalAsyncNotifier<PortfolioHubState> {
  @override
  Future<PortfolioHubState> fetch() async {
    final now = DateTime.now().toUtc();
    final today = DateTime.utc(now.year, now.month, now.day);
    final yearStart = DateTime.utc(today.year, 1, 1);

    final holdings = await ref.watch(holdingsSnapshotProvider.future);
    final assets = await ref.watch(allAssetsStreamProvider.future);
    final accounts = await ref.watch(accountsStreamProvider.future);
    final baseCurrency = ref.watch(holdingBaseCurrencyProvider);
    final holdingService = await ref.watch(holdingServiceProvider.future);
    final returnService = await ref.watch(
      portfolioReturnServiceProvider.future,
    );
    final lots = await holdingService.lotsAt(now);
    final returns = await returnService.compute(from: yearStart, to: today);

    final assetById = {for (final asset in assets) asset.id: asset};
    final accountById = {for (final account in accounts) account.id: account};
    final rows = [
      for (final entry in holdings.entries)
        PortfolioHoldingRow.fromSnapshot(
          snapshot: entry.value,
          asset: assetById[entry.key],
        ),
    ]..sort((a, b) => b.marketValueInBase.compareTo(a.marketValueInBase));

    final marketValue = _sum(rows.map((row) => row.marketValueInBase));
    final costBasis = _sum(rows.map((row) => row.costBasisInBase));
    final unrealizedPnl = _sum(rows.map((row) => row.unrealizedPnlInBase));
    return PortfolioHubState(
      holdings: rows,
      lots: lots,
      accountById: accountById,
      baseCurrency: baseCurrency,
      marketValueInBase: marketValue,
      costBasisInBase: costBasis,
      unrealizedPnlInBase: unrealizedPnl,
      ytdReturn: returns,
    );
  }
}

class PortfolioHubState {
  const PortfolioHubState({
    required this.holdings,
    required this.lots,
    required this.accountById,
    required this.baseCurrency,
    required this.marketValueInBase,
    required this.costBasisInBase,
    required this.unrealizedPnlInBase,
    required this.ytdReturn,
  });

  final List<PortfolioHoldingRow> holdings;
  final List<Lot> lots;
  final Map<String, Account> accountById;
  final String baseCurrency;
  final Decimal marketValueInBase;
  final Decimal costBasisInBase;
  final Decimal unrealizedPnlInBase;
  final PortfolioReturnResult ytdReturn;

  double? get xirrRatio => ytdReturn.displayReturn;

  List<PortfolioGroupRow> groupsFor(
    PortfolioHubView view,
    AppLocalizations l10n,
  ) {
    switch (view) {
      case PortfolioHubView.account:
        return _accountGroups(l10n);
      case PortfolioHubView.currency:
        return _groupBy(
          idOf: (row) => row.assetCurrency,
          titleOf: (row) => row.assetCurrency,
          subtitleOf: (_) => l10n.portfolioHubCurrencyGroupSubtitle,
        );
      case PortfolioHubView.assetClass:
        return _groupBy(
          idOf: (row) => row.assetType.name,
          titleOf: (row) => row.assetTypeLabel(l10n),
          subtitleOf: (_) => l10n.portfolioHubAssetClassGroupSubtitle,
        );
    }
  }

  List<PortfolioGroupRow> _accountGroups(AppLocalizations l10n) {
    final holdingByAsset = {for (final row in holdings) row.assetId: row};
    final assetQuantity = <String, Decimal>{};
    final assetCost = <String, Decimal>{};
    for (final lot in lots.where((lot) => !lot.isClosed)) {
      assetQuantity.update(
        lot.assetId,
        (value) => value + lot.remainingQuantity,
        ifAbsent: () => lot.remainingQuantity,
      );
      assetCost.update(
        lot.assetId,
        (value) => value + lot.remainingCost,
        ifAbsent: () => lot.remainingCost,
      );
    }

    final buckets = <String, _GroupAccumulator>{};
    for (final lot in lots.where((lot) => !lot.isClosed)) {
      final holding = holdingByAsset[lot.assetId];
      if (holding == null) continue;
      final totalQty = assetQuantity[lot.assetId] ?? Decimal.zero;
      if (totalQty.sign <= 0) continue;

      final qtyRatio = (lot.remainingQuantity / totalQty).toDecimal(
        scaleOnInfinitePrecision: 12,
      );
      final totalCost = assetCost[lot.assetId] ?? Decimal.zero;
      final costRatio = totalCost.sign <= 0
          ? qtyRatio
          : (lot.remainingCost / totalCost).toDecimal(
              scaleOnInfinitePrecision: 12,
            );
      final marketValue = holding.marketValueInBase * qtyRatio;
      final costBasis = holding.costBasisInBase * costRatio;
      final account = accountById[lot.accountId];
      final title = account?.name ?? l10n.portfolioHubUnknownAccount;
      final subtitle = account?.institution?.isNotEmpty == true
          ? account!.institution!
          : l10n.portfolioHubAccountGroupSubtitle;
      buckets
          .putIfAbsent(
            lot.accountId,
            () => _GroupAccumulator(
              id: lot.accountId,
              title: title,
              subtitle: subtitle,
              baseCurrency: baseCurrency,
            ),
          )
          .add(
            marketValue: marketValue,
            costBasis: costBasis,
            holdingId: lot.assetId,
          );
    }
    return _sortedGroups(buckets.values);
  }

  List<PortfolioGroupRow> _groupBy({
    required String Function(PortfolioHoldingRow row) idOf,
    required String Function(PortfolioHoldingRow row) titleOf,
    required String Function(PortfolioHoldingRow row) subtitleOf,
  }) {
    final buckets = <String, _GroupAccumulator>{};
    for (final row in holdings) {
      final id = idOf(row);
      buckets
          .putIfAbsent(
            id,
            () => _GroupAccumulator(
              id: id,
              title: titleOf(row),
              subtitle: subtitleOf(row),
              baseCurrency: baseCurrency,
            ),
          )
          .add(
            marketValue: row.marketValueInBase,
            costBasis: row.costBasisInBase,
            holdingId: row.assetId,
          );
    }
    return _sortedGroups(buckets.values);
  }

  List<PortfolioGroupRow> _sortedGroups(Iterable<_GroupAccumulator> groups) {
    return [
      for (final group in groups)
        group.toRow(totalMarketValue: marketValueInBase),
    ]..sort((a, b) => b.marketValueInBase.compareTo(a.marketValueInBase));
  }
}

class PortfolioHoldingRow {
  const PortfolioHoldingRow({
    required this.assetId,
    required this.title,
    required this.subtitle,
    required this.assetType,
    required this.assetCurrency,
    required this.quantity,
    required this.marketValueInBase,
    required this.costBasisInBase,
    required this.unrealizedPnlInBase,
    required this.weight,
    required this.baseCurrency,
  });

  factory PortfolioHoldingRow.fromSnapshot({
    required HoldingSnapshot snapshot,
    required Asset? asset,
  }) {
    return PortfolioHoldingRow(
      assetId: snapshot.assetId,
      title: asset?.name?.isNotEmpty == true
          ? asset!.name!
          : asset?.symbol ?? snapshot.assetId,
      subtitle: asset?.symbol ?? snapshot.assetId,
      assetType: asset?.type ?? AssetType.custom,
      assetCurrency: snapshot.assetCurrency,
      quantity: snapshot.quantity,
      marketValueInBase: snapshot.marketValueInBase,
      costBasisInBase: snapshot.costBasisInBase,
      unrealizedPnlInBase: snapshot.unrealizedPnlInBase,
      weight: snapshot.weight,
      baseCurrency: snapshot.baseCurrency,
    );
  }

  final String assetId;
  final String title;
  final String subtitle;
  final AssetType assetType;
  final String assetCurrency;
  final Decimal quantity;
  final Decimal marketValueInBase;
  final Decimal costBasisInBase;
  final Decimal unrealizedPnlInBase;
  final Decimal weight;
  final String baseCurrency;

  String assetTypeLabel(AppLocalizations l10n) {
    switch (assetType) {
      case AssetType.stock:
        return l10n.portfolioHubAssetTypeStock;
      case AssetType.etf:
        return l10n.portfolioHubAssetTypeEtf;
      case AssetType.mutualFund:
        return l10n.portfolioHubAssetTypeMutualFund;
      case AssetType.bond:
        return l10n.portfolioHubAssetTypeBond;
      case AssetType.crypto:
        return l10n.portfolioHubAssetTypeCrypto;
      case AssetType.cash:
        return l10n.portfolioHubAssetTypeCash;
      case AssetType.realEstate:
        return l10n.physicalAssetTypeRealEstate;
      case AssetType.vehicle:
        return l10n.physicalAssetTypeVehicle;
      case AssetType.commodity:
        return l10n.portfolioHubAssetTypeCommodity;
      case AssetType.custom:
        return l10n.portfolioHubAssetTypeCustom;
      case AssetType.bankDepositTerm:
        return l10n.portfolioHubAssetTypeBankDepositTerm;
      case AssetType.bankDepositDemand:
        return l10n.portfolioHubAssetTypeBankDepositDemand;
      case AssetType.wealthProduct:
        return l10n.portfolioHubAssetTypeWealthProduct;
    }
  }
}

class PortfolioGroupRow {
  const PortfolioGroupRow({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.baseCurrency,
    required this.marketValueInBase,
    required this.costBasisInBase,
    required this.unrealizedPnlInBase,
    required this.weight,
    required this.holdingsCount,
  });

  final String id;
  final String title;
  final String subtitle;
  final String baseCurrency;
  final Decimal marketValueInBase;
  final Decimal costBasisInBase;
  final Decimal unrealizedPnlInBase;
  final Decimal weight;
  final int holdingsCount;
}

enum PortfolioHubView { account, currency, assetClass }

class PortfolioHubPage extends ConsumerStatefulWidget {
  const PortfolioHubPage({super.key});

  @override
  ConsumerState<PortfolioHubPage> createState() => _PortfolioHubPageState();
}

class _PortfolioHubPageState extends ConsumerState<PortfolioHubPage> {
  PortfolioHubView _view = PortfolioHubView.account;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(portfolioHubProvider);

    return FScaffold(
      header: FHeader.nested(
        title: Text(l10n.portfolioHubTitle),
        prefixes: [backHeaderAction(context)],
      ),
      childPad: false,
      child: state.when(
        loading: () => const _PortfolioHubSkeleton(),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(l10n.portfolioHubLoadError('$error')),
          ),
        ),
        data: (data) => RefreshIndicator(
          onRefresh: () => ref.read(portfolioHubProvider.notifier).refresh(),
          child: _PortfolioHubBody(
            data: data,
            view: _view,
            onViewChanged: (next) => setState(() => _view = next),
          ),
        ),
      ),
    );
  }
}

class _PortfolioHubBody extends StatelessWidget {
  const _PortfolioHubBody({
    required this.data,
    required this.view,
    required this.onViewChanged,
  });

  final PortfolioHubState data;
  final PortfolioHubView view;
  final ValueChanged<PortfolioHubView> onViewChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final hPad = Breakpoints.isMobile(width) ? 16.0 : 24.0;
    final groups = data.groupsFor(view, l10n);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        hPad,
        8,
        hPad,
        80 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        _PortfolioSummary(data: data),
        const SizedBox(height: 20),
        PortfolioHubViewSegment(value: view, onChanged: onViewChanged),
        const SizedBox(height: 16),
        Text(
          l10n.portfolioHubHoldingsTitle,
          style: context.theme.typography.lg.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        if (groups.isEmpty)
          _EmptyState(message: l10n.portfolioHubEmpty)
        else
          for (final group in groups) ...[
            _GroupRowCard(group: group),
            const SizedBox(height: 10),
          ],
        const SizedBox(height: 12),
        Text(
          l10n.portfolioHubPositionsTitle,
          style: context.theme.typography.lg.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        if (data.holdings.isEmpty)
          _EmptyState(message: l10n.portfolioHubEmpty)
        else
          for (final holding in data.holdings.take(12)) ...[
            _HoldingRowCard(holding: holding),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _PortfolioSummary extends StatelessWidget {
  const _PortfolioSummary({required this.data});

  final PortfolioHubState data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final xirr = data.xirrRatio;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.portfolioHubMarketValueLabel.toUpperCase(),
          style: context.theme.typography.xs2.copyWith(
            color: context.theme.colors.mutedForeground,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        AnimatedMoneyText(
          amount: data.marketValueInBase.toDouble(),
          currencyCode: data.baseCurrency,
          style: TypographyTokens.numericTitle.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _SummaryMetric(
                label: l10n.portfolioHubYtdXirrLabel,
                value: xirr == null ? '—' : _formatRatio(context, xirr),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryMetric.money(
                label: l10n.portfolioHubAbsoluteReturnLabel,
                amount: data.unrealizedPnlInBase.toDouble(),
                currency: data.baseCurrency,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.label, required this.value})
    : amount = null,
      currency = null;

  const _SummaryMetric.money({
    required this.label,
    required double this.amount,
    required String this.currency,
  }) : value = null;

  final String label;
  final String? value;
  final double? amount;
  final String? currency;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.theme.colors.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: context.theme.typography.xs.copyWith(
                color: context.theme.colors.mutedForeground,
              ),
            ),
            const SizedBox(height: 4),
            if (amount == null)
              Text(
                value ?? '—',
                style: context.theme.typography.lg.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              )
            else
              AnimatedMoneyText(
                amount: amount,
                currencyCode: currency!,
                showSign: true,
                style: context.theme.typography.lg.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class PortfolioHubViewSegment extends StatelessWidget {
  const PortfolioHubViewSegment({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final PortfolioHubView value;
  final ValueChanged<PortfolioHubView> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final labels = {
      PortfolioHubView.account: l10n.portfolioHubViewAccount,
      PortfolioHubView.currency: l10n.portfolioHubViewCurrency,
      PortfolioHubView.assetClass: l10n.portfolioHubViewAssetClass,
    };
    final icons = {
      PortfolioHubView.account: Icons.account_balance_wallet_outlined,
      PortfolioHubView.currency: Icons.payments_outlined,
      PortfolioHubView.assetClass: Icons.category_outlined,
    };

    return Container(
      decoration: BoxDecoration(
        color: context.theme.colors.secondary.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        children: [
          for (final view in PortfolioHubView.values)
            Expanded(
              child: _ViewChip(
                label: labels[view]!,
                icon: icons[view]!,
                selected: value == view,
                onTap: () {
                  Haptics.selection();
                  onChanged(view);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ViewChip extends StatelessWidget {
  const _ViewChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? context.theme.colors.primary
        : context.theme.colors.mutedForeground;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: Motion.medium,
        curve: Motion.emphasizedDecelerate,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: selected
              ? context.theme.colors.background
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: context.theme.typography.xs.copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupRowCard extends StatelessWidget {
  const _GroupRowCard({required this.group});

  final PortfolioGroupRow group;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FCard.raw(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _TitleSubtitle(
                    title: group.title,
                    subtitle:
                        '${group.subtitle} · ${l10n.portfolioHubHoldingCount(group.holdingsCount)}',
                  ),
                ),
                AnimatedMoneyText(
                  amount: group.marketValueInBase.toDouble(),
                  currencyCode: group.baseCurrency,
                  style: context.theme.typography.sm.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _WeightBar(weight: group.weight.toDouble()),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  _formatRatio(context, group.weight.toDouble()),
                  style: context.theme.typography.xs.copyWith(
                    color: context.theme.colors.mutedForeground,
                  ),
                ),
                const Spacer(),
                AnimatedMoneyText(
                  amount: group.unrealizedPnlInBase.toDouble(),
                  currencyCode: group.baseCurrency,
                  showSign: true,
                  style: context.theme.typography.xs.copyWith(
                    color: context.theme.colors.mutedForeground,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HoldingRowCard extends StatelessWidget {
  const _HoldingRowCard({required this.holding});

  final PortfolioHoldingRow holding;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FCard.raw(
      child: GestureDetector(
        onTap: () => context.push(AppRoutes.accountAsset(holding.assetId)),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: _TitleSubtitle(
                  title: holding.title,
                  subtitle:
                      '${holding.assetTypeLabel(l10n)} · ${holding.subtitle}',
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  AnimatedMoneyText(
                    amount: holding.marketValueInBase.toDouble(),
                    currencyCode: holding.baseCurrency,
                    style: context.theme.typography.sm.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatRatio(context, holding.weight.toDouble()),
                    style: context.theme.typography.xs.copyWith(
                      color: context.theme.colors.mutedForeground,
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

class _TitleSubtitle extends StatelessWidget {
  const _TitleSubtitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.theme.typography.sm.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.theme.typography.xs.copyWith(
            color: context.theme.colors.mutedForeground,
          ),
        ),
      ],
    );
  }
}

class _WeightBar extends StatelessWidget {
  const _WeightBar({required this.weight});

  final double weight;

  @override
  Widget build(BuildContext context) {
    final clamped = weight.clamp(0, 1).toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 5,
        child: LinearProgressIndicator(
          value: clamped,
          backgroundColor: context.theme.colors.secondary,
          valueColor: AlwaysStoppedAnimation<Color>(
            context.theme.colors.primary,
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Text(
          message,
          style: context.theme.typography.sm.copyWith(
            color: context.theme.colors.mutedForeground,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _PortfolioHubSkeleton extends StatelessWidget {
  const _PortfolioHubSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        SkeletonBox(width: 120, height: 12, radius: 4),
        SizedBox(height: 8),
        SkeletonBox(width: 220, height: 34, radius: 8),
        SizedBox(height: 24),
        SkeletonBox(height: 42, radius: 999),
        SizedBox(height: 18),
        SkeletonBox(height: 82, radius: 8),
        SizedBox(height: 10),
        SkeletonBox(height: 82, radius: 8),
        SizedBox(height: 10),
        SkeletonBox(height: 82, radius: 8),
      ],
    );
  }
}

class _GroupAccumulator {
  _GroupAccumulator({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.baseCurrency,
  });

  final String id;
  final String title;
  final String subtitle;
  final String baseCurrency;
  final Set<String> holdingIds = {};
  Decimal marketValue = Decimal.zero;
  Decimal costBasis = Decimal.zero;

  void add({
    required Decimal marketValue,
    required Decimal costBasis,
    required String holdingId,
  }) {
    this.marketValue += marketValue;
    this.costBasis += costBasis;
    holdingIds.add(holdingId);
  }

  PortfolioGroupRow toRow({required Decimal totalMarketValue}) {
    final weight = totalMarketValue.sign <= 0
        ? Decimal.zero
        : (marketValue / totalMarketValue).toDecimal(
            scaleOnInfinitePrecision: 8,
          );
    return PortfolioGroupRow(
      id: id,
      title: title,
      subtitle: subtitle,
      baseCurrency: baseCurrency,
      marketValueInBase: marketValue,
      costBasisInBase: costBasis,
      unrealizedPnlInBase: marketValue - costBasis,
      weight: weight,
      holdingsCount: holdingIds.length,
    );
  }
}

Decimal _sum(Iterable<Decimal> values) {
  var total = Decimal.zero;
  for (final value in values) {
    total += value;
  }
  return total;
}

String _formatRatio(BuildContext context, double value) {
  if (value.isNaN || value.isInfinite) return '—';
  final locale = Localizations.localeOf(context).toLanguageTag();
  final digits = math.max(1, value.abs() < 0.1 ? 2 : 1);
  final format = NumberFormat.percentPattern(locale)
    ..minimumFractionDigits = digits
    ..maximumFractionDigits = digits;
  return format.format(value);
}
