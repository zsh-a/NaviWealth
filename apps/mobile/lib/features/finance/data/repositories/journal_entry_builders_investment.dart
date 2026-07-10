part of 'journal_entry_builders.dart';

JournalEntryBuild _buildBuyJournalEntry({
  required DateTime date,
  required String accountId,
  required String cashAccountId,
  required String assetUnit,
  required Decimal qty,
  required Decimal price,
  required String quoteCurrency,
  String? lotId,
  DateTime? acquiredOn,
  bool capitalizeFeeIntoLot = false,
  Decimal? feeAmount,
  String? feeAccountId,
  String? feeCurrency,
  Decimal? taxAmount,
  String? taxAccountId,
  String? taxCurrency,
  String? narration,
  String? payee,
  DateTime? settledOn,
  List<String> tagIds = const <String>[],
}) {
  _assertPositive(qty, 'qty');
  _assertPositive(price, 'price');
  final fee = capitalizeFeeIntoLot
      ? _normalizeCapitalizedBuyFee(
          feeAmount,
          feeAccountId,
          feeCurrency,
          quoteCurrency,
        )
      : _normalizeOptionalAmount(feeAmount, feeAccountId, label: 'fee');
  final tax = _normalizeOptionalAmount(taxAmount, taxAccountId, label: 'tax');

  final notional = qty * price;
  final feeCcy = feeCurrency ?? quoteCurrency;
  final taxCcy = taxCurrency ?? quoteCurrency;

  // Cash leg amount only sums fee/tax that are denominated in the
  // quote currency. Fee/tax in a different currency get their own
  // separate cash impact via the explicit posting; the FX fold in
  // the invariant validator keeps the JE balanced regardless.
  var cashOut = notional;
  if (fee != null && feeCcy == quoteCurrency) cashOut += fee;
  if (tax != null && taxCcy == quoteCurrency) cashOut += tax;

  final postings = <PostingDraft>[
    PostingDraft(
      position: 0,
      accountId: accountId,
      units: qty,
      unit: assetUnit,
      cost: Cost(
        perUnit: capitalizeFeeIntoLot && fee != null
            ? ((notional + fee) / qty).toDecimal(scaleOnInfinitePrecision: 16)
            : price,
        currency: quoteCurrency,
        lotId: lotId,
        acquiredOn: acquiredOn ?? date,
      ),
    ),
  ];
  if (fee != null && !capitalizeFeeIntoLot) {
    postings.add(
      PostingDraft(
        position: postings.length,
        accountId: feeAccountId!,
        units: fee,
        unit: feeCcy,
      ),
    );
  }
  if (tax != null) {
    postings.add(
      PostingDraft(
        position: postings.length,
        accountId: taxAccountId!,
        units: tax,
        unit: taxCcy,
      ),
    );
  }
  postings.add(
    PostingDraft(
      position: postings.length,
      accountId: cashAccountId,
      units: -cashOut,
      unit: quoteCurrency,
    ),
  );

  // Fee/tax in a foreign currency hit the cash leg as a separate
  // outflow so the JE still balances after FX folding.
  if (fee != null && feeCcy != quoteCurrency) {
    postings.add(
      PostingDraft(
        position: postings.length,
        accountId: cashAccountId,
        units: -fee,
        unit: feeCcy,
      ),
    );
  }
  if (tax != null && taxCcy != quoteCurrency) {
    postings.add(
      PostingDraft(
        position: postings.length,
        accountId: cashAccountId,
        units: -tax,
        unit: taxCcy,
      ),
    );
  }

  return JournalEntryBuild(
    entry: JournalEntryDraft(
      date: date,
      settledOn: settledOn,
      narration: narration ?? _defaultBuyNarration(qty, assetUnit),
      payee: payee,
      tagIds: _withAssetTag(tagIds, assetUnit),
    ),
    postings: postings,
  );
}

Decimal? _normalizeCapitalizedBuyFee(
  Decimal? amount,
  String? accountId,
  String? currency,
  String quoteCurrency,
) {
  if (accountId != null) {
    throw ArgumentError.value(
      accountId,
      'feeAccountId',
      'must be null when the buy fee is capitalized into the lot',
    );
  }
  if (amount == null || amount == Decimal.zero) return null;
  if (amount < Decimal.zero) {
    throw ArgumentError.value(amount, 'feeAmount', 'must be >= 0');
  }
  final effectiveCurrency = currency ?? quoteCurrency;
  if (effectiveCurrency != quoteCurrency) {
    throw ArgumentError.value(
      effectiveCurrency,
      'feeCurrency',
      'must match quoteCurrency when the buy fee is capitalized',
    );
  }
  return amount;
}

