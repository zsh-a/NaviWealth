part of 'expense_report_sections.dart';

String _categoryLabel(
  AppLocalizations l10n,
  Account? account,
  String fallback,
) {
  return account == null ? fallback : localizedAccountName(l10n, account);
}

String _breakdownLabel(
  AppLocalizations l10n,
  CategoryBreakdown breakdown,
  Map<String, Account> categoryById,
) {
  if (breakdown.expenseAccountId == kExpenseReportPieOtherId) {
    return l10n.expenseReportOtherCategories;
  }
  return _categoryLabel(
    l10n,
    categoryById[breakdown.expenseAccountId],
    l10n.expenseReportUncategorized,
  );
}
