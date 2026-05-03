import 'package:decimal/decimal.dart';

import '../domain/posting.dart';
import 'journal_entry_repository.dart';

/// FIR-131 — pure construction layer that turns a high-level economic
/// event ("buy 100 AAPL @ $150 from cash") into the
/// `(JournalEntryDraft, List<PostingDraft>)` shape
/// [JournalEntryRepository.create] consumes.
///
/// Why a separate file:
///   * Builders are pure functions over the domain model; keeping them
///     out of the repo means tests don't need a Drift instance to assert
///     the leg layout for each event type.
///   * Forms / AI proposals / batch importers can all share the exact
///     same posting layout — there is exactly one place that knows what
///     "a buy" looks like.
///   * The repo's invariant guard runs on whatever the builder produced,
///     so if a builder ever drifts out of balance the
///     [JournalEntryUnbalancedException] surfaces it immediately.
///
/// Sign convention (FIR-128 §6, restated here so the leg signs in this
/// file are easy to verify):
///
/// | Account category | `units` sign on a *normal* event              |
/// |------------------|-----------------------------------------------|
/// | `asset`          | `+` on inflow, `-` on outflow                 |
/// | `expense`        | `+` when incurred                             |
/// | `liability`      | `+` when paying down, `-` when accruing       |
/// | `income`         | `-` when earned                               |
/// | `equity`         | `-` when contributed, `+` when withdrawn      |
///
/// All builder parameters expect **positive amounts** (the magnitude of
/// the transaction). The builder applies the correct sign per leg.
/// `split.addedQuantity` is the one exception — it stays signed because
/// it can be a bonus issue (`+`) or a reverse split (`-`).
class JournalEntryBuilders {
  const JournalEntryBuilders._();

  // ---------- Buy ----------

