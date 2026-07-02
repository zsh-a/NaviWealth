part of 'journal_entry_builders.dart';

JournalEntryBuild _buildTransferJournalEntry({
  required DateTime date,
  required String fromAccountId,
  required String toAccountId,
  required Decimal amount,
  required String currency,
  Decimal? toAmount,
  String? toCurrency,
  String? narration,
  String? payee,
  DateTime? settledOn,
  List<String> tagIds = const <String>[],
}) {
  _assertPositive(amount, 'amount');
  if (toAmount != null) _assertPositive(toAmount, 'toAmount');

  final destCcy = toCurrency ?? currency;
  final destAmt = toAmount ?? amount;

  // Beancount-style price annotation: "1 unit of destCcy is worth N
  // of currency". `amount / destAmt` gives that exchange rate. We
  // only attach when the currencies actually differ - same-currency
  // transfers stay clean (no superfluous price row).
  Price? destPrice;
  if (destCcy != currency) {
    destPrice = Price(
      perUnit: (amount / destAmt).toDecimal(scaleOnInfinitePrecision: 12),
      currency: currency,
    );
  }

  return JournalEntryBuild(
    entry: JournalEntryDraft(
      date: date,
      settledOn: settledOn,
      narration: narration ?? 'Transfer',
      payee: payee,
      tagIds: tagIds,
    ),
    postings: <PostingDraft>[
      PostingDraft(
        position: 0,
        accountId: fromAccountId,
        units: -amount,
        unit: currency,
      ),
      PostingDraft(
        position: 1,
        accountId: toAccountId,
        units: destAmt,
        unit: destCcy,
        price: destPrice,
      ),
    ],
  );
}

JournalEntryBuild _buildExpenseJournalEntry({
  required DateTime date,
  required String expenseAccountId,
  required String fromAccountId,
  required Decimal amount,
  required String currency,
  String? payee,
  String? narration,
  DateTime? settledOn,
  List<String> tagIds = const <String>[],
}) {
  _assertPositive(amount, 'amount');
  return JournalEntryBuild(
    entry: JournalEntryDraft(
      date: date,
      settledOn: settledOn,
      narration: narration ?? 'Expense',
      payee: payee,
      tagIds: tagIds,
    ),
    postings: <PostingDraft>[
      PostingDraft(
        position: 0,
        accountId: expenseAccountId,
        units: amount,
        unit: currency,
      ),
      PostingDraft(
        position: 1,
        accountId: fromAccountId,
        units: -amount,
        unit: currency,
      ),
    ],
  );
}

JournalEntryBuild _buildDividendJournalEntry({
  required DateTime date,
  required String cashAccountId,
  required String incomeAccountId,
  required Decimal amount,
  required String currency,
  Decimal? withholdingAmount,
  String? withholdingAccountId,
  String? assetUnit,
  String? narration,
  String? payee,
  DateTime? settledOn,
  List<String> tagIds = const <String>[],
}) {
  _assertPositive(amount, 'amount');
  final withholding = _normalizeOptionalAmount(
    withholdingAmount,
    withholdingAccountId,
    label: 'withholding',
  );

  final cashIn = withholding == null ? amount : amount - withholding;

  final postings = <PostingDraft>[
    PostingDraft(
      position: 0,
      accountId: cashAccountId,
      units: cashIn,
      unit: currency,
    ),
    PostingDraft(
      position: 1,
      accountId: incomeAccountId,
      units: -amount,
      unit: currency,
    ),
  ];
  if (withholding != null) {
    postings.add(
      PostingDraft(
        position: postings.length,
        accountId: withholdingAccountId!,
        units: withholding,
        unit: currency,
      ),
    );
  }

  return JournalEntryBuild(
    entry: JournalEntryDraft(
      date: date,
      settledOn: settledOn,
      narration: narration ?? 'Dividend',
      payee: payee,
      tagIds: assetUnit == null ? tagIds : _withAssetTag(tagIds, assetUnit),
    ),
    postings: postings,
  );
}

