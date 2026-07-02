import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';

import '../domain/cash_flow_ledger_entry.dart';

extension CashFlowLedgerEntryAdapter on JournalEntryWithPostings {
  CashFlowLedgerEntry toCashFlowLedgerEntry() {
    return CashFlowLedgerEntry(
      id: entry.id,
      date: entry.date,
      tagIds: entry.tagIds,
      postings: [
        for (final posting in postings)
          CashFlowLedgerPosting(
            accountId: posting.accountId,
            units: posting.units,
            unit: posting.unit,
          ),
      ],
    );
  }
}
