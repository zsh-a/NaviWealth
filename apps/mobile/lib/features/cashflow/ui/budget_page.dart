import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../data/db/app_database.dart';
import '../../../data/repositories/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../domain/values/money.dart';
import '../../../l10n/gen/app_localizations.dart';

/// `/plan/budget` — month-scoped budget list.
///
/// MVP scope (`docs/roadmap-next.md` §3.2): the page renders the active
/// month's budgets read from [budgetsForMonthProvider] and exposes a
/// total roll-up. Editing budgets and the spend-vs-budget overlay land
/// in follow-up PRs — the read model + repository wiring (already
/// shipped) is what gates them.
class PlanBudgetPage extends ConsumerWidget {
  const PlanBudgetPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final monthKey = _currentMonthKey(DateTime.now().toUtc());
    final budgetsAsync = ref.watch(budgetsForMonthProvider(monthKey));

    return FScaffold(
      header: FHeader.nested(
        title: Text(l10n.planBudgetTitle),
        prefixes: [backHeaderAction(context)],
      ),
      childPad: false,
      child: budgetsAsync.when(
        loading: () => const Center(child: FCircularProgress()),
        error: (_, _) => Center(
          child: AppEmptyState(
            icon: FLucideIcons.piggyBank,
            title: l10n.planBudgetEmptyTitle,
          ),
        ),
        data: (rows) => _BudgetBody(monthKey: monthKey, rows: rows),
      ),
    );
  }
}

class _BudgetBody extends StatelessWidget {
  const _BudgetBody({required this.monthKey, required this.rows});

  final String monthKey;
  final List<BudgetRow> rows;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (rows.isEmpty) {
      return Center(
        child: AppEmptyState(
          icon: FLucideIcons.piggyBank,
          title: l10n.planBudgetEmptyTitle,
          message: l10n.planBudgetEmptyBody,
        ),
      );
    }
    // Currency totals by ISO code — one user might budget in CNY for
    // groceries and USD for international travel; the header surfaces
    // each currency separately so we never silently sum across them.
    final totalsByCurrency = <String, Decimal>{};
    for (final row in rows) {
      totalsByCurrency.update(
        row.currency.toUpperCase(),
        (acc) => acc + row.amount,
        ifAbsent: () => row.amount,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s12,
        AppSpacing.s16,
        AppSpacing.s24,
      ),
      children: [
        _MonthHeaderCard(
          monthKey: monthKey,
          totalsByCurrency: totalsByCurrency,
          rowCount: rows.length,
        ),
        const SizedBox(height: AppSpacing.s16),
        Text(
          l10n.planBudgetMonthHeader(monthKey),
          style: context.theme.typography.sm.copyWith(
            color: context.theme.colors.mutedForeground,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        for (final row in rows) ...[
          _BudgetTile(row: row),
          const SizedBox(height: AppSpacing.s8),
        ],
      ],
    );
  }
}

class _MonthHeaderCard extends StatelessWidget {
  const _MonthHeaderCard({
    required this.monthKey,
    required this.totalsByCurrency,
    required this.rowCount,
  });

  final String monthKey;
  final Map<String, Decimal> totalsByCurrency;
  final int rowCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.planBudgetTotalLabel,
            style: context.theme.typography.sm.copyWith(
              color: colors.mutedForeground,
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          for (final entry in totalsByCurrency.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s4),
              child: MoneyText(
                amount: entry.value.toDouble(),
                currencyCode: entry.key,
                style: TypographyTokens.numericTitle,
              ),
            ),
          const SizedBox(height: AppSpacing.s4),
          Text(
            '$monthKey · $rowCount',
            style: context.theme.typography.xs.copyWith(
              color: colors.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetTile extends StatelessWidget {
  const _BudgetTile({required this.row});

  final BudgetRow row;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final money = Money(row.amount, row.currency);
    return FCard.raw(
      child: FTile(
        prefix: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: colors.foreground.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Icon(
            FLucideIcons.piggyBank,
            size: 18,
            color: colors.mutedForeground,
          ),
        ),
        title: Text(row.categoryId),
        subtitle: row.note == null ? null : Text(row.note!),
        suffix: MoneyText(
          amount: money.amount.toDouble(),
          currencyCode: money.currency,
        ),
      ),
    );
  }
}

/// Encode the UTC calendar month as `YYYY-MM` — same key shape the
/// repository writes so the family-provider lookup is identity.
String _currentMonthKey(DateTime now) {
  final utc = now.toUtc();
  final m = utc.month.toString().padLeft(2, '0');
  return '${utc.year}-$m';
}
