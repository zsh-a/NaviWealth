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
  final fee = _normalizeOptionalAmount(feeAmount, feeAccountId, label: 'fee');
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
        perUnit: price,
        currency: quoteCurrency,
        lotId: lotId,
        acquiredOn: acquiredOn ?? date,
      ),
    ),
  ];
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

JournalEntryBuild _buildSellJournalEntry({
  required DateTime date,
  required String accountId,
  required String cashAccountId,
  required String capitalGainsAccountId,
  required String assetUnit,
  required Decimal qty,
  required Decimal price,
  required String quoteCurrency,
  required Decimal costPerUnit,
  required String costCurrency,
  String? lotId,
  DateTime? acquiredOn,
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
  if (costCurrency != quoteCurrency) {
    throw ArgumentError(
      'sell currently requires costCurrency ($costCurrency) to match '
      'quoteCurrency ($quoteCurrency); cross-currency lot closure '
      'is unsupported territory.',
    );
  }
  final fee = _normalizeOptionalAmount(feeAmount, feeAccountId, label: 'fee');
  final tax = _normalizeOptionalAmount(taxAmount, taxAccountId, label: 'tax');

  final grossProceeds = qty * price;
  final realisedPnl = (price - costPerUnit) * qty;

  final feeCcy = feeCurrency ?? quoteCurrency;
  final taxCcy = taxCurrency ?? quoteCurrency;

  // Cash leg sits net of fee/tax denominated in the quote currency.
  // Fee/tax in a foreign currency get their own outflow legs (same
  // shape as buy()).
  var cashIn = grossProceeds;
  if (fee != null && feeCcy == quoteCurrency) cashIn -= fee;
  if (tax != null && taxCcy == quoteCurrency) cashIn -= tax;

  final postings = <PostingDraft>[
    PostingDraft(
      position: 0,
      accountId: accountId,
      units: -qty,
      unit: assetUnit,
      // cost ties this leg back to the open lot for cost-basis
      // bookkeeping; price records the realised market price for
      // analytics + Beancount export.
      cost: Cost(
        perUnit: costPerUnit,
        currency: costCurrency,
        lotId: lotId,
        acquiredOn: acquiredOn,
      ),
      price: Price(perUnit: price, currency: quoteCurrency),
    ),
    // Income:CapitalGains leg. Negative units = credit to income.
    PostingDraft(
      position: 1,
      accountId: capitalGainsAccountId,
      units: -realisedPnl,
      unit: quoteCurrency,
    ),
  ];
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
