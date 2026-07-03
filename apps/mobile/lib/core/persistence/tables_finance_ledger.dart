part of 'tables.dart';

@DataClassName('AccountRow')
class Accounts extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get type =>
      text().map(const EnumStringConverter(AccountCategory.values))();
  TextColumn get name => text()();
  TextColumn get currency => text().withLength(min: 3, max: 8)();
  TextColumn get institution => text().nullable()();
  TextColumn get accountNumber => text().nullable()();
  TextColumn get note => text().nullable()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();

  /// Accounting classification (asset / liability / income /
  /// expense / equity). See [AccountSide] for the why and the
  /// migration in `app_database.dart` (v8) for the back-fill rules.
  ///
  /// Defaulting to `asset` at the column level gives new accounts the
  /// conservative accounting class; creation code still sets the intended
  /// category explicitly.
  TextColumn get category => text()
      .map(const EnumStringConverter(AccountSide.values))
      .withDefault(Constant(AccountSide.asset.name))();

  /// Id of this account's parent in the Beancount-style tree.
  /// NULL on top-level rows; otherwise points at another row in this
  /// table. No FK at the SQL layer because sync-borne reorders need to
  /// land before the parent has caught up.
  TextColumn get parentId => text().nullable()();

  /// Material icon name for the account avatar.
  TextColumn get icon => text().nullable()();

  /// Color token (hex string or design-token id) for the account avatar.
  TextColumn get color => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Atomic economic event in the Beancount-style ledger. One
/// row per event; the postings that compose it live in the [Postings]
/// table and must satisfy the SUM(weight) = 0 invariant (see
/// `entryIsBalanced` in `domain/invariants.dart`).
@DataClassName('JournalEntryRow')
class JournalEntries extends Table with SyncableTable {
  TextColumn get id => text()();

  /// Trade date — when the event happened. Stored as a regular Drift
  /// DateTime (seconds-since-epoch INTEGER) so range queries by date
  /// hit the index rather than triggering text-comparison sorts.
  DateTimeColumn get date => dateTime()();

  /// Settlement date (broker T+2 etc.). NULL when same-day.
  DateTimeColumn get settledOn => dateTime().nullable()();

  /// Free-form description. Required and non-empty by convention so the
  /// timeline always has something to render; an empty string is
  /// reserved for the synthetic padding rows ([EntryFlag.padding]).
  TextColumn get narration => text()();

  /// Optional counter-party (merchant / payer name). Not indexed —
  /// payee-driven views aggregate inside Dart since the surface is small.
  TextColumn get payee => text().nullable()();

  /// Beancount lifecycle flag. See `EntryFlag` in
  /// `domain/journal_entry.dart` for the value semantics.
  TextColumn get flag => text()
      .map(const EnumStringConverter(EntryFlag.values))
      .withDefault(Constant(EntryFlag.confirmed.name))();

  /// JSON-encoded list of `tags.id` strings. Denormalised onto the JE so
  /// reading entries doesn't require a join through `tag_links`. The
  /// canonical writer / reader are [JournalEntryRow] code paths only.
  TextColumn get tagIdsJson => text().withDefault(const Constant('[]'))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// One leg of a [JournalEntries] row. The composite invariant
/// `SUM(units × weight) GROUP BY journal_entry_id ≈ 0` (after FX folding
/// to base) is enforced by the application layer at write time (see
/// `entryIsBalanced`).
@DataClassName('PostingRow')
class Postings extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get journalEntryId => text()();

  /// 0-based render order within the parent JE. Stored explicitly so a
  /// re-order is a single-column LWW update rather than a JE-wide
  /// rewrite that touches every leg.
  IntColumn get position => integer()();

  TextColumn get accountId => text()();

  /// Signed delta applied to the account's balance in [unit] terms.
  TextColumn get units => text().map(const DecimalConverter())();

  /// Either an ISO 4217 currency code (`'CNY'`, `'USD'`) or an
  /// `assets.id` (`'us_stock:AAPL'`). The unit's namespace is
  /// disambiguated at read time by joining against `assets`.
  TextColumn get unit => text()();

  // --- Optional cost annotation (lot anchor) ------------------------
  TextColumn get costPerUnit =>
      text().map(const DecimalConverter()).nullable()();
  TextColumn get costCurrency => text().nullable()();
  TextColumn get costLotId => text().nullable()();
  DateTimeColumn get costAcquiredOn => dateTime().nullable()();

  // --- Optional price annotation (market snapshot) ------------------
  TextColumn get pricePerUnit =>
      text().map(const DecimalConverter()).nullable()();
  TextColumn get priceCurrency => text().nullable()();

  /// Cost annotation columns must be all-set or all-null together —
  /// tracking `cost_per_unit` without a `cost_currency` produces an
  /// un-weighable leg. The same holds for the price annotation.
  @override
  List<String> get customConstraints => [
    'CHECK ((cost_per_unit IS NULL) = (cost_currency IS NULL))',
    'CHECK ((price_per_unit IS NULL) = (price_currency IS NULL))',
  ];

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Append-only price observations time-series. Replaces the
/// legacy `valuationAdjust` event row plus `assets.last_price` mirror.
/// Reading the current price of an asset is a "find the latest
/// observation" query against this table.
@DataClassName('PriceRow')
class Prices extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get unit => text()();
  TextColumn get quoteCurrency => text().withLength(min: 3, max: 8)();
  DateTimeColumn get observedOn => dateTime()();
  TextColumn get perUnit => text().map(const DecimalConverter())();
  TextColumn get source => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// User-recorded corporate action source-of-truth.
///
/// Journal entries and price observations remain the accounting
/// materialisation, but this table preserves the business event itself so
/// dividend forecasts, timelines, sync, and backup can read declared actions
/// without reverse-engineering postings.
@DataClassName('CorporateActionRow')
class CorporateActions extends Table with SyncableTable {
  TextColumn get id => text()();
  TextColumn get kind => text()();
  TextColumn get assetId => text()();
  DateTimeColumn get effectiveDate => dateTime()();
  TextColumn get transactionId => text().nullable()();
  TextColumn get accountId => text().nullable()();
  TextColumn get currency => text().withLength(min: 3, max: 8).nullable()();
  TextColumn get amountPerShare =>
      text().map(const DecimalConverter()).nullable()();
  TextColumn get withholdingTax =>
      text().map(const DecimalConverter()).nullable()();
  TextColumn get bonusRatio =>
      text().map(const DecimalConverter()).nullable()();
  TextColumn get splitRatio =>
      text().map(const DecimalConverter()).nullable()();
  TextColumn get subscribedQuantity =>
      text().map(const DecimalConverter()).nullable()();
  TextColumn get pricePerUnit =>
      text().map(const DecimalConverter()).nullable()();
  TextColumn get fee => text().map(const DecimalConverter()).nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('RecurringTransactionRow')
class RecurringTransactions extends Table with SyncableTable {
  TextColumn get id => text()();

  /// JSON-encoded posting template. Forecast expansion reads this value
  /// purely in memory; generated forecast instances are never persisted.
  TextColumn get templateJournalBuildJson => text()();

  /// RFC 5545 subset: FREQ, INTERVAL, BYMONTHDAY, UNTIL.
  TextColumn get rrule => text()();

  /// Next occurrence eligible for materialisation.
  DateTimeColumn get nextDueAt => dateTime()();

  /// Last occurrence successfully turned into a journal entry.
  DateTimeColumn get lastMaterialisedAt => dateTime().nullable()();

  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
