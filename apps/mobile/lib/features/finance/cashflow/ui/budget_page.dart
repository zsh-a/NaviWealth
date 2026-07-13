import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../domain/budget_summary.dart';

/// `/plan/budget` — month-scoped budget list.
///
/// Renders the active month's budgets, realised spend, remaining headroom,
/// and an edit sheet for existing category caps.
class PlanBudgetPage extends ConsumerWidget {
  const PlanBudgetPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final monthKey = _currentMonthKey(DateTime.now().toUtc());
    final budgetsAsync = ref.watch(budgetsForMonthProvider(monthKey));
    final summaryAsync = ref.watch(monthlyBudgetSummaryProvider(monthKey));

    return AppPageScaffold(
      title: l10n.planBudgetTitle,
      childPad: false,
      child: budgetsAsync.whenOrLoading(
        context: context,
        error: (_, _) => Center(
          child: AppEmptyState(
            icon: FLucideIcons.piggyBank,
            title: l10n.planBudgetEmptyTitle,
          ),
        ),
        data: (rows) => _BudgetBody(
          monthKey: monthKey,
          rows: rows,
          summary: summaryAsync.hasValue
              ? summaryAsync.requireValue.summary
              : null,
        ),
      ),
    );
  }
}

class _BudgetBody extends ConsumerWidget {
  const _BudgetBody({
    required this.monthKey,
    required this.rows,
    required this.summary,
  });

  final String monthKey;
  final List<BudgetRow> rows;
  final MonthlyBudgetSummary? summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    final statusByCategory = {
      for (final item in summary?.categories ?? const <CategoryBudgetStatus>[])
        item.categoryId: item,
    };
    final totalsByCurrency = _totalsByCurrency(rows);

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
          summary: summary,
          rowCount: rows.length,
        ),
        const SizedBox(height: AppSpacing.s16),
        Text(
          l10n.planBudgetMonthHeader(monthKey),
          style: context.mutedLabelStyle,
        ),
        const SizedBox(height: AppSpacing.s8),
        for (final row in rows) ...[
          _BudgetTile(
            row: row,
            status: statusByCategory[row.categoryId],
            onEdit: () => _showBudgetEditSheet(context, ref, row),
          ),
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
    required this.summary,
    required this.rowCount,
  });

  final String monthKey;
  final Map<String, Decimal> totalsByCurrency;
  final MonthlyBudgetSummary? summary;
  final int rowCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SoftCard.raised(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.planBudgetTotalLabel, style: context.bodyCaptionStyle),
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
          if (summary != null) ...[
            const SizedBox(height: AppSpacing.s8),
            _BudgetProgress(
              spent: summary!.totalSpent,
              budgeted: summary!.totalBudgeted,
              progress: summary!.progressFraction,
              isOverBudget: summary!.isOverBudget,
            ),
          ],
          const SizedBox(height: AppSpacing.s4),
          Text('$monthKey · $rowCount', style: context.captionStyle),
        ],
      ),
    );
  }
}

class _BudgetTile extends StatelessWidget {
  const _BudgetTile({required this.row, required this.status, this.onEdit});

