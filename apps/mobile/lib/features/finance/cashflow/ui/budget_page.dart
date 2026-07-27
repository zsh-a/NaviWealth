import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/data/preferences/base_currency_preference.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/expense/data/expense_category_providers.dart';
import 'package:naviwealth/features/finance/expense/domain/expense_category.dart';
import 'package:naviwealth/features/finance/expense/ui/expense_category_l10n.dart';
import 'package:naviwealth/features/finance/expense/ui/expense_category_picker.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../domain/budget_summary.dart';

/// `/plan/budget` — month-scoped budget list.
///
/// Renders a selectable month's budgets, realised spend, remaining headroom,
/// and the complete create / edit / delete lifecycle for category caps.
class PlanBudgetPage extends ConsumerStatefulWidget {
  const PlanBudgetPage({super.key});

  @override
  ConsumerState<PlanBudgetPage> createState() => _PlanBudgetPageState();
}

class _PlanBudgetPageState extends ConsumerState<PlanBudgetPage> {
  late DateTime _month;
  bool _copying = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final monthKey = _monthKey(_month);
    final budgetsAsync = ref.watch(budgetsForMonthProvider(monthKey));
    final previousMonthKey = _monthKey(DateTime(_month.year, _month.month - 1));
    final previousRowsAsync = ref.watch(
      budgetsForMonthProvider(previousMonthKey),
    );
    final summaryAsync = ref.watch(monthlyBudgetSummaryProvider(monthKey));
    final categoriesAsync = ref.watch(allExpenseCategoriesProvider);
    final categories = categoriesAsync.value ?? const <ExpenseCategory>[];
    final rows = budgetsAsync.value ?? const <BudgetRow>[];
    final baseCurrency = ref.watch(baseCurrencyProvider);

    void openCreate() {
      _showBudgetFormSheet(
        context,
        ref,
        monthKey: monthKey,
        currency: baseCurrency,
        categories: categories,
        existingCategoryIds: {for (final row in rows) row.categoryId},
      );
    }

    return AppPageScaffold(
      title: l10n.planBudgetTitle,
      actions: [
        AppHeaderAction(
          semanticsLabel: l10n.planBudgetAddAction,
          icon: const Icon(FLucideIcons.plus),
          onPress:
              budgetsAsync.hasValue &&
                  categoriesAsync.hasValue &&
                  _availableBudgetCategories(categories, {
                    for (final row in rows) row.categoryId,
                  }).isNotEmpty
              ? openCreate
              : null,
        ),
        AppAdaptiveActionMenu(
          title: l10n.shellMoreActions,
          actions: [
            AppAdaptiveAction(
              icon: FLucideIcons.tags,
              title: l10n.expenseCategoriesManageTitle,
              onPress: () => context.push(FinanceRoutes.planExpenseCategories),
            ),
            AppAdaptiveAction(
              icon: FLucideIcons.chartPie,
              title: l10n.spendingTitle,
              onPress: () => context.push(FinanceRoutes.spending),
            ),
            if (!_copying &&
                previousRowsAsync.hasValue &&
                previousRowsAsync.requireValue.isNotEmpty)
              AppAdaptiveAction(
                icon: FLucideIcons.copy,
                title: l10n.planBudgetCopyPreviousAction,
                onPress: () => _copyPreviousMonth(
                  previousRowsAsync.requireValue,
                  rows,
                  monthKey,
                ),
              ),
          ],
          triggerBuilder: (context, openMenu, focusNode) => AppHeaderAction(
            semanticsLabel: l10n.shellMoreActions,
            icon: const Icon(FLucideIcons.ellipsis),
            focusNode: focusNode,
            onPress: openMenu,
          ),
        ),
      ],
      childPad: false,
      child: budgetsAsync.whenOrLoading(
        context: context,
        onRetry: () {
          ref.invalidate(budgetsForMonthProvider(monthKey));
          ref.invalidate(monthlyBudgetSummaryProvider(monthKey));
          ref.invalidate(allExpenseCategoriesProvider);
        },
        data: (rows) => _BudgetBody(
          monthKey: monthKey,
          rows: rows,
          categories: categories,
          categoriesLoading:
              categoriesAsync.isLoading && !categoriesAsync.hasValue,
          categoriesError: categoriesAsync.error,
          summaryError: summaryAsync.error,
          summary: summaryAsync.hasValue
              ? summaryAsync.requireValue.summary
              : null,
          mismatchedCount: summaryAsync.value?.mismatchedCount ?? 0,
          onPreviousMonth: () => _shiftMonth(-1),
          onNextMonth: () => _shiftMonth(1),
          onCreate: openCreate,
        ),
      ),
    );
  }

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
    });
  }

  Future<void> _copyPreviousMonth(
    List<BudgetRow> previousRows,
    List<BudgetRow> currentRows,
    String targetMonth,
  ) async {
    final l10n = AppLocalizations.of(context);
    final existing = {for (final row in currentRows) row.categoryId};
    final candidates = previousRows
        .where((row) => !existing.contains(row.categoryId))
        .toList(growable: false);
    if (candidates.isEmpty) return;
    setState(() => _copying = true);
    try {
      final repository = await ref.read(budgetRepositoryProvider.future);
      for (final row in candidates) {
        await repository.create(
          categoryId: row.categoryId,
          periodMonth: targetMonth,
          amount: row.amount,
          currency: row.currency,
          note: row.note,
        );
      }
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.success,
          l10n.planBudgetCopied(candidates.length),
        );
      }
    } catch (_) {
      if (mounted) {
        AppMessenger.show(context, ToastKind.error, l10n.commonSaveFailed);
      }
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }
}

