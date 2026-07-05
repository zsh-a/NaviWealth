import 'package:decimal/decimal.dart';

class CashFlowLedgerEntry {
  const CashFlowLedgerEntry({
    required this.id,
    required this.date,
    required this.postings,
    this.tagIds = const <String>[],
  });

  final String id;
  final DateTime date;
  final List<CashFlowLedgerPosting> postings;
  final List<String> tagIds;
}

class CashFlowLedgerPosting {
  const CashFlowLedgerPosting({
    required this.accountId,
    required this.units,
    required this.unit,
  });

  final String accountId;
  final Decimal units;
  final String unit;
}
