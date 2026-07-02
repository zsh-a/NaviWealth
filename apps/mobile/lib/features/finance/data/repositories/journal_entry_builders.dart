import 'package:decimal/decimal.dart';

import 'package:naviwealth/features/finance/domain/models/posting.dart';
import 'journal_entry_repository.dart';

part 'journal_entry_builders_helpers.dart';
part 'journal_entry_builders_investment.dart';
part 'journal_entry_builders_models.dart';

/// Pure construction layer that turns a high-level economic
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
/// Sign convention (restated here so the leg signs in this
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
  }) => _buildBuyJournalEntry(
    date: date,
    accountId: accountId,
    cashAccountId: cashAccountId,
    assetUnit: assetUnit,
    qty: qty,
    price: price,
    quoteCurrency: quoteCurrency,
    lotId: lotId,
    acquiredOn: acquiredOn,
    feeAmount: feeAmount,
    feeAccountId: feeAccountId,
    feeCurrency: feeCurrency,
    taxAmount: taxAmount,
    taxAccountId: taxAccountId,
    taxCurrency: taxCurrency,
    narration: narration,
    payee: payee,
    settledOn: settledOn,
    tagIds: tagIds,
  );

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
  }) => _buildSellJournalEntry(
    date: date,
    accountId: accountId,
    cashAccountId: cashAccountId,
    capitalGainsAccountId: capitalGainsAccountId,
    assetUnit: assetUnit,
    qty: qty,
    price: price,
    quoteCurrency: quoteCurrency,
    costPerUnit: costPerUnit,
    costCurrency: costCurrency,
    lotId: lotId,
    acquiredOn: acquiredOn,
    feeAmount: feeAmount,
    feeAccountId: feeAccountId,
    feeCurrency: feeCurrency,
    taxAmount: taxAmount,
    taxAccountId: taxAccountId,
    taxCurrency: taxCurrency,
    narration: narration,
    payee: payee,
    settledOn: settledOn,
    tagIds: tagIds,
  );

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
        tagIds: assetUnit == null ? tagIds : _withAssetTag(tagIds, assetUnit),
      ),
      postings: postings,
    );
  }

  /// Dividend Reinvestment Plan: gross dividend is credited to dividend
  /// income, withholding/fee land on expense accounts, and the remaining
  /// value opens a new asset lot. There is no cash leg because the net cash
  /// is immediately reinvested by the broker.
  static JournalEntryBuild drip({
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
      throw ArgumentError('liabilityPayment requires principal + interest > 0');
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

  /// Replaces one open lot with its post-corporate-action shape while
  /// preserving total cost basis. Used for stock dividends and forward /
  /// reverse splits where the economic value stays constant but the share
  /// count and per-unit cost change.
  static JournalEntryBuild lotAdjustment({
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
        'must be ≥ 0',
      );
    }
    if (afterCostPerUnit < Decimal.zero) {
      throw ArgumentError.value(
        afterCostPerUnit,
        'afterCostPerUnit',
        'must be ≥ 0',
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

  // ---------- Valuation adjust ----------

  /// Mark-to-market event: records a new valuation for an asset without
  /// any cash flow. Two flavours:
  ///
  ///   1. Cash-class (quantity == 0): bank deposits, 理财产品 — the
  ///      asset has no underlying unit, so [newValuation] is the
  ///      absolute balance. The leg carries `units: 1` with a price
  ///      annotation so the balance check can fold it.
  ///   2. Physical / security (quantity != 0): real estate, vehicles,
  ///      or a manual price override on a traded instrument —
  ///      [newValuation] is the per-unit price; [quantity] is the
  ///      holding size.
  ///
  /// In both cases the equity counter-account (`equity:adjustments`
  /// by convention) absorbs the offset so Σ = 0.
  static JournalEntryBuild valuationAdjust({
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
}
