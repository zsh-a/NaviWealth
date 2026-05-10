import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/format/formatters.dart';
import '../../../data/domain/account.dart';
import '../../../data/domain/asset.dart';
import '../../../data/domain/manual_asset_metadata.dart';
import '../../../data/repositories/providers.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../home/data/dashboard_providers.dart';
import '../../home/ui/asset_category_visuals.dart';

class PortfolioByClassView extends ConsumerWidget {
  const PortfolioByClassView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(dashboardSnapshotProvider);
    return snapshot.when(
      loading: () => const Center(child: FCircularProgress()),
      error: (e, _) => _ErrorText(error: e),
      data: (value) => _AggregateList(
        rows: [
          for (final allocation in value.allocations)
            _AggregateRow(
              title: AssetCategoryVisuals.label(
                AppLocalizations.of(context),
                allocation.category,
              ),
              subtitle: AppLocalizations.of(
                context,
              ).portfolioAggregateItems(allocation.items.length),
              value: allocation.totalInBase.amount,
              currency: value.baseCurrency,
              icon: AssetCategoryVisuals.icon(allocation.category),
            ),
        ],
      ),
    );
  }
}

class PortfolioByCurrencyView extends ConsumerWidget {
  const PortfolioByCurrencyView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(dashboardSnapshotProvider);
    return snapshot.when(
      loading: () => const Center(child: FCircularProgress()),
      error: (e, _) => _ErrorText(error: e),
      data: (value) {
        final byCurrency =
            <String, ({Decimal native, Decimal base, int count})>{};
        for (final allocation in value.allocations) {
          for (final item in allocation.items) {
            final existing = byCurrency[item.nativeCurrency];
            byCurrency[item.nativeCurrency] = (
              native: (existing?.native ?? Decimal.zero) + item.nativeAmount,
              base: (existing?.base ?? Decimal.zero) + item.valueInBase.amount,
              count: (existing?.count ?? 0) + 1,
            );
          }
        }
        final rows = byCurrency.entries.map((entry) {
          final aggregate = entry.value;
          return _AggregateRow(
            title: entry.key,
            subtitle: AppLocalizations.of(context).portfolioCurrencyNative(
              _compact(context, aggregate.native, entry.key),
            ),
            value: aggregate.base,
            currency: value.baseCurrency,
            icon: Icons.currency_exchange_outlined,
          );
        }).toList()..sort((a, b) => b.value.compareTo(a.value));
        return _AggregateList(rows: rows);
      },
    );
  }
}

class PortfolioByAccountView extends ConsumerWidget {
  const PortfolioByAccountView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(dashboardSnapshotProvider);
    final manualAssets = ref.watch(manualAssetsStreamProvider);
    final accounts = ref.watch(accountsStreamProvider);
    return snapshot.when(
      loading: () => const Center(child: FCircularProgress()),
      error: (e, _) => _ErrorText(error: e),
      data: (value) {
        final accountById = <String, Account>{
          for (final account in accounts.value ?? const <Account>[])
            account.id: account,
        };
        final assetToAccount = _assetAccountMap(manualAssets.value ?? const []);
        final l10n = AppLocalizations.of(context);
        final byAccount = <String, ({Decimal base, int count})>{};
        for (final allocation in value.allocations) {
          for (final item in allocation.items) {
            final accountId = assetToAccount[item.id];
            final title = accountId == null
                ? l10n.portfolioUnassignedAccount
                : accountById[accountId]?.name ??
                      l10n.portfolioUnassignedAccount;
            final existing = byAccount[title];
            byAccount[title] = (
              base: (existing?.base ?? Decimal.zero) + item.valueInBase.amount,
              count: (existing?.count ?? 0) + 1,
            );
          }
        }
        final rows = byAccount.entries.map((entry) {
          return _AggregateRow(
            title: entry.key,
            subtitle: l10n.portfolioAggregateItems(entry.value.count),
            value: entry.value.base,
            currency: value.baseCurrency,
            icon: Icons.account_balance_wallet_outlined,
          );
        }).toList()..sort((a, b) => b.value.compareTo(a.value));
        return _AggregateList(rows: rows);
      },
    );
  }

  Map<String, String> _assetAccountMap(List<Asset> assets) {
    final out = <String, String>{};
    for (final asset in assets) {
      final metadata = ManualAssetMetadata.decode(asset.metadataJson);
      if (metadata != null) out[asset.id] = metadata.accountId;
    }
    return out;
  }
}

class _AggregateList extends StatelessWidget {
  const _AggregateList({required this.rows});

  final List<_AggregateRow> rows;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (rows.isEmpty) {
      return Center(child: Text(l10n.assetsEmptyHint));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16).copyWith(
        top: 8,
        bottom:
            const EdgeInsets.all(16).bottom +
            64 +
            MediaQuery.paddingOf(context).bottom,
      ),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _AggregateTile(row: rows[index]),
    );
  }
}

class _AggregateTile extends StatelessWidget {
  const _AggregateTile({required this.row});

  final _AggregateRow row;

  @override
  Widget build(BuildContext context) {
    final formatter = AppFormatters(locale: Localizations.localeOf(context));
    return FCard.raw(
      child: FTile(
        title: Text(row.title),
        prefix: Icon(row.icon),
        subtitle: Text(row.subtitle),
        suffix: Text(
          formatter.compactCurrency(row.value, code: row.currency),
          style: context.theme.typography.sm,
        ),
      ),
    );
  }
}

class _AggregateRow {
  const _AggregateRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.currency,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final Decimal value;
  final String currency;
  final IconData icon;
}

class _ErrorText extends StatelessWidget {
  const _ErrorText({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(AppLocalizations.of(context).assetsLoadError('$error')),
    );
  }
}

String _compact(BuildContext context, Decimal amount, String currency) {
  return AppFormatters(
    locale: Localizations.localeOf(context),
  ).compactCurrency(amount, code: currency);
}
