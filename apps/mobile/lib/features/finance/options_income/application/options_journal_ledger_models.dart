part of 'options_journal_ledger_service.dart';

enum _OptionsLedgerLeg {
  premium,
  closeDebit,
  assignment,
  leapsOpen,
  leapsClose,
}

class _CostBasis {
  const _CostBasis({
    required this.costPerUnit,
    required this.currency,
    this.lotId,
    this.acquiredOn,
  });

  final Decimal costPerUnit;
  final String currency;
  final String? lotId;
  final DateTime? acquiredOn;
}
