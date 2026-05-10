import '../../../data/domain/enums.dart';
import '../../../l10n/gen/app_localizations.dart';

/// Localised label for the wealth-container [AccountCategory] the user
/// picks when creating an account. Reads as a noun phrase so it slots
/// directly into account row subtitles ("Cash · CNY", "Brokerage ·
/// USD"). The semantic categories (cash / bank / broker / crypto /
/// credit / loan / asset / liability) replace the legacy carrier-shape
/// strings and exclude the old `realEstate` / `vehicle` / `other`
/// sub-types — those collapse into "Asset".
String accountCategoryLabel(AppLocalizations l10n, AccountCategory c) {
  return switch (c) {
    AccountCategory.cash => l10n.accountCategoryCash,
    AccountCategory.bank => l10n.accountCategoryBank,
    AccountCategory.broker => l10n.accountCategoryBroker,
    AccountCategory.crypto => l10n.accountCategoryCrypto,
    AccountCategory.credit => l10n.accountCategoryCredit,
    AccountCategory.loan => l10n.accountCategoryLoan,
    AccountCategory.asset => l10n.accountCategoryAsset,
    AccountCategory.liability => l10n.accountCategoryLiability,
  };
}

/// Localised label for the accounting [AccountSide] (debit / credit
/// classification). Should never be shown in primary UI — it's
/// auto-derived from [AccountCategory] via [accountSideForCategory] —
/// but it is surfaced in some debug / ledger views for transparency.
String accountSideLabel(AppLocalizations l10n, AccountSide s) {
  return switch (s) {
    AccountSide.asset => l10n.accountSideAsset,
    AccountSide.liability => l10n.accountSideLiability,
    AccountSide.income => l10n.accountSideIncome,
    AccountSide.expense => l10n.accountSideExpense,
    AccountSide.equity => l10n.accountSideEquity,
  };
}
