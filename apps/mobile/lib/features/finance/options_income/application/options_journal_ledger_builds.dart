part of 'options_journal_ledger_service.dart';

Future<void> _upsertOptionsPremium({
  required JournalEntryRepository journalEntryRepo,
  required Future<String> Function() currentUserId,
  required TradeJournalEntry entry,
  required String cashAccountId,
}) async {
  final amount = entry.entryCredit;
  final id = _optionsLedgerEntryId(entry.id, _OptionsLedgerLeg.premium);
  if (amount <= Decimal.zero) {
    await _deleteOptionsLedgerIfPresent(
      journalEntryRepo: journalEntryRepo,
      id: id,
    );
    return;
  }
  final uid = await currentUserId();
  final build = _cashIncomeBuild(
    id: id,
    date: entry.openedAt,
    cashAccountId: cashAccountId,
    incomeAccountId: AccountRepository.systemAccountIdForPath(
      'income:options',
      ownerUserId: uid,
    ),
    amount: amount,
    currency: entry.currency,
    narration: 'Options premium ${entry.optionSymbol}',
    tagIds: _optionsLedgerTags(entry),
  );
  await _upsertOptionsLedgerBuild(
    journalEntryRepo: journalEntryRepo,
    build: build,
  );
}

Future<void> _upsertOptionsCloseDebit({
  required JournalEntryRepository journalEntryRepo,
  required Future<String> Function() currentUserId,
  required TradeJournalEntry entry,
  required String cashAccountId,
}) async {
  final id = _optionsLedgerEntryId(entry.id, _OptionsLedgerLeg.closeDebit);
  final debit = entry.exitDebit;
  if (entry.status == TradeJournalStatus.open ||
      debit == null ||
      debit <= Decimal.zero) {
    await _deleteOptionsLedgerIfPresent(
      journalEntryRepo: journalEntryRepo,
      id: id,
    );
    return;
  }
  final uid = await currentUserId();
  final build = JournalEntryBuild(
    entry: JournalEntryDraft(
      id: id,
      date: entry.closedAt ?? DateTime.now().toUtc(),
      narration: 'Options close debit ${entry.optionSymbol}',
      tagIds: _optionsLedgerTags(entry),
    ),
    postings: <PostingDraft>[
      PostingDraft(
        position: 0,
        accountId: AccountRepository.systemAccountIdForPath(
          'income:options',
          ownerUserId: uid,
        ),
        units: debit,
        unit: entry.currency,
      ),
      PostingDraft(
        position: 1,
        accountId: cashAccountId,
        units: -debit,
        unit: entry.currency,
      ),
    ],
  );
  await _upsertOptionsLedgerBuild(
    journalEntryRepo: journalEntryRepo,
    build: build,
  );
}

