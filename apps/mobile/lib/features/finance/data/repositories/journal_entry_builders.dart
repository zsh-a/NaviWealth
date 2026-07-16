import 'package:decimal/decimal.dart';

import 'package:naviwealth/features/finance/domain/models/posting.dart';
import 'journal_entry_repository.dart';

part 'journal_entry_builders_balances.dart';
part 'journal_entry_builders_cashflow.dart';
part 'journal_entry_builders_corporate_actions.dart';
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
    capitalizeFeeIntoLot: capitalizeFeeIntoLot,
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
  }) => sellLots(
    date: date,
    accountId: accountId,
    cashAccountId: cashAccountId,
    capitalGainsAccountId: capitalGainsAccountId,
    assetUnit: assetUnit,
    allocations: [
      SellLotAllocation(
        quantity: qty,
        costPerUnit: costPerUnit,
        costCurrency: costCurrency,
        lotId: lotId,
        acquiredOn: acquiredOn,
      ),
    ],
    price: price,
    quoteCurrency: quoteCurrency,
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

  /// Builds one sale whose asset leg is split across exact consumed lots.
  ///
  /// Cash, fee, tax, and capital-gains legs are emitted once for the whole
  /// transaction. Asset closing postings preserve [allocations] order.
  static JournalEntryBuild sellLots({
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
  }) => _buildSellLotsJournalEntry(
    date: date,
    accountId: accountId,
    cashAccountId: cashAccountId,
    capitalGainsAccountId: capitalGainsAccountId,
    assetUnit: assetUnit,
    allocations: allocations,
    price: price,
    quoteCurrency: quoteCurrency,
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
  }) => _buildTransferJournalEntry(
    date: date,
    fromAccountId: fromAccountId,
    toAccountId: toAccountId,
    amount: amount,
    currency: currency,
    toAmount: toAmount,
    toCurrency: toCurrency,
    narration: narration,
    payee: payee,
    settledOn: settledOn,
    tagIds: tagIds,
  );

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
  }) => _buildExpenseJournalEntry(
    date: date,
    expenseAccountId: expenseAccountId,
    fromAccountId: fromAccountId,
    amount: amount,
    currency: currency,
    payee: payee,
    narration: narration,
    settledOn: settledOn,
    tagIds: tagIds,
  );

  // ---------- Income ----------

  /// Generic cash income. The destination asset/cash account increases and
  /// the selected seeded `income:*` counter-account receives the balancing
  /// credit.
  static JournalEntryBuild income({
    required DateTime date,
    required String toAccountId,
    required String incomeAccountId,
    required Decimal amount,
    required String currency,
    String? payee,
    String? narration,
    DateTime? settledOn,
    List<String> tagIds = const <String>[],
  }) => _buildIncomeJournalEntry(
    date: date,
    toAccountId: toAccountId,
    incomeAccountId: incomeAccountId,
    amount: amount,
    currency: currency,
    payee: payee,
    narration: narration,
    settledOn: settledOn,
    tagIds: tagIds,
  );

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
  }) => _buildDividendJournalEntry(
    date: date,
    cashAccountId: cashAccountId,
    incomeAccountId: incomeAccountId,
    amount: amount,
    currency: currency,
    withholdingAmount: withholdingAmount,
    withholdingAccountId: withholdingAccountId,
    assetUnit: assetUnit,
    narration: narration,
    payee: payee,
    settledOn: settledOn,
    tagIds: tagIds,
  );

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
  }) => _buildDripJournalEntry(
    date: date,
    accountId: accountId,
    incomeAccountId: incomeAccountId,
    assetUnit: assetUnit,
    grossAmount: grossAmount,
    reinvestedQuantity: reinvestedQuantity,
    pricePerUnit: pricePerUnit,
    currency: currency,
    lotId: lotId,
    acquiredOn: acquiredOn,
    withholdingAmount: withholdingAmount,
    withholdingAccountId: withholdingAccountId,
    feeAmount: feeAmount,
    feeAccountId: feeAccountId,
    narration: narration,
    payee: payee,
    settledOn: settledOn,
    tagIds: tagIds,
  );

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
  }) => _buildLiabilityPaymentJournalEntry(
    date: date,
    liabilityAccountId: liabilityAccountId,
    fromAccountId: fromAccountId,
    interestExpenseAccountId: interestExpenseAccountId,
    principal: principal,
    interest: interest,
    currency: currency,
    amortizationEntryId: amortizationEntryId,
    narration: narration,
    payee: payee,
    settledOn: settledOn,
    tagIds: tagIds,
  );

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
  }) => _buildSplitJournalEntry(
    date: date,
    accountId: accountId,
    splitsEquityAccountId: splitsEquityAccountId,
    assetUnit: assetUnit,
    quoteCurrency: quoteCurrency,
    addedQuantity: addedQuantity,
    lotId: lotId,
    narration: narration,
    settledOn: settledOn,
    tagIds: tagIds,
  );

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
  }) => _buildLotAdjustmentJournalEntry(
    date: date,
    accountId: accountId,
    assetUnit: assetUnit,
    currency: currency,
    beforeQuantity: beforeQuantity,
    beforeCostPerUnit: beforeCostPerUnit,
    afterQuantity: afterQuantity,
    afterCostPerUnit: afterCostPerUnit,
    oldLotId: oldLotId,
    oldAcquiredOn: oldAcquiredOn,
    newLotId: newLotId,
    narration: narration,
    settledOn: settledOn,
    tagIds: tagIds,
  );

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
  }) => _buildOpeningBalanceJournalEntry(
    date: date,
    accountId: accountId,
    openingBalanceAccountId: openingBalanceAccountId,
    amount: amount,
    currency: currency,
    narration: narration,
    settledOn: settledOn,
    tagIds: tagIds,
  );

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
  }) => _buildValuationAdjustJournalEntry(
    date: date,
    accountId: accountId,
    equityAccountId: equityAccountId,
    assetUnit: assetUnit,
    quantity: quantity,
    newValuation: newValuation,
    currency: currency,
    narration: narration,
    settledOn: settledOn,
    tagIds: tagIds,
  );
}
