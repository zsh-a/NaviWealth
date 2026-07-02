part of 'journal_entry_repository.dart';

// ---------- Companion / op helpers ----------

JournalEntriesCompanion _journalCompanion(JournalEntry entry) {
  return JournalEntriesCompanion.insert(
    id: entry.id,
    date: entry.date,
    settledOn: Value(entry.settledOn),
    narration: entry.narration,
    payee: Value(entry.payee),
    flag: Value(entry.flag),
    tagIdsJson: Value(jsonEncode(entry.tagIds)),
    ownerUserId: entry.sync.ownerUserId,
    updatedAt: entry.sync.updatedAt,
    updatedByDevice: entry.sync.updatedByDevice,
    hlc: entry.sync.hlc,
  );
}

PostingsCompanion _postingCompanion(Posting p) {
  return PostingsCompanion.insert(
    id: p.id,
    journalEntryId: p.journalEntryId,
    position: p.position,
    accountId: p.accountId,
    units: p.units,
    unit: p.unit,
    costPerUnit: Value(p.cost?.perUnit),
    costCurrency: Value(p.cost?.currency),
    costLotId: Value(p.cost?.lotId),
    costAcquiredOn: Value(p.cost?.acquiredOn),
    pricePerUnit: Value(p.price?.perUnit),
    priceCurrency: Value(p.price?.currency),
    ownerUserId: p.sync.ownerUserId,
    updatedAt: p.sync.updatedAt,
    updatedByDevice: p.sync.updatedByDevice,
    hlc: p.sync.hlc,
  );
}

// ---------- Row -> domain ----------

JournalEntry _journalToDomain(JournalEntryRow row) {
  final tagIds = (jsonDecode(row.tagIdsJson) as List<dynamic>).cast<String>();
  return JournalEntry(
    id: row.id,
    date: row.date,
    settledOn: row.settledOn,
    narration: row.narration,
    payee: row.payee,
    tagIds: List.unmodifiable(tagIds),
    flag: row.flag,
    sync: SyncMeta(
      ownerUserId: row.ownerUserId,
      updatedAt: row.updatedAt,
      updatedByDevice: row.updatedByDevice,
      hlc: row.hlc,
      deletedAt: row.deletedAt,
    ),
  );
}

Posting _postingToDomain(PostingRow row) {
  Cost? cost;
  if (row.costPerUnit != null && row.costCurrency != null) {
    cost = Cost(
      perUnit: row.costPerUnit!,
      currency: row.costCurrency!,
      lotId: row.costLotId,
      acquiredOn: row.costAcquiredOn,
    );
  }
  Price? price;
  if (row.pricePerUnit != null && row.priceCurrency != null) {
    price = Price(perUnit: row.pricePerUnit!, currency: row.priceCurrency!);
  }
  return Posting(
    id: row.id,
    journalEntryId: row.journalEntryId,
    position: row.position,
    accountId: row.accountId,
    units: row.units,
    unit: row.unit,
    cost: cost,
    price: price,
    sync: SyncMeta(
      ownerUserId: row.ownerUserId,
      updatedAt: row.updatedAt,
      updatedByDevice: row.updatedByDevice,
      hlc: row.hlc,
      deletedAt: row.deletedAt,
    ),
  );
}

Expense? _postingToExpense(
  JournalEntryRow jeRow,
  PostingRow postingRow,
  List<PostingRow> siblingPostings,
) {
  final tagIds = (jsonDecode(jeRow.tagIdsJson) as List<dynamic>).cast<String>();
  final counterPosting = _expenseCounterPosting(
    expensePosting: postingRow,
    siblingPostings: siblingPostings,
  );
  return Expense(
    id: jeRow.id,
    expenseAccountId: postingRow.accountId,
    fromAccountId: counterPosting?.accountId,
    amount: postingRow.units.abs(),
    currency: postingRow.unit,
    tradeDate: jeRow.date,
    tags: tagIds,
    note: jeRow.narration,
    sync: SyncMeta(
      ownerUserId: jeRow.ownerUserId,
      updatedAt: jeRow.updatedAt,
      updatedByDevice: jeRow.updatedByDevice,
      hlc: jeRow.hlc,
      deletedAt: jeRow.deletedAt,
    ),
  );
}

PostingRow? _expenseCounterPosting({
  required PostingRow expensePosting,
  required List<PostingRow> siblingPostings,
}) {
  for (final posting in siblingPostings) {
    if (posting.accountId == expensePosting.accountId) continue;
    if (posting.unit != expensePosting.unit) continue;
    if (posting.units < Decimal.zero) return posting;
  }
  for (final posting in siblingPostings) {
    if (posting.accountId == expensePosting.accountId) continue;
    if (posting.units < Decimal.zero) return posting;
  }
  for (final posting in siblingPostings) {
    if (posting.accountId != expensePosting.accountId) return posting;
  }
  return null;
}
