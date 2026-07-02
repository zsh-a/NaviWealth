import 'package:naviwealth/features/finance/data/domain/account.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';

enum CashFlowKind {
  salary,
  dividend,
  interest,
  capitalGains,
  otherIncome,
  expense,
  transfer,
  opening,
  other,
}

CashFlowKind cashFlowKindForCounterAccount(Account account) {
  switch (account.category) {
    case AccountSide.income:
      return _incomeKind(account);
    case AccountSide.expense:
      return CashFlowKind.expense;
    case AccountSide.equity:
      return _isOpeningAccount(account)
          ? CashFlowKind.opening
          : CashFlowKind.other;
    case AccountSide.asset:
    case AccountSide.liability:
      return CashFlowKind.transfer;
  }
}

CashFlowKind _incomeKind(Account account) {
  final token = _normalise(account.name);
  final id = account.id.toLowerCase();
  if (id.contains(':income:salary') || token.contains('salary')) {
    return CashFlowKind.salary;
  }
  if (id.contains(':income:dividend') || token.contains('dividend')) {
    return CashFlowKind.dividend;
  }
  if (id.contains(':income:interest') || token.contains('interest')) {
    return CashFlowKind.interest;
  }
  if (id.contains(':income:capitalgains') ||
      token.contains('capitalgain') ||
      token.contains('capitalgains')) {
    return CashFlowKind.capitalGains;
  }
  return CashFlowKind.otherIncome;
}

bool _isOpeningAccount(Account account) {
  final token = _normalise(account.name);
  final id = account.id.toLowerCase();
  return id.contains(':equity:openingbalance') ||
      token.contains('openingbalance');
}

String _normalise(String input) {
  final buffer = StringBuffer();
  for (final code in input.codeUnits) {
    final lower = code >= 0x41 && code <= 0x5a ? code + 0x20 : code;
    if (lower >= 0x61 && lower <= 0x7a) {
      buffer.writeCharCode(lower);
    }
  }
  return buffer.toString();
}
