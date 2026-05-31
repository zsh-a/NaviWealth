/// All enum types used across NaviWealth domain models.
///
/// Stored on disk via Drift's `EnumNameConverter`-style mapping (see
/// `lib/core/persistence/converters.dart`), so adding a value at the **end** of an
/// enum is forward-compatible, but renaming or reordering existing values
/// requires a migration that rewrites the persisted name.
library;

/// Wealth-container category — the user-visible "what kind of account is
/// this" semantic. Drives icons, defaults, AI behaviour (cash counts toward
/// liquidity, broker counts toward risk exposure, credit is short-term
/// liability with billing cycles, etc.).
///
/// Replaced the carrier-shape `AccountType` with a calmer 8-value
/// taxonomy modelled after how the user actually thinks about their wealth
/// containers, not how a bookkeeping system files them. The companion
/// accounting "side of the double-entry book" classification is
/// [AccountSide] and is auto-derived via [accountSideForCategory] — users
/// never see it.
///
/// Storage uses the generic [EnumStringConverter]; new values must be
/// appended at the end. The v3→v4 migration maps the legacy carrier-shape
/// values to this enum (brokerage→broker, cryptoWallet→crypto,
/// realEstate/vehicle/other→asset; cash/bank/liability unchanged).
enum AccountCategory {
  cash,
  bank,
  broker,
  crypto,
  credit,
  loan,
  asset,
  liability,
}

/// Side of the standard double-entry bookkeeping identity the account
/// settles to. Auto-derived from [AccountCategory] via
/// [accountSideForCategory]; never shown to or edited by the user.
///
/// The seeded virtual system accounts (income / expense / equity sub-trees)
/// for cash-flow counter-postings live under the corresponding side; they
/// are not user-creatable wealth containers and are surfaced separately
/// in the ledger / posting model.
///
/// Storage uses the generic [EnumStringConverter]; new values must be
/// appended at the end. The v3→v4 migration rewrites the legacy
/// `accounts.category` column from the old user-facing enum
/// (asset/liability/income/expense/equity) into this auto-derived one.
enum AccountSide { asset, liability, income, expense, equity }

/// Auto-derive the accounting side from a wealth-container category.
///
/// User-creatable containers always map to either `asset` or `liability`;
/// `income` / `expense` / `equity` sides only ever back system accounts
/// (seeded counter-postings) and never come from this function.
AccountSide accountSideForCategory(AccountCategory category) {
  switch (category) {
    case AccountCategory.cash:
    case AccountCategory.bank:
    case AccountCategory.broker:
    case AccountCategory.crypto:
    case AccountCategory.asset:
      return AccountSide.asset;
    case AccountCategory.credit:
    case AccountCategory.loan:
    case AccountCategory.liability:
      return AccountSide.liability;
  }
}

/// Static classification of an [Asset]. Used to drive UI affordances and
/// cost-basis behavior.
///
/// Added the three "no-market-data" deposit/wealth flavours at the
/// end. Adding new values at the *end* keeps name-based persistence
/// backwards-compatible (see `EnumStringConverter`).
enum AssetType {
  stock,
  etf,
  mutualFund,
  bond,
  crypto,
  cash,
  realEstate,
  vehicle,
  commodity,
  custom,
  bankDepositTerm,
  bankDepositDemand,
  wealthProduct,
}

/// Subset of [AssetType] whose current price/value is updated manually by
/// the user rather than fetched from a market data provider. The forms +
/// repository in `features/assets` only handle these.
const Set<AssetType> kManualValuationAssetTypes = {
  AssetType.cash,
  AssetType.bankDepositTerm,
  AssetType.bankDepositDemand,
  AssetType.wealthProduct,
};

/// Subset of [AssetType] whose canonical id is `<market>:<symbol>`
/// and which `SecuritiesAssetRepository.watchSecurities` lists by default.
/// Anything outside this set either has no global symbol (cash / deposit /
/// wealth product / real estate / vehicle) or is too freeform to lift into
/// the catalog (custom, commodity).
const Set<AssetType> kSecuritiesAssetTypes = {
  AssetType.stock,
  AssetType.etf,
  AssetType.mutualFund,
  AssetType.bond,
  AssetType.crypto,
};

/// Cost-basis lot selection. Configurable per [Settings] so users in
/// different tax regimes can pick the method that matches their filings.
enum CostBasisMethod { fifo, lifo, averageCost, specificLot }

/// Backing kind for a [Liability].
enum LiabilityType {
  mortgage,
  carLoan,
  creditCard,
  consumerLoan,
  studentLoan,
  marginLoan,
  other,
}

/// Repayment schedule shape — drives how the amortization table is generated
/// from the loan's principal, rate and term.
///
/// - [equalInstallment] (等额本息) — same total payment every period; the
///   principal share grows while the interest share shrinks.
/// - [equalPrincipal] (等额本金) — same principal share every period; the
///   total payment shrinks because interest is computed on the falling
///   balance.
enum RepaymentMethod { equalInstallment, equalPrincipal }

/// How the [Liability] interest rate is determined. [fixed] keeps the rate
/// constant; [lprFloating] is a Chinese-mortgage convention where the
/// effective rate floats with the central bank's LPR — we still store the
/// effective rate, but flagging it lets the UI surface a "rate may change"
/// hint rather than implying the schedule is set in stone.
enum LiabilityRateType { fixed, lprFloating }

/// User-visible color theme preference.
enum AppThemeMode { system, light, dark }

/// Privacy mode — when `hidden`, balances render as `***` outside of the
/// dedicated detail screens.
enum PrivacyMode { visible, hidden }

/// Tag classification — drives faceted filters in analytics.
enum TagKind { industry, region, marketCap, theme, custom }

/// Goal type.
enum GoalType { fire, targetAllocation, savings, debtPayoff, custom }

/// Device platform — informational, used by sync to pick UA strings and by
/// the user to identify devices in the trusted-devices list.
enum DevicePlatform { ios, android, web, macos, windows, linux, unknown }

/// OpLog operation kind. Together with `entityTable` + `entityId` this is
/// enough to reconstruct any state change on the receiving side.
enum OpKind { insert, update, delete }

/// Beancount-style lifecycle flag for a `JournalEntry` row. Maps 1:1 to
/// Beancount's `*` / `!` / `#` prefix syntax so the eventual `.beancount`
/// exporter can serialise the column without a
/// translation table.
///
///   - [confirmed] — the user has reviewed and accepted the entry; the
///     default for hand-entered rows.
///   - [pending] — the entry is provisional (e.g. drafted from an AI
///     proposal that hasn't been confirmed yet). Reports may exclude
///     pending entries from "actuals" buckets.
///   - [padding] — synthetic balance assertion / opening-balance row.
///     Padding rows skip the standard balance check; their purpose is to
///     reconcile against an externally-known total rather than describe
///     an economic event.
enum EntryFlag { confirmed, pending, padding }
