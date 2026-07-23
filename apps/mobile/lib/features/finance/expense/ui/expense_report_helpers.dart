part of 'expense_report_sections.dart';

String _categoryLabel(
  AppLocalizations l10n,
  ExpenseCategory? category,
  String fallback,
) {
  return category == null
      ? fallback
      : localizedExpenseCategoryName(l10n, category);
}

String _breakdownLabel(
  AppLocalizations l10n,
  CategoryBreakdown breakdown,
  Map<String, ExpenseCategory> categoryById,
) {
  if (breakdown.categoryId == kExpenseReportPieOtherId) {
    return l10n.expenseReportOtherCategories;
  }
  return _categoryLabel(
    l10n,
    categoryById[breakdown.categoryId],
    l10n.expenseReportUncategorized,
  );
}