  /// `Assets:Brokerage:<asset>  +qty <unit>  {price quoteCurrency}`
  /// `Expenses:Trading:Fee      +feeAmount feeCurrency`            (optional)
  /// `Expenses:Trading:Tax      +taxAmount taxCurrency`            (optional)
  /// `Assets:Brokerage:Cash     -(qty*price + fee + tax) quoteCurrency`
  ///
  /// [qty] and [price] must be positive. The cash leg is computed in
  /// [quoteCurrency]; fee/tax may live in their own currencies (the
  /// invariant validator folds via [FxRateSource]).
  ///
  /// [lotId] / [acquiredOn] flow into the cost annotation on the asset
  /// leg so cost-basis selection (FIFO / LIFO / specific) can later
  /// match closing legs back to the right open lot.
  static JournalEntryBuild buy({
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
    final fee = _normalizeOptionalAmount(
      feeAmount,
      feeAccountId,
      label: 'fee',
    );
    final tax = _normalizeOptionalAmount(
      taxAmount,
      taxAccountId,
      label: 'tax',
    );

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

  // ---------- Sell ----------

  /// Closes [qty] units of an open lot. The realised PnL leg is
  /// emitted automatically and lands on [capitalGainsAccountId] (an
  /// `Income:CapitalGains` account in the seeded tree).
  ///
  /// The caller resolves the cost lot ahead of time and passes
  /// [costPerUnit] / [costCurrency] / [lotId] / [acquiredOn]; this
  /// builder does not run FIFO / LIFO selection itself — that lives in
  /// the holding service so it stays a single concern.
  ///
  /// Realised PnL is computed gross of fee/tax: the user-facing "I made
  /// $500 on this sale" headline matches what the income account
  /// accrues. Fees and taxes show up as their own expense legs.
  static JournalEntryBuild sell({
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
        'is FIR-132 territory.',
      );
    }
    final fee = _normalizeOptionalAmount(
      feeAmount,
      feeAccountId,
      label: 'fee',
    );
    final tax = _normalizeOptionalAmount(
      taxAmount,
      taxAccountId,
      label: 'tax',
    );

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

  // ---------- Transfer ----------

  /// Two-leg cash transfer between [fromAccountId] and [toAccountId].
  ///
  /// Same-currency transfers (the default) skip any FX annotation —
  /// both legs net to zero in the source unit.
  ///
  /// Cross-currency transfers pass [toAmount] + [toCurrency]. The
  /// builder attaches a `Price` annotation to the destination leg
  /// equal to `amount / toAmount` in [currency], so the invariant
  /// validator folds both legs to the *user's chosen rate* rather than
  /// whatever rate the [FxRateSource] happens to know on that day.
  /// That keeps the JE balanced at submit time even when the
  /// fx_rates table lags or disagrees, and it preserves the user's
  /// "I converted at X rate today" intent in the audit ledger.
  static JournalEntryBuild transfer({
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
    // only attach when the currencies actually differ — same-currency
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

  // ---------- Expense ----------

  /// Categorised expense: amount flows from a cash account into one of
  /// the `category=expense` accounts in the seeded tree.
  static JournalEntryBuild expense({
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

  // ---------- Dividend ----------

  /// Cash dividend received. Optional withholding tax leg lands on
  /// [withholdingAccountId] (typically `Expenses:Trading:Tax` or a
  /// dedicated `Liabilities:WithholdingTax` account).
  ///
  /// [assetUnit] is appended to `tagIds` as `asset:<unit>` so the
  /// dividend stays linked to the issuing security for analytics —
  /// without forcing a posting on the holding leg, since the dividend
  /// itself doesn't change the share count.
  static JournalEntryBuild dividend({
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
        tagIds: assetUnit == null
            ? tagIds
            : _withAssetTag(tagIds, assetUnit),
      ),
      postings: postings,
    );
  }

  // ---------- Liability payment ----------

  /// Three-leg payment: principal reduction + interest expense + cash
  /// outflow. [amortizationEntryId], when supplied, is recorded in the
  /// JE tag list as `amort:<id>` so liability detail pages can match
  /// the JE back to a specific schedule period without an extra column
  /// on `journal_entries`.
  static JournalEntryBuild liabilityPayment({
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
      throw ArgumentError.value(principal, 'principal', 'must be ≥ 0');
    }
    if (interest < Decimal.zero) {
      throw ArgumentError.value(interest, 'interest', 'must be ≥ 0');
    }
    final total = principal + interest;
    if (total == Decimal.zero) {
      throw ArgumentError(
        'liabilityPayment requires principal + interest > 0',
      );
    }

    final postings = <PostingDraft>[
      // Liability debit (paying down): +units = reducing the negative
      // running balance toward zero. `kSign convention §6`.
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
      // No interest leg — squash the cash leg's position so the list
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

  // ---------- Split ----------

  /// Stock split (or reverse-split). The new shares are matched against
  /// an `Equity:Splits` placeholder so the unit-level Σ stays at zero
  /// without requiring an FX rate for the asset.
  ///
  /// [addedQuantity] is signed: positive for a bonus issue (1:N split),
  /// negative for a reverse split. The cost annotation on both legs
  /// uses `0` in the quote currency so the base-currency weight is
  /// trivially zero.
  static JournalEntryBuild split({
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

  // ---------- Opening balance ----------

  /// Seeds an asset (or liability) with its starting balance against an
  /// `Equity:OpeningBalance` offset. Lets a user record "I had 10000
  /// CNY in this account before I started using NaviWealth" without
  /// having to fabricate a fake transfer.
  ///
  /// Pass [accountId] as the asset/liability target. [amount] is signed
  /// **as it should appear on the target account** (positive for
  /// asset balances, negative for liability balances per §6).
  static JournalEntryBuild openingBalance({
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

  // ---------- Helpers ----------

  static void _assertPositive(Decimal value, String name) {
    if (value <= Decimal.zero) {
      throw ArgumentError.value(value, name, 'must be > 0');
    }
  }

  /// Returns [amount] when both [amount] and [accountId] are present,
  /// `null` when both are absent, throws if exactly one is supplied.
  /// Keeps the per-event `feeAmount` / `feeAccountId` etc. couplings
  /// honest at the call site.
  static Decimal? _normalizeOptionalAmount(
    Decimal? amount,
    String? accountId, {
    required String label,
  }) {
    if (amount == null && accountId == null) return null;
    if (amount == null || accountId == null) {
      throw ArgumentError(
        '$label requires both amount and accountId, or neither',
      );
    }
    if (amount <= Decimal.zero) {
      throw ArgumentError.value(amount, '${label}Amount', 'must be > 0');
    }
    return amount;
  }

  static List<String> _withAssetTag(List<String> tagIds, String assetUnit) {
    final tag = 'asset:$assetUnit';
    if (tagIds.contains(tag)) return tagIds;
    return <String>[...tagIds, tag];
  }

  static String _defaultBuyNarration(Decimal qty, String unit) =>
      'Buy ${_trim(qty)} $unit';
  static String _defaultSellNarration(Decimal qty, String unit) =>
      'Sell ${_trim(qty)} $unit';
  static String _trim(Decimal v) {
    final s = v.toString();
    if (!s.contains('.')) return s;
    final trimmed = s.replaceFirst(RegExp(r'\.?0+$'), '');
    return trimmed.isEmpty ? '0' : trimmed;
  }
}

/// Output of a [JournalEntryBuilders] call: a `(entry, postings)` pair
/// the caller hands straight to [JournalEntryRepository.create].
class JournalEntryBuild {
  const JournalEntryBuild({required this.entry, required this.postings});

  final JournalEntryDraft entry;
  final List<PostingDraft> postings;
}
