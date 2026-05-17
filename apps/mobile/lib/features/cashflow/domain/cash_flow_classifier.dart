import 'package:decimal/decimal.dart';

import '../../../data/domain/account.dart';
import '../../../data/domain/enums.dart';
import '../../../data/repositories/journal_entry_repository.dart';
import 'cash_flow_event.dart';
import 'cash_flow_kind.dart';

typedef CashFlowBaseAmountConverter =
    Decimal? Function(Decimal amount, String currency, DateTime date);

CashFlowEvent? classifyCashFlowEvent(
  JournalEntryWithPostings entryWithPostings, {
  required Account? Function(String accountId) resolveAccount,
  CashFlowBaseAmountConverter? convertToBaseAmount,
}) {
  final postings = entryWithPostings.postings;
  if (postings.isEmpty) return null;

  final accounts = <String, Account>{};
  final sides = <AccountSide>{};
  for (final posting in postings) {
    final account = resolveAccount(posting.accountId);
    if (account == null) return null;
    accounts[posting.accountId] = account;
    sides.add(account.category);
  }

  final assetCashLegs = postings.where((posting) {
    final account = accounts[posting.accountId]!;
    return account.category == AccountSide.asset &&
        _looksLikeFiatCode(posting.unit) &&
        posting.units != Decimal.zero;
  }).toList();
  if (assetCashLegs.isEmpty) return null;

  final counter = _counterAccount(accounts.values, sides);
  final kind = _kindFor(counter, sides);
  final primaryLeg = assetCashLegs.reduce((a, b) {
    return a.units.abs().compareTo(b.units.abs()) >= 0 ? a : b;
  });

  var signedAmount = Decimal.zero;
  for (final leg in assetCashLegs) {
    if (convertToBaseAmount == null) {
      if (leg.unit == primaryLeg.unit) signedAmount += leg.units;
      continue;
    }
    final converted = convertToBaseAmount(
      leg.units,
      leg.unit,
      entryWithPostings.entry.date,
    );
    if (converted == null) return null;
    signedAmount += converted;
  }
  if (convertToBaseAmount == null) {
    signedAmount = signedAmount == Decimal.zero
        ? primaryLeg.units
        : signedAmount;
  }

  return CashFlowEvent(
    journalEntryId: entryWithPostings.entry.id,
    date: entryWithPostings.entry.date,
    kind: kind,
    signedAmount: signedAmount,
    originalAmount: primaryLeg.units,
    currency: primaryLeg.unit.trim().toUpperCase(),
    accountId: primaryLeg.accountId,
    counterAccountSide: counter?.category ?? AccountSide.asset,
  );
}

Account? _counterAccount(Iterable<Account> accounts, Set<AccountSide> sides) {
  for (final side in const [
    AccountSide.income,
    AccountSide.expense,
    AccountSide.equity,
    AccountSide.liability,
  ]) {
    if (!sides.contains(side)) continue;
    return accounts.firstWhere((account) => account.category == side);
  }
  return null;
}

CashFlowKind _kindFor(Account? counter, Set<AccountSide> sides) {
  if (counter != null) return cashFlowKindForCounterAccount(counter);
  if (sides.length == 1 && sides.contains(AccountSide.asset)) {
    return CashFlowKind.transfer;
  }
  return CashFlowKind.other;
}

bool _looksLikeFiatCode(String unit) {
  final code = unit.trim();
  if (code.length < 3 || code.length > 8) return false;
  for (final c in code.codeUnits) {
    final upper = c >= 0x61 && c <= 0x7a ? c - 0x20 : c;
    if (upper < 0x41 || upper > 0x5a) return false;
  }
  return true;
}
