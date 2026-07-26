part of 'options_journal_ledger_service.dart';

Future<void> _upsertOptionsPremium({
  required JournalEntryRepository journalEntryRepo,
  required Future<String> Function() currentUserId,
  required TradeJournalEntry entry,
  required String cashAccountId,
  required OptionsLedgerNarrations narrations,
}) async {
  final amount = entry.grossEntryCredit - entry.effectiveFees;
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
    narration: narrations.premium(entry.optionSymbol),
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
  required OptionsLedgerNarrations narrations,
}) async {
  final id = _optionsLedgerEntryId(entry.id, _OptionsLedgerLeg.closeDebit);
  final debit = entry.grossExitDebit;
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
      narration: narrations.closeDebit(entry.optionSymbol),
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
  required OptionsLedgerNarrations narrations,
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
  final qty = Decimal.fromInt(
    (entry.contractSize ?? defaultContractSize) * entry.contractQuantity,
  );
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
        narration: narrations.putAssigned(entry.symbol),
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
        narration: narrations.callAssigned(entry.symbol),
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

Future<void> _upsertLeapsOpen({
  required JournalEntryRepository journalEntryRepo,
  required LeapsCallPosition position,
  required String brokerageAccountId,
  required String cashAccountId,
  required OptionsLedgerNarrations narrations,
}) async {
  final quantity = Decimal.fromInt(position.contractQuantity);
  final build = JournalEntryBuilders.buy(
    date: position.openedAt,
    accountId: brokerageAccountId,
    cashAccountId: cashAccountId,
    assetUnit: _leapsAssetUnit(position),
    qty: quantity,
    price: position.entryDebit,
    quoteCurrency: position.currency,
    lotId: _leapsLotId(position),
    acquiredOn: position.openedAt,
    capitalizeFeeIntoLot: true,
    feeAmount: position.fees,
    narration: narrations.leapsOpen(position.optionSymbol),
    tagIds: _leapsLedgerTags(position),
  );
  await _upsertOptionsLedgerBuild(
    journalEntryRepo: journalEntryRepo,
    build: _withLedgerId(
      build,
      _optionsLedgerEntryId(position.id, _OptionsLedgerLeg.leapsOpen),
    ),
  );
}

Future<void> _upsertLeapsClose({
  required JournalEntryRepository journalEntryRepo,
  required SecuritiesAssetRepository securitiesAssetRepo,
  required Future<String> Function() currentUserId,
  required LeapsCallPosition position,
  required String brokerageAccountId,
  required String cashAccountId,
  required OptionsLedgerNarrations narrations,
}) async {
  final id = _optionsLedgerEntryId(position.id, _OptionsLedgerLeg.leapsClose);
  if (position.status == LeapsCallStatus.open) {
    await _deleteOptionsLedgerIfPresent(
      journalEntryRepo: journalEntryRepo,
      id: id,
    );
    return;
  }

  final quantity = Decimal.fromInt(position.contractQuantity);
  final basisPerContract = (position.grossEntryCost / quantity).toDecimal(
    scaleOnInfinitePrecision: 16,
  );
  final closedAt = position.closedAt ?? position.expirationAt;
  final JournalEntryBuild build;
  if (position.status == LeapsCallStatus.closed &&
      position.exitCredit != null &&
      position.exitCredit! > Decimal.zero) {
    build = JournalEntryBuilders.sell(
      date: closedAt,
      accountId: brokerageAccountId,
      cashAccountId: cashAccountId,
      capitalGainsAccountId: AccountRepository.systemAccountIdForPath(
        'income:capitalGains',
        ownerUserId: await currentUserId(),
      ),
      assetUnit: _leapsAssetUnit(position),
      qty: quantity,
      price: position.exitCredit!,
      quoteCurrency: position.currency,
      costPerUnit: basisPerContract,
      costCurrency: position.currency,
      lotId: _leapsLotId(position),
      acquiredOn: position.openedAt,
      narration: narrations.leapsClose(position.optionSymbol),
      tagIds: _leapsLedgerTags(position),
    );
  } else if (position.status == LeapsCallStatus.exercised) {
    final underlying = await _ensureLeapsUnderlyingAsset(
      securitiesAssetRepo: securitiesAssetRepo,
      position: position,
    );
    final shares = Decimal.fromInt(
      position.contractQuantity * position.contractSize,
    );
    final strikeCash = position.strikePrice * shares;
    final shareCost = ((strikeCash + position.grossEntryCost) / shares)
        .toDecimal(scaleOnInfinitePrecision: 16);
    build = JournalEntryBuild(
      entry: JournalEntryDraft(
        date: closedAt,
        narration: narrations.leapsExercise(position.optionSymbol),
        tagIds: _leapsLedgerTags(position),
      ),
      postings: <PostingDraft>[
        PostingDraft(
          position: 0,
          accountId: brokerageAccountId,
          units: -quantity,
          unit: _leapsAssetUnit(position),
          cost: Cost(
            perUnit: basisPerContract,
            currency: position.currency,
            lotId: _leapsLotId(position),
            acquiredOn: position.openedAt,
          ),
        ),
        PostingDraft(
          position: 1,
          accountId: brokerageAccountId,
          units: shares,
          unit: underlying.id,
          cost: Cost(
            perUnit: shareCost,
            currency: position.currency,
            lotId: 'leaps:${position.id}:exercise',
            acquiredOn: closedAt,
          ),
        ),
        PostingDraft(
          position: 2,
          accountId: cashAccountId,
          units: -strikeCash,
          unit: position.currency,
        ),
      ],
    );
  } else {
    build = JournalEntryBuild(
      entry: JournalEntryDraft(
        date: closedAt,
        narration: narrations.leapsExpired(position.optionSymbol),
        tagIds: _leapsLedgerTags(position),
      ),
      postings: <PostingDraft>[
        PostingDraft(
          position: 0,
          accountId: brokerageAccountId,
          units: -quantity,
          unit: _leapsAssetUnit(position),
          cost: Cost(
            perUnit: basisPerContract,
            currency: position.currency,
            lotId: _leapsLotId(position),
            acquiredOn: position.openedAt,
          ),
        ),
        PostingDraft(
          position: 1,
          accountId: AccountRepository.systemAccountIdForPath(
            'income:capitalGains',
            ownerUserId: await currentUserId(),
          ),
          units: position.grossEntryCost,
          unit: position.currency,
        ),
      ],
    );
  }
  await _upsertOptionsLedgerBuild(
    journalEntryRepo: journalEntryRepo,
    build: _withLedgerId(build, id),
  );
}

JournalEntryBuild _withLedgerId(JournalEntryBuild build, String id) =>
    JournalEntryBuild(
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

String _leapsAssetUnit(LeapsCallPosition position) => 'option:${position.id}';

String _leapsLotId(LeapsCallPosition position) => 'leaps:${position.id}';

List<String> _leapsLedgerTags(LeapsCallPosition position) => <String>[
  'leaps:${position.id}',
  'option:${position.optionSymbol}',
  'underlying:${position.symbol}',
];

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