class _BudgetBody extends ConsumerWidget {
  const _BudgetBody({
    required this.monthKey,
    required this.rows,
    required this.categories,
    required this.categoriesLoading,
    required this.categoriesError,
    required this.summaryError,
    required this.summary,
    required this.mismatchedCount,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onCreate,
  });

  final String monthKey;
  final List<BudgetRow> rows;
  final List<ExpenseCategory> categories;
  final bool categoriesLoading;
  final Object? categoriesError;
  final Object? summaryError;
  final MonthlyBudgetSummary? summary;
  final int mismatchedCount;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final statusByCategory = {
      for (final item in summary?.categories ?? const <CategoryBudgetStatus>[])
        item.categoryId: item,
    };
    final totalsByCurrency = _totalsByCurrency(rows);
    final categoryLabelById = _categoryLabelById(context, categories);
    final selectableCategories = _selectableExpenseCategories(categories);

    return Column(
      children: [
        _BudgetMonthSelector(
          monthKey: monthKey,
          onPrevious: onPreviousMonth,
          onNext: onNextMonth,
        ),
        Expanded(
          child: rows.isEmpty
              ? AppEmptyState(
                  icon: FLucideIcons.piggyBank,
                  title: l10n.planBudgetEmptyTitle,
                  message: categoriesError == null
                      ? l10n.planBudgetEmptyBody
                      : userSafeErrorMessage(
                          context,
                          categoriesError!,
                          operation: 'load expense categories',
                        ),
                  action: categoriesLoading || selectableCategories.isEmpty
                      ? null
                      : FButton(
                          onPress: onCreate,
                          child: Text(l10n.planBudgetEmptyCta),
                        ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.s16,
                    AppSpacing.s4,
                    AppSpacing.s16,
                    AppSpacing.s24,
                  ),
                  children: [
                    if (categoriesError != null || summaryError != null) ...[
                      AppStatusBanner(
                        kind: AppStatusKind.warning,
                        message: userSafeErrorMessage(
                          context,
                          summaryError ?? categoriesError!,
                          operation: summaryError != null
                              ? 'load budget summary'
                              : 'load expense categories',
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s12),
                    ],
                    if (mismatchedCount > 0) ...[
                      SoftCard.flat(
                        padding: const EdgeInsets.all(AppSpacing.s12),
                        child: Text(
                          l10n.planBudgetCurrencyMismatch(mismatchedCount),
                          style: context.captionStyle.copyWith(
                            color: context.appTheme.status.warning.fg,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s12),
                    ],
                    _MonthHeaderCard(
                      monthKey: monthKey,
                      totalsByCurrency: totalsByCurrency,
                      summary: summary,
                      rowCount: rows.length,
                    ),
                    const SizedBox(height: AppSpacing.s16),
                    for (final row in rows) ...[
                      _BudgetTile(
                        row: row,
                        categoryLabel:
                            categoryLabelById[row.categoryId] ?? row.categoryId,
                        status: statusByCategory[row.categoryId],
                        onEdit: () => _showBudgetFormSheet(
                          context,
                          ref,
                          monthKey: monthKey,
                          currency: row.currency,
                          categories: categories,
                          existingCategoryIds: {
                            for (final item in rows) item.categoryId,
                          },
                          row: row,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s8),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _BudgetMonthSelector extends StatelessWidget {
  const _BudgetMonthSelector({
    required this.monthKey,
    required this.onPrevious,
    required this.onNext,
  });

  final String monthKey;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s8,
        AppSpacing.s16,
        AppSpacing.s8,
      ),
      child: Row(
        children: [
          AppIconButton(
            icon: FLucideIcons.chevronLeft,
            tooltip: l10n.planBudgetPreviousMonth,
            onPress: onPrevious,
          ),
          Expanded(
            child: Text(
              l10n.planBudgetMonthHeader(monthKey),
              textAlign: TextAlign.center,
              style: context.rowTitleStyle,
            ),
          ),
          AppIconButton(
            icon: FLucideIcons.chevronRight,
            tooltip: l10n.planBudgetNextMonth,
            onPress: onNext,
          ),
        ],
      ),
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
  const _BudgetTile({
    required this.row,
    required this.categoryLabel,
    required this.status,
    this.onEdit,
  });

  final BudgetRow row;
  final String categoryLabel;
  final CategoryBudgetStatus? status;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    final money = Money(row.amount, row.currency);
    final remaining = status?.remaining;
    return SoftCard.flat(
      child: AppTappable(
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
                        Text(categoryLabel),
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

Future<void> _showBudgetFormSheet(
  BuildContext context,
  WidgetRef ref, {
  required String monthKey,
  required String currency,
  required List<ExpenseCategory> categories,
  required Set<String> existingCategoryIds,
  BudgetRow? row,
}) async {
  await showAppFormSheet<void>(
    context: context,
    builder: (ctx) => _BudgetFormSheet(
      ref: ref,
      monthKey: monthKey,
      currency: currency,
      categories: categories,
      existingCategoryIds: existingCategoryIds,
      row: row,
    ),
  );
}

class _BudgetFormSheet extends StatefulWidget {
  const _BudgetFormSheet({
    required this.ref,
    required this.monthKey,
    required this.currency,
    required this.categories,
    required this.existingCategoryIds,
    this.row,
  });

  final WidgetRef ref;
  final String monthKey;
  final String currency;
  final List<ExpenseCategory> categories;
  final Set<String> existingCategoryIds;
  final BudgetRow? row;

  @override
  State<_BudgetFormSheet> createState() => _BudgetFormSheetState();
}

class _BudgetFormSheetState extends State<_BudgetFormSheet> {
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  String? _categoryId;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.row != null;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.row?.amount.toString() ?? '',
    );
    _noteController = TextEditingController(text: widget.row?.note ?? '');
    _categoryId = widget.row?.categoryId;
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
    final categoryLabelById = _categoryLabelById(context, widget.categories);
    final pickerCategories = widget.categories
        .where(
          (category) =>
              !widget.existingCategoryIds.contains(category.id) ||
              category.id == _categoryId,
        )
        .toList(growable: false);
    final hasAvailableCategory = _availableBudgetCategories(
      widget.categories,
      widget.existingCategoryIds,
    ).isNotEmpty;
    return AppSheet(
      title: _editing ? l10n.planBudgetEditTitle : l10n.planBudgetCreateTitle,
      subtitle: _editing
          ? categoryLabelById[widget.row!.categoryId] ?? widget.row!.categoryId
          : l10n.planBudgetPeriodCurrency(widget.monthKey, widget.currency),
      actions: [
        if (_editing)
          AppIconButton(
            tooltip: l10n.planBudgetDeleteAction,
            icon: FLucideIcons.trash2,
            onPress: _saving ? null : _delete,
          ),
      ],
      footer: AppSheetFooter(
        submitLabel: l10n.commonSave,
        cancelLabel: l10n.commonCancel,
        busy: _saving,
        enabled: _editing || hasAvailableCategory,
        onSubmit: _save,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_editing && hasAvailableCategory) ...[
            ExpenseCategoryPicker(
              categories: pickerCategories,
              value: _categoryId,
              onChanged: (value) => setState(() {
                _categoryId = value;
                _error = null;
              }),
              label: l10n.planBudgetCategoryLabel,
              helperText: l10n.planBudgetCategoryHelper,
              leafOnly: true,
            ),
            const SizedBox(height: AppSpacing.s12),
          ] else if (!_editing) ...[
            AppStatusBanner(
              kind: AppStatusKind.info,
              message: l10n.planBudgetNoAvailableCategories,
            ),
            const SizedBox(height: AppSpacing.s12),
          ],
          FTextField(
            control: FTextFieldControl.managed(controller: _amountController),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            label: Text(l10n.planBudgetAmountLabel(widget.currency)),
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
    final categoryId = _categoryId;
    if (categoryId == null || categoryId.isEmpty) {
      setState(() => _error = l10n.planBudgetCategoryRequired);
      return;
    }
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
      final row = widget.row;
      if (row == null) {
        await repo.create(
          categoryId: categoryId,
          periodMonth: widget.monthKey,
          amount: amount,
          currency: widget.currency,
          note: note.isEmpty ? null : note,
        );
      } else {
        await repo.updateAmount(
          id: row.id,
          amount: amount,
          note: note.isEmpty ? null : note,
          clearNote: note.isEmpty,
        );
      }
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

  Future<void> _delete() async {
    final row = widget.row;
    if (row == null) return;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context: context,
      title: Text(l10n.planBudgetDeleteTitle),
      body: Text(l10n.planBudgetDeleteBody),
      confirmLabel: l10n.commonDelete,
      cancelLabel: l10n.commonCancel,
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = await widget.ref.read(budgetRepositoryProvider.future);
      await repo.delete(row.id);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = userSafeErrorMessage(
            context,
            error,
            operation: 'delete budget',
          );
        });
      }
    }
  }
}

Map<String, String> _categoryLabelById(
  BuildContext context,
  List<ExpenseCategory> categories,
) {
  final l10n = AppLocalizations.of(context);
  final byId = <String, ExpenseCategory>{
    for (final category in categories) category.id: category,
  };
  return {
    for (final category in categories)
      category.id: localizedExpenseCategoryPath(l10n, category, byId),
  };
}

List<ExpenseCategory> _selectableExpenseCategories(
  List<ExpenseCategory> categories,
) {
  final activeCategories = categories
      .where(
        (category) =>
            !category.archived &&
            category.sync.deletedAt == null &&
            !category.isMerged,
      )
      .toList(growable: false);
  final parentIds = <String>{
    for (final category in activeCategories)
      if (category.parentId != null) category.parentId!,
  };
  return activeCategories
      .where((category) => !parentIds.contains(category.id))
      .toList(growable: false);
}

List<ExpenseCategory> _availableBudgetCategories(
  List<ExpenseCategory> categories,
  Set<String> existingCategoryIds,
) => _selectableExpenseCategories(
  categories,
).where((category) => !existingCategoryIds.contains(category.id)).toList();

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

/// Encode the user's local calendar month as `YYYY-MM`.
String _monthKey(DateTime month) {
  final m = month.month.toString().padLeft(2, '0');
  return '${month.year}-$m';
}