JournalEntryBuild _buildSellLotsJournalEntry({
  required DateTime date,
  required String accountId,
  required String cashAccountId,
  required String capitalGainsAccountId,
  required String assetUnit,
  required List<SellLotAllocation> allocations,
  required Decimal price,
  required String quoteCurrency,
  Decimal? feeAmount,
  String? feeAccountId,
  String? feeCurrency,
  Decimal? taxAmount,
  String? taxAccountId,
  String? taxCurrency,
  String? narration,
  String? payee,
  DateTime? settledOn,
  List<String> tagIds = const <String>[],
}) {
  if (allocations.isEmpty) {
    throw ArgumentError.value(allocations, 'allocations', 'must not be empty');
  }
  _assertPositive(price, 'price');
  for (var index = 0; index < allocations.length; index++) {
    final allocation = allocations[index];
    _assertPositive(allocation.quantity, 'allocations[$index].quantity');
    if (allocation.costPerUnit < Decimal.zero) {
      throw ArgumentError.value(
        allocation.costPerUnit,
        'allocations[$index].costPerUnit',
        'must be >= 0',
      );
    }
    if (allocation.costCurrency != quoteCurrency) {
      throw ArgumentError(
        'sell currently requires costCurrency '
        '(${allocation.costCurrency}) to match quoteCurrency '
        '($quoteCurrency); cross-currency lot closure is unsupported.',
      );
    }
  }
  final fee = _normalizeOptionalAmount(feeAmount, feeAccountId, label: 'fee');
  final tax = _normalizeOptionalAmount(taxAmount, taxAccountId, label: 'tax');

  final qty = allocations.fold<Decimal>(
    Decimal.zero,
    (sum, allocation) => sum + allocation.quantity,
  );
  final grossProceeds = qty * price;
  final realisedPnl = allocations.fold<Decimal>(
    Decimal.zero,
    (sum, allocation) =>
        sum + (price - allocation.costPerUnit) * allocation.quantity,
  );

  final feeCcy = feeCurrency ?? quoteCurrency;
  final taxCcy = taxCurrency ?? quoteCurrency;

  // Cash leg sits net of fee/tax denominated in the quote currency.
  // Fee/tax in a foreign currency get their own outflow legs (same
  // shape as buy()).
  var cashIn = grossProceeds;
  if (fee != null && feeCcy == quoteCurrency) cashIn -= fee;
  if (tax != null && taxCcy == quoteCurrency) cashIn -= tax;

  final postings = <PostingDraft>[];
  for (final allocation in allocations) {
    postings.add(
      PostingDraft(
        position: postings.length,
        accountId: accountId,
        units: -allocation.quantity,
        unit: assetUnit,
        // Keep every consumed lot distinct for deterministic lot reduction.
        cost: Cost(
          perUnit: allocation.costPerUnit,
          currency: allocation.costCurrency,
          lotId: allocation.lotId,
          acquiredOn: allocation.acquiredOn,
        ),
        price: Price(perUnit: price, currency: quoteCurrency),
      ),
    );
  }
  // Income:CapitalGains leg. Negative units = credit to income.
  postings.add(
    PostingDraft(
      position: postings.length,
      accountId: capitalGainsAccountId,
      units: -realisedPnl,
      unit: quoteCurrency,
    ),
  );
  if (fee != null) {
    postings.add(
      PostingDraft(
        position: postings.length,
        accountId: feeAccountId!,
        units: fee,
        unit: feeCcy,
      ),
    );
  }
  if (tax != null) {
    postings.add(
      PostingDraft(
        position: postings.length,
        accountId: taxAccountId!,
        units: tax,
        unit: taxCcy,
      ),
    );
  }
  postings.add(
    PostingDraft(
      position: postings.length,
      accountId: cashAccountId,
      units: cashIn,
      unit: quoteCurrency,
    ),
  );
  if (fee != null && feeCcy != quoteCurrency) {
    postings.add(
      PostingDraft(
        position: postings.length,
        accountId: cashAccountId,
        units: -fee,
        unit: feeCcy,
      ),
    );
  }
  if (tax != null && taxCcy != quoteCurrency) {
    postings.add(
      PostingDraft(
        position: postings.length,
        accountId: cashAccountId,
        units: -tax,
        unit: taxCcy,
      ),
    );
  }

  return JournalEntryBuild(
    entry: JournalEntryDraft(
      date: date,
      settledOn: settledOn,
      narration: narration ?? _defaultSellNarration(qty, assetUnit),
      payee: payee,
      tagIds: _withAssetTag(tagIds, assetUnit),
    ),
    postings: postings,
  );
}
