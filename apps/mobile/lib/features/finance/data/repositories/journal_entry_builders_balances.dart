part of 'journal_entry_builders.dart';

JournalEntryBuild _buildOpeningBalanceJournalEntry({
  required DateTime date,
  required String accountId,
  required String openingBalanceAccountId,
  required Decimal amount,
  required String currency,
  String? narration,
  DateTime? settledOn,
  List<String> tagIds = const <String>[],
}) {
  if (amount == Decimal.zero) {
    throw ArgumentError.value(
      amount,
      'amount',
      'openingBalance must move a non-zero amount',
    );
  }
  return JournalEntryBuild(
    entry: JournalEntryDraft(
      date: date,
      settledOn: settledOn,
      narration: narration ?? 'Opening balance',
      tagIds: tagIds,
    ),
    postings: <PostingDraft>[
      PostingDraft(
        position: 0,
        accountId: accountId,
        units: amount,
        unit: currency,
      ),
      PostingDraft(
        position: 1,
        accountId: openingBalanceAccountId,
        units: -amount,
        unit: currency,
      ),
    ],
  );
}

JournalEntryBuild _buildValuationAdjustJournalEntry({
  required DateTime date,
  required String accountId,
  required String equityAccountId,
  required String assetUnit,
  required Decimal quantity,
  required Decimal newValuation,
  required String currency,
  String? narration,
  DateTime? settledOn,
  List<String> tagIds = const <String>[],
}) {
  if (newValuation <= Decimal.zero) {
    throw ArgumentError.value(newValuation, 'newValuation', 'must be > 0');
  }
  // Cash-class: units=1 with price=newValuation (absolute value).
  // Physical/security: units=quantity with price=newValuation (per-unit).
  final legUnits = quantity.sign == 0 ? Decimal.one : quantity;
  final totalValue = legUnits * newValuation;
  return JournalEntryBuild(
    entry: JournalEntryDraft(
      date: date,
      settledOn: settledOn,
      narration: narration ?? 'Valuation adjust',
      tagIds: _withAssetTag(tagIds, assetUnit),
    ),
    postings: <PostingDraft>[
      PostingDraft(
        position: 0,
        accountId: accountId,
        units: legUnits,
        unit: assetUnit,
        price: Price(perUnit: newValuation, currency: currency),
      ),
      PostingDraft(
        position: 1,
        accountId: equityAccountId,
        units: -totalValue,
        unit: currency,
      ),
    ],
  );
}
