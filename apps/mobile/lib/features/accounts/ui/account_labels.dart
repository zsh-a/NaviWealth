import '../../../data/domain/enums.dart';
import '../../../l10n/gen/app_localizations.dart';

String accountTypeLabel(AppLocalizations l10n, AccountType t) {
  return switch (t) {
    AccountType.brokerage => l10n.accountTypeBrokerage,
    AccountType.bank => l10n.accountTypeBank,
    AccountType.cryptoWallet => l10n.accountTypeCryptoWallet,
    AccountType.realEstate => l10n.accountTypeRealEstate,
    AccountType.vehicle => l10n.accountTypeVehicle,
    AccountType.liability => l10n.accountTypeLiability,
    AccountType.cash => l10n.accountTypeCash,
    AccountType.other => l10n.accountTypeOther,
  };
}

String accountCategoryLabel(AppLocalizations l10n, AccountCategory c) {
  return switch (c) {
    AccountCategory.asset => l10n.accountCategoryAsset,
    AccountCategory.liability => l10n.accountCategoryLiability,
    AccountCategory.income => l10n.accountCategoryIncome,
    AccountCategory.expense => l10n.accountCategoryExpense,
    AccountCategory.equity => l10n.accountCategoryEquity,
  };
}
