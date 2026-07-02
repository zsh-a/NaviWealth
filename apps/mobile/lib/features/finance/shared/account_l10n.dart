import 'package:naviwealth/features/finance/data/domain/account.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

String localizedAccountName(AppLocalizations l10n, Account account) {
  final path = systemAccountPath(account);
  if (path == null) return account.name;
  return _localizedSystemAccountName(l10n, path) ?? account.name;
}

String localizedAccountPath(
  AppLocalizations l10n,
  Account account,
  Map<String, Account> byId, {
  bool dropSystemRoot = true,
}) {
  final chain = <Account>[];
  var depth = 0;
  var cursor = account;
  while (true) {
    chain.add(cursor);
    final parentId = cursor.parentId;
    if (parentId == null) break;
    final parent = byId[parentId];
    if (parent == null) break;
    if (depth > 64) break;
    cursor = parent;
    depth += 1;
  }

  final ordered = chain.reversed.toList();
  if (dropSystemRoot &&
      ordered.length > 1 &&
      systemAccountPath(ordered.first) != null) {
    ordered.removeAt(0);
  }
  return ordered.map((a) => localizedAccountName(l10n, a)).join(' › ');
}

String? systemAccountPath(Account account) =>
    systemAccountPathFromId(account.id);

String? systemAccountPathFromId(String id) {
  const prefix = 'system-account:';
  if (!id.startsWith(prefix)) return null;
  final scoped = id.substring(prefix.length);
  final separator = scoped.indexOf(':');
  if (separator < 0 || separator == scoped.length - 1) return null;
  return scoped.substring(separator + 1);
}

String? _localizedSystemAccountName(AppLocalizations l10n, String path) {
  return switch (path) {
    'income' => l10n.systemAccountIncome,
    'income:salary' => l10n.systemAccountIncomeSalary,
    'income:dividend' => l10n.systemAccountIncomeDividend,
    'income:interest' => l10n.systemAccountIncomeInterest,
    'income:capitalGains' => l10n.systemAccountIncomeCapitalGains,
    'income:other' => l10n.systemAccountIncomeOther,
    'expense' => l10n.systemAccountExpense,
    'expense:dining' => l10n.systemAccountExpenseDining,
    'expense:groceries' => l10n.systemAccountExpenseGroceries,
    'expense:coffee' => l10n.systemAccountExpenseCoffee,
    'expense:transport' => l10n.systemAccountExpenseTransport,
    'expense:rideHailing' => l10n.systemAccountExpenseRideHailing,
    'expense:housing' => l10n.systemAccountExpenseHousing,
    'expense:utilities' => l10n.systemAccountExpenseUtilities,
    'expense:household' => l10n.systemAccountExpenseHousehold,
    'expense:shopping' => l10n.systemAccountExpenseShopping,
    'expense:subscriptions' => l10n.systemAccountExpenseSubscriptions,
    'expense:entertainment' => l10n.systemAccountExpenseEntertainment,
    'expense:medical' => l10n.systemAccountExpenseMedical,
    'expense:fitness' => l10n.systemAccountExpenseFitness,
    'expense:education' => l10n.systemAccountExpenseEducation,
    'expense:travel' => l10n.systemAccountExpenseTravel,
    'expense:communication' => l10n.systemAccountExpenseCommunication,
    'expense:gift' => l10n.systemAccountExpenseGift,
    'expense:familySupport' => l10n.systemAccountExpenseFamilySupport,
    'expense:pets' => l10n.systemAccountExpensePets,
    'expense:trading' => l10n.systemAccountExpenseTrading,
    'expense:trading:fee' => l10n.systemAccountExpenseTradingFee,
    'expense:trading:tax' => l10n.systemAccountExpenseTradingTax,
    'expense:trading:interest' => l10n.systemAccountExpenseTradingInterest,
    'expense:tax' => l10n.systemAccountExpenseTax,
    'expense:tax:withholding' => l10n.systemAccountExpenseTaxWithholding,
    'expense:other' => l10n.systemAccountExpenseOther,
    'equity' => l10n.systemAccountEquity,
    'equity:openingBalance' => l10n.systemAccountEquityOpeningBalance,
    'equity:splits' => l10n.systemAccountEquitySplits,
    'equity:adjustments' => l10n.systemAccountEquityAdjustments,
    _ => null,
  };
}
