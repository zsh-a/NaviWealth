part of 'expense_report_sections.dart';

String _categoryLabel(
  AppLocalizations l10n,
  Account? account,
  String fallback,
) {
  return account == null ? fallback : localizedAccountName(l10n, account);
}