Future<void> _upsertOptionsAssignment({
  required JournalEntryRepository journalEntryRepo,
  required SecuritiesAssetRepository securitiesAssetRepo,
  required PriceRepository priceRepo,
  required Future<HoldingService> Function() holdingService,
  required Future<String> Function() currentUserId,
  required TradeJournalEntry entry,
  required String cashAccountId,
  required int defaultContractSize,
}) async {
  final id = _optionsLedgerEntryId(entry.id, _OptionsLedgerLeg.assignment);
  if (entry.status != TradeJournalStatus.assigned) {
    await _deleteOptionsLedgerIfPresent(
      journalEntryRepo: journalEntryRepo,
      id: id,
    );
    return;
  }
  final brokerageAccountId = entry.brokerageAccountId;
  final strike = entry.strikePrice;
  if (brokerageAccountId == null ||
      brokerageAccountId.isEmpty ||
      strike == null ||
      strike <= Decimal.zero) {
    await _deleteOptionsLedgerIfPresent(
      journalEntryRepo: journalEntryRepo,
      id: id,
    );
    return;
  }

  final asset = await _ensureOptionsUnderlyingAsset(
    securitiesAssetRepo: securitiesAssetRepo,
    entry: entry,
  );
  final qty = Decimal.fromInt(entry.contractSize ?? defaultContractSize);
  final date = entry.closedAt ?? DateTime.now().toUtc();
  final JournalEntryBuild build;
  switch (entry.strategy) {
    case OptionsStrategyKind.cashSecuredPut:
      build = JournalEntryBuilders.buy(
        date: date,
        accountId: brokerageAccountId,
        cashAccountId: cashAccountId,
        assetUnit: asset.id,
        qty: qty,
        price: strike,
        quoteCurrency: entry.currency,
        lotId: 'options:${entry.id}:assignment',
        acquiredOn: date,
        narration: 'Put assigned ${entry.symbol}',
        tagIds: _optionsLedgerTags(entry),
      );
    case OptionsStrategyKind.coveredCall:
      final basis = await _costBasisForOptionsCalledAway(
        holdingService: holdingService,
        accountId: brokerageAccountId,
        assetId: asset.id,
        quantity: qty,
        fallbackPrice: strike,
        currency: entry.currency,
        asOf: date,
      );
      build = JournalEntryBuilders.sell(
        date: date,
        accountId: brokerageAccountId,
        cashAccountId: cashAccountId,
        capitalGainsAccountId: AccountRepository.systemAccountIdForPath(
          'income:capitalGains',
          ownerUserId: await currentUserId(),
        ),
        assetUnit: asset.id,
        qty: qty,
        price: strike,
        quoteCurrency: entry.currency,
        costPerUnit: basis.costPerUnit,
        costCurrency: basis.currency,
        lotId: basis.lotId,
        acquiredOn: basis.acquiredOn,
        narration: 'Covered call assigned ${entry.symbol}',
        tagIds: _optionsLedgerTags(entry),
      );
  }

  final forced = JournalEntryBuild(
    entry: JournalEntryDraft(
      id: id,
      date: build.entry.date,
      settledOn: build.entry.settledOn,
      narration: build.entry.narration,
      payee: build.entry.payee,
      tagIds: build.entry.tagIds,
      flag: build.entry.flag,
    ),
    postings: build.postings,
  );
  await _upsertOptionsLedgerBuild(
    journalEntryRepo: journalEntryRepo,
    build: forced,
  );
  await priceRepo.record(
    unit: asset.id,
    quoteCurrency: entry.currency,
    observedOn: date,
    perUnit: strike,
    source: 'options_assignment',
  );
}

JournalEntryBuild _cashIncomeBuild({
  required String id,
  required DateTime date,
  required String cashAccountId,
  required String incomeAccountId,
  required Decimal amount,
  required String currency,
  required String narration,
  required List<String> tagIds,
}) {
  return JournalEntryBuild(
    entry: JournalEntryDraft(
      id: id,
      date: date,
      narration: narration,
      tagIds: tagIds,
    ),
    postings: <PostingDraft>[
      PostingDraft(
        position: 0,
        accountId: cashAccountId,
        units: amount,
        unit: currency,
      ),
      PostingDraft(
        position: 1,
        accountId: incomeAccountId,
        units: -amount,
        unit: currency,
      ),
    ],
  );
}

Future<void> _upsertOptionsLedgerBuild({
  required JournalEntryRepository journalEntryRepo,
  required JournalEntryBuild build,
}) async {
  final id = build.entry.id;
  if (id == null) {
    throw StateError('options ledger mirror requires deterministic JE id');
  }
  final existing = await journalEntryRepo.getById(id);
  if (existing == null) {
    await journalEntryRepo.create(entry: build.entry, postings: build.postings);
    return;
  }
  await journalEntryRepo.replacePostings(
    id: id,
    entry: build.entry,
    postings: build.postings,
  );
}

Future<void> _removeOptionsLedgerMirrors({
  required JournalEntryRepository journalEntryRepo,
  required String entryId,
}) async {
  for (final leg in _OptionsLedgerLeg.values) {
    await _deleteOptionsLedgerIfPresent(
      journalEntryRepo: journalEntryRepo,
      id: _optionsLedgerEntryId(entryId, leg),
    );
  }
}

Future<void> _deleteOptionsLedgerIfPresent({
  required JournalEntryRepository journalEntryRepo,
  required String id,
}) async {
  final existing = await journalEntryRepo.getById(id);
  if (existing == null) return;
  await journalEntryRepo.softDelete(id);
}

List<String> _optionsLedgerTags(TradeJournalEntry entry) => <String>[
  'options:${entry.id}',
  'option:${entry.optionSymbol}',
];

String _optionsLedgerEntryId(String entryId, _OptionsLedgerLeg leg) =>
    'options:$entryId:${leg.name}';
