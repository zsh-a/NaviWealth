part of 'journal_entry_builders.dart';

/// Output of a [JournalEntryBuilders] call: a `(entry, postings)` pair
/// the caller hands straight to [JournalEntryRepository.create].
class JournalEntryBuild {
  const JournalEntryBuild({required this.entry, required this.postings});

  final JournalEntryDraft entry;
  final List<PostingDraft> postings;
}

/// One cost-basis parcel consumed by a securities sale.
///
/// Callers that close multiple lots must preserve one allocation per lot so
/// the ledger keeps the lot id, acquisition date, quantity, and cost basis on
/// separate asset postings.
final class SellLotAllocation {
  const SellLotAllocation({
    required this.quantity,
    required this.costPerUnit,
    required this.costCurrency,
    this.costToQuoteRate,
    this.lotId,
    this.acquiredOn,
  });

  final Decimal quantity;
  final Decimal costPerUnit;
  final String costCurrency;

  /// Sell-date conversion for one [costCurrency] unit into the sale quote
  /// currency. Required only when the lot and sale use different currencies.
  final Decimal? costToQuoteRate;
  final String? lotId;
  final DateTime? acquiredOn;
}
