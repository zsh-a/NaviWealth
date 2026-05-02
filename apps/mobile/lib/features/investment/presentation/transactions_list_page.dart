import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format/formatters.dart';
import '../../../data/domain/asset.dart';
import '../../../data/domain/enums.dart';
import '../../../data/domain/transaction.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';

/// `/transactions` — flat, month-grouped log of every recorded trade.
///
/// The trade entry form is the only write surface, so this page is read-
/// only: it lets the user verify what was actually recorded, jump to the
/// owning asset, or fan out into a new entry. Transactions are grouped by
/// `tradeDate`'s calendar month; rows within a group are already date-
/// descending because [transactionsStreamProvider] orders newest-first.
class TransactionsListPage extends ConsumerWidget {
  const TransactionsListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final txAsync = ref.watch(transactionsStreamProvider);
    final assetsAsync = ref.watch(allAssetsStreamProvider);
    final assetsById = <String, Asset>{
      for (final a in assetsAsync.value ?? const <Asset>[]) a.id: a,
    };

    return Scaffold(
      appBar: GlassAppBar(title: Text(l10n.transactionsAppBarTitle)),
      body: txAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l10n.transactionsLoadError('$e'))),
        data: (transactions) {
          if (transactions.isEmpty) {
            return _Empty(message: l10n.transactionsEmptyHint);
          }
          return _GroupedTransactionList(
            transactions: transactions,
            assetsById: assetsById,
          );
        },
      ),
      floatingActionButton: AppFab.extended(
        key: const Key('transactions-add-fab'),
        onPressed: () => context.push('/assets/trade'),
        icon: const Icon(Icons.add),
        label: Text(l10n.transactionsAddAction),
      ),
    );
  }
}

class _GroupedTransactionList extends StatelessWidget {
  const _GroupedTransactionList({
    required this.transactions,
    required this.assetsById,
  });

  final List<Transaction> transactions;
  final Map<String, Asset> assetsById;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formatter = AppFormatters(locale: Localizations.localeOf(context));
    final groups = _groupByMonth(transactions);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: Spacing.s8),
      itemCount: groups.length,
      itemBuilder: (context, i) {
        final g = groups[i];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MonthHeader(
              key: Key('transactions-header-${g.key}'),
              label: l10n.transactionsMonthHeader(
                g.year.toString(),
                g.month.toString().padLeft(2, '0'),
              ),
            ),
            for (final tx in g.transactions)
              _TransactionRow(
                key: Key('transactions-row-${tx.id}'),
                transaction: tx,
                asset: tx.assetId == null ? null : assetsById[tx.assetId!],
                formatter: formatter,
              ),
            const Divider(height: 0),
          ],
        );
      },
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.s16,
        Spacing.s12,
        Spacing.s16,
        Spacing.s8,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontFeatures: TypographyTokens.tabularFigures,
        ),
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({
    super.key,
    required this.transaction,
    required this.asset,
    required this.formatter,
  });

  final Transaction transaction;
  final Asset? asset;
  final AppFormatters formatter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final symbol = asset?.symbol ?? transaction.assetId ?? '—';
    final typeLabel = transactionTypeLabel(l10n, transaction.type);
    return ListTile(
      onTap: asset == null
          ? null
          : () => context.push('/assets/${asset!.id}'),
      leading: _TypeChip(type: transaction.type, label: typeLabel),
      title: Text(
        symbol,
        style: theme.textTheme.bodyLarge,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [
          formatter.date(transaction.tradeDate),
          l10n.transactionsRowQuantityPrice(
            '${transaction.quantity}',
            formatter.currency(transaction.price, code: transaction.currency),
          ),
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontFeatures: TypographyTokens.tabularFigures,
        ),
      ),
      trailing: const Icon(Icons.chevron_right, size: 18),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.type, required this.label});

  final TransactionType type;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (bg, fg) = switch (type) {
      TransactionType.buy ||
      TransactionType.transferIn ||
      TransactionType.deposit ||
      TransactionType.dividend ||
      TransactionType.reinvest ||
      TransactionType.interest =>
        (scheme.primary.withValues(alpha: 0.12), scheme.primary),
      TransactionType.sell ||
      TransactionType.transferOut ||
      TransactionType.withdraw ||
      TransactionType.fee ||
      TransactionType.tax ||
      TransactionType.expense =>
        (scheme.error.withValues(alpha: 0.10), scheme.error),
      _ => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.s8,
        vertical: Spacing.s4,
      ),
      decoration: BoxDecoration(color: bg, borderRadius: Radii.brSm),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(color: fg),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: Spacing.pageMobile,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.swap_horiz_outlined, size: 48),
            const SizedBox(height: Spacing.s12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// Shared helper: maps every [TransactionType] to its short display label.
/// Exposed so other surfaces (e.g. a future drawer / detail page) can render
/// the same chip text without duplicating the switch.
String transactionTypeLabel(AppLocalizations l10n, TransactionType type) {
  return switch (type) {
    TransactionType.buy => l10n.tradeTypeBuy,
    TransactionType.sell => l10n.tradeTypeSell,
    TransactionType.transferIn => l10n.tradeTypeTransferIn,
    TransactionType.transferOut => l10n.tradeTypeTransferOut,
    TransactionType.valuationAdjust => l10n.tradeTypeValuationAdjust,
    TransactionType.dividend => l10n.tradeTypeDividend,
    TransactionType.reinvest => l10n.tradeTypeReinvest,
    TransactionType.interest => l10n.tradeTypeInterest,
    TransactionType.deposit => l10n.tradeTypeDeposit,
    TransactionType.withdraw => l10n.tradeTypeWithdraw,
    TransactionType.fee => l10n.tradeTypeFee,
    TransactionType.tax => l10n.tradeTypeTax,
    TransactionType.split => l10n.tradeTypeSplit,
    TransactionType.liabilityPayment => l10n.tradeTypeLiabilityPayment,
    TransactionType.expense => l10n.tradeTypeExpense,
  };
}

class _MonthGroup {
  _MonthGroup(this.year, this.month);
  final int year;
  final int month;
  final List<Transaction> transactions = [];
  String get key => '$year-${month.toString().padLeft(2, '0')}';
}

List<_MonthGroup> _groupByMonth(List<Transaction> transactions) {
  final groups = <String, _MonthGroup>{};
  for (final tx in transactions) {
    final d = tx.tradeDate.toLocal();
    final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
    groups.putIfAbsent(key, () => _MonthGroup(d.year, d.month)).transactions.add(tx);
  }
  // Newest month first; transactions inside each group are already
  // newest-first because the upstream stream orders by tradeDate desc.
  final list = groups.values.toList();
  list.sort((a, b) {
    if (a.year != b.year) return b.year.compareTo(a.year);
    return b.month.compareTo(a.month);
  });
  return list;
}