  final BudgetRow row;
  final CategoryBudgetStatus? status;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    final money = Money(row.amount, row.currency);
    final remaining = status?.remaining;
    return SoftCard.flat(
      child: FTappable(
        onPress: onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s12,
            vertical: AppSpacing.s12,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: colors.foreground.withValues(
                        alpha: AppOpacity.whisper,
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      FLucideIcons.piggyBank,
                      size: AppIconSizes.h18,
                      color: colors.mutedForeground,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(row.categoryId),
                        if (row.note != null)
                          Text(row.note!, style: context.captionStyle),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      MoneyText(
                        amount: money.amount.toDouble(),
                        currencyCode: money.currency,
                      ),
                      if (remaining != null)
                        Text(
                          remaining.isNegative
                              ? l10n.planBudgetOverBy(
                                  remaining.amount.abs().toString(),
                                  remaining.currency,
                                )
                              : l10n.planBudgetRemaining(
                                  remaining.amount.toString(),
                                  remaining.currency,
                                ),
                          style: context.captionStyle.copyWith(
                            color: remaining.isNegative
                                ? colors.destructive
                                : colors.mutedForeground,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  Icon(
                    FLucideIcons.pencil,
                    size: AppIconSizes.sm,
                    color: colors.mutedForeground,
                  ),
                ],
              ),
              if (status != null) ...[
                const SizedBox(height: AppSpacing.s10),
                _BudgetProgress(
                  spent: status!.spent,
                  budgeted: status!.budgeted,
                  progress: status!.progressFraction,
                  isOverBudget: status!.isOverBudget,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BudgetProgress extends StatelessWidget {
  const _BudgetProgress({
    required this.spent,
    required this.budgeted,
    required this.progress,
    required this.isOverBudget,
  });

  final Money spent;
  final Money budgeted;
  final double progress;
  final bool isOverBudget;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final clamped = progress.clamp(0.0, 1.0);
    final barColor = isOverBudget ? colors.destructive : colors.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.full),
          child: LinearProgressIndicator(
            minHeight: 6,
            value: clamped,
            backgroundColor: colors.border,
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
          ),
        ),
        const SizedBox(height: AppSpacing.s6),
        Text(
          l10n.planBudgetSpentOf(
            spent.amount.toString(),
            budgeted.amount.toString(),
            budgeted.currency,
          ),
          style: context.captionStyle,
        ),
      ],
    );
  }
}

Future<void> _showBudgetEditSheet(
  BuildContext context,
  WidgetRef ref,
  BudgetRow row,
) async {
  await showAppFormSheet<void>(
    context: context,
    builder: (ctx) => _BudgetEditSheet(row: row, ref: ref),
  );
}

class _BudgetEditSheet extends StatefulWidget {
  const _BudgetEditSheet({required this.row, required this.ref});

  final BudgetRow row;
  final WidgetRef ref;

  @override
  State<_BudgetEditSheet> createState() => _BudgetEditSheetState();
}

class _BudgetEditSheetState extends State<_BudgetEditSheet> {
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.row.amount.toString(),
    );
    _noteController = TextEditingController(text: widget.row.note ?? '');
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppSheet(
      title: l10n.planBudgetEditTitle,
      subtitle: widget.row.categoryId,
      footer: AppSheetFooter(
        submitLabel: l10n.commonSave,
        cancelLabel: l10n.commonCancel,
        busy: _saving,
        onSubmit: _save,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FTextField(
            control: FTextFieldControl.managed(controller: _amountController),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            label: Text(l10n.planBudgetAmountLabel(widget.row.currency)),
          ),
          const SizedBox(height: AppSpacing.s12),
          FTextField(
            control: FTextFieldControl.managed(controller: _noteController),
            label: Text(l10n.planBudgetNoteLabel),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.s12),
            AppStatusBanner(kind: AppStatusKind.error, message: _error!),
          ],
        ],
      ),
    );
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final amount = Decimal.tryParse(_amountController.text.trim());
    if (amount == null || amount < Decimal.zero) {
      setState(() => _error = l10n.planBudgetInvalidAmount);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = await widget.ref.read(budgetRepositoryProvider.future);
      final note = _noteController.text.trim();
      await repo.updateAmount(
        id: widget.row.id,
        amount: amount,
        note: note.isEmpty ? null : note,
        clearNote: note.isEmpty,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = userSafeErrorMessage(context, e);
        });
      }
    }
  }
}

Map<String, Decimal> _totalsByCurrency(List<BudgetRow> rows) {
  final totalsByCurrency = <String, Decimal>{};
  for (final row in rows) {
    totalsByCurrency.update(
      row.currency.toUpperCase(),
      (acc) => acc + row.amount,
      ifAbsent: () => row.amount,
    );
  }
  return totalsByCurrency;
}

/// Encode the UTC calendar month as `YYYY-MM` — same key shape the
/// repository writes so the family-provider lookup is identity.
String _currentMonthKey(DateTime now) {
  final utc = now.toUtc();
  final m = utc.month.toString().padLeft(2, '0');
  return '${utc.year}-$m';
}