JournalEntryBuild _buildDripJournalEntry({
  required DateTime date,
  required String accountId,
  required String incomeAccountId,
  required String assetUnit,
  required Decimal grossAmount,
  required Decimal reinvestedQuantity,
  required Decimal pricePerUnit,
  required String currency,
  String? lotId,
  DateTime? acquiredOn,
  Decimal? withholdingAmount,
  String? withholdingAccountId,
  Decimal? feeAmount,
  String? feeAccountId,
  String? narration,
  String? payee,
  DateTime? settledOn,
  List<String> tagIds = const <String>[],
}) {
  _assertPositive(grossAmount, 'grossAmount');
  _assertPositive(reinvestedQuantity, 'reinvestedQuantity');
  _assertPositive(pricePerUnit, 'pricePerUnit');
  final withholding = _normalizeOptionalAmount(
    withholdingAmount,
    withholdingAccountId,
    label: 'withholding',
  );
  final fee = _normalizeOptionalAmount(feeAmount, feeAccountId, label: 'fee');

  final postings = <PostingDraft>[
    PostingDraft(
      position: 0,
      accountId: accountId,
      units: reinvestedQuantity,
      unit: assetUnit,
      cost: Cost(
        perUnit: pricePerUnit,
        currency: currency,
        lotId: lotId,
        acquiredOn: acquiredOn ?? date,
      ),
    ),
    PostingDraft(
      position: 1,
      accountId: incomeAccountId,
      units: -grossAmount,
      unit: currency,
    ),
  ];
  if (withholding != null) {
    postings.add(
      PostingDraft(
        position: postings.length,
        accountId: withholdingAccountId!,
        units: withholding,
        unit: currency,
      ),
    );
  }
  if (fee != null) {
    postings.add(
      PostingDraft(
        position: postings.length,
        accountId: feeAccountId!,
        units: fee,
        unit: currency,
      ),
    );
  }

  return JournalEntryBuild(
    entry: JournalEntryDraft(
      date: date,
      settledOn: settledOn,
      narration: narration ?? 'Dividend reinvestment',
      payee: payee,
      tagIds: _withAssetTag(tagIds, assetUnit),
    ),
    postings: postings,
  );
}

JournalEntryBuild _buildLiabilityPaymentJournalEntry({
  required DateTime date,
  required String liabilityAccountId,
  required String fromAccountId,
  required String interestExpenseAccountId,
  required Decimal principal,
  required Decimal interest,
  required String currency,
  String? amortizationEntryId,
  String? narration,
  String? payee,
  DateTime? settledOn,
  List<String> tagIds = const <String>[],
}) {
  if (principal < Decimal.zero) {
    throw ArgumentError.value(principal, 'principal', 'must be \u2265 0');
  }
  if (interest < Decimal.zero) {
    throw ArgumentError.value(interest, 'interest', 'must be \u2265 0');
  }
  final total = principal + interest;
  if (total == Decimal.zero) {
    throw ArgumentError('liabilityPayment requires principal + interest > 0');
  }

  final postings = <PostingDraft>[
    // Liability debit (paying down): +units = reducing the negative
    // running balance toward zero. `kSign convention` section 6.
    PostingDraft(
      position: 0,
      accountId: liabilityAccountId,
      units: principal,
      unit: currency,
    ),
    // Cash outflow.
    PostingDraft(
      position: 2,
      accountId: fromAccountId,
      units: -total,
      unit: currency,
    ),
  ];
  if (interest > Decimal.zero) {
    postings.insert(
      1,
      PostingDraft(
        position: 1,
        accountId: interestExpenseAccountId,
        units: interest,
        unit: currency,
      ),
    );
  } else {
    // No interest leg - squash the cash leg's position so the list
    // is densely numbered.
    postings[1] = PostingDraft(
      position: 1,
      accountId: postings[1].accountId,
      units: postings[1].units,
      unit: postings[1].unit,
    );
  }

  final tags = amortizationEntryId == null
      ? tagIds
      : <String>[...tagIds, 'amort:$amortizationEntryId'];

  return JournalEntryBuild(
    entry: JournalEntryDraft(
      date: date,
      settledOn: settledOn,
      narration: narration ?? 'Liability payment',
      payee: payee,
      tagIds: tags,
    ),
    postings: postings,
  );
}
