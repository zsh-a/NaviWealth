import 'package:decimal/decimal.dart';

enum AccountReconciliationStatus { balanced, mismatch, overridden }

final class AccountReconciliation {
  const AccountReconciliation({
    required this.id,
    required this.periodMonth,
    required this.accountId,
    required this.unit,
    required this.statementBalance,
    required this.ledgerBalance,
    required this.difference,
    required this.status,
    required this.verifiedAt,
    this.note,
  });

  final String id;
  final String periodMonth;
  final String accountId;
  final String unit;
  final Decimal statementBalance;
  final Decimal ledgerBalance;
  final Decimal difference;
  final AccountReconciliationStatus status;
  final DateTime verifiedAt;
  final String? note;

  bool get isAccepted =>
      status == AccountReconciliationStatus.balanced ||
      status == AccountReconciliationStatus.overridden;
}

final class ReconciliationTarget {
  const ReconciliationTarget({
    required this.accountId,
    required this.accountName,
    required this.unit,
    required this.ledgerBalance,
    this.reconciliation,
  });

  final String accountId;
  final String accountName;
  final String unit;
  final Decimal ledgerBalance;
  final AccountReconciliation? reconciliation;

  bool get isAccepted => reconciliation?.isAccepted ?? false;
}

AccountReconciliationStatus reconciliationStatusFor(Decimal difference) =>
    difference == Decimal.zero
    ? AccountReconciliationStatus.balanced
    : AccountReconciliationStatus.mismatch;

DateTime reconciliationPeriodEndExclusive(String periodMonth) {
  final parts = periodMonth.split('-');
  if (parts.length != 2) throw FormatException('Invalid period: $periodMonth');
  final year = int.parse(parts[0]);
  final month = int.parse(parts[1]);
  if (month < 1 || month > 12) {
    throw FormatException('Invalid period: $periodMonth');
  }
  return DateTime.utc(year, month + 1);
}
