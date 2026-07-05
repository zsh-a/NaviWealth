part of 'journal_entry_builders.dart';

JournalEntryBuild _buildSplitJournalEntry({
  required DateTime date,
  required String accountId,
  required String splitsEquityAccountId,
  required String assetUnit,
  required String quoteCurrency,
  required Decimal addedQuantity,
  String? lotId,
  String? narration,
  DateTime? settledOn,
  List<String> tagIds = const <String>[],
}) {
  if (addedQuantity == Decimal.zero) {
    throw ArgumentError.value(
      addedQuantity,
      'addedQuantity',
      'split must move at least one share',
    );
  }
  final zero = Decimal.zero;
  final cost = Cost(
    perUnit: zero,
    currency: quoteCurrency,
    lotId: lotId,
    acquiredOn: date,
  );
  return JournalEntryBuild(
    entry: JournalEntryDraft(
      date: date,
      settledOn: settledOn,
      narration: narration ?? 'Split',
      tagIds: _withAssetTag(tagIds, assetUnit),
    ),
    postings: <PostingDraft>[
      PostingDraft(
        position: 0,
        accountId: accountId,
        units: addedQuantity,
        unit: assetUnit,
        cost: cost,
      ),
      PostingDraft(
        position: 1,
        accountId: splitsEquityAccountId,
        units: -addedQuantity,
        unit: assetUnit,
        cost: cost,
      ),
    ],
  );
}

JournalEntryBuild _buildLotAdjustmentJournalEntry({
  required DateTime date,
  required String accountId,
  required String assetUnit,
  required String currency,
  required Decimal beforeQuantity,
  required Decimal beforeCostPerUnit,
  required Decimal afterQuantity,
  required Decimal afterCostPerUnit,
  String? oldLotId,
  DateTime? oldAcquiredOn,
  String? newLotId,
  String? narration,
  DateTime? settledOn,
  List<String> tagIds = const <String>[],
}) {
  _assertPositive(beforeQuantity, 'beforeQuantity');
  _assertPositive(afterQuantity, 'afterQuantity');
  if (beforeCostPerUnit < Decimal.zero) {
    throw ArgumentError.value(
      beforeCostPerUnit,
      'beforeCostPerUnit',
      'must be \u2265 0',
    );
  }
  if (afterCostPerUnit < Decimal.zero) {
    throw ArgumentError.value(
      afterCostPerUnit,
      'afterCostPerUnit',
      'must be \u2265 0',
    );
  }
  return JournalEntryBuild(
    entry: JournalEntryDraft(
      date: date,
      settledOn: settledOn,
      narration: narration ?? 'Lot adjustment',
      tagIds: _withAssetTag(tagIds, assetUnit),
    ),
    postings: <PostingDraft>[
      PostingDraft(
        position: 0,
        accountId: accountId,
        units: -beforeQuantity,
        unit: assetUnit,
        cost: Cost(
          perUnit: beforeCostPerUnit,
          currency: currency,
          lotId: oldLotId,
          acquiredOn: oldAcquiredOn,
        ),
      ),
      PostingDraft(
        position: 1,
        accountId: accountId,
        units: afterQuantity,
        unit: assetUnit,
        cost: Cost(
          perUnit: afterCostPerUnit,
          currency: currency,
          lotId: newLotId,
          acquiredOn: date,
        ),
      ),
    ],
  );
}
