/// All enum types used across NaviWealth domain models.
///
/// Stored on disk via Drift's `EnumNameConverter`-style mapping (see
/// `lib/data/db/converters.dart`), so adding a value at the **end** of an
/// enum is forward-compatible, but renaming or reordering existing values
/// requires a migration that rewrites the persisted name.
library;

/// Container/owner of holdings or cash flows.
enum AccountType {
  brokerage,
  bank,
  cryptoWallet,
  realEstate,
  vehicle,
  liability,
  cash,
  other,
}

/// FIR-126 — accounting classification orthogonal to [AccountType].
///
/// [AccountType] describes the *carrier shape* of an account ("is this a
/// bank card or a brokerage account?"). [AccountCategory] describes which
/// side of the standard double-entry bookkeeping identity the account
/// belongs to. The two are intentionally independent: the same `bank`
/// carrier might back an asset (a savings deposit) or a liability (a credit
/// card) depending on the user's intent.
///
/// The full five-category set (P1-A scope) is required so that future
/// double-entry posting (P2-A) has a complete account taxonomy to lean on:
/// every transaction will resolve to a debit + credit pair across asset /
/// liability / income / expense / equity buckets.
///
/// The seeded virtual system accounts ([systemAccountSlugForCategory]) for
/// income / expense / equity give cash flows a counter-account to settle
/// against before the proper posting model lands. Storage uses the
/// generic [EnumStringConverter], so adding new values must be appended at
/// the end and no value may be reordered or renamed without a migration.
enum AccountCategory { asset, liability, income, expense, equity }

/// Default [AccountCategory] suggestion for a given [AccountType].
///
/// Mirrors the v8 backfill rules so the create-account form, the AI
/// proposal applier and the migration agree on the same heuristic. UI
/// callers always let the user override the suggestion before saving.
AccountCategory defaultCategoryForAccountType(AccountType type) {
  switch (type) {
    case AccountType.brokerage:
    case AccountType.bank:
    case AccountType.cryptoWallet:
    case AccountType.cash:
    case AccountType.realEstate:
    case AccountType.vehicle:
    case AccountType.other:
      return AccountCategory.asset;
    case AccountType.liability:
      return AccountCategory.liability;
  }
}

/// Static classification of an [Asset]. Used to drive UI affordances and
/// cost-basis behavior.
///
/// FIR-44 added the three "no-market-data" deposit/wealth flavours at the
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

/// Subset of [AssetType] whose canonical id is `<market>:<symbol>` (FIR-75)
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

/// Single fact-table entry kind. Anything that mutates a holding or cash
/// position must be one of these so reports can roll up cleanly.
///
/// FIR-68 added `expense` at the end. An expense is a categorised cash
/// outflow stored as a [Transactions] row with `quantity` carrying the
/// signed (negative) amount and `expenseMetadataJson` holding the
/// expense-specific bits (category, tags). Existing aggregators that don't
/// know about expenses can safely fold them as a generic outflow.
enum TransactionType {
  buy,
  sell,
  dividend,
  reinvest,
  interest,
  deposit,
  withdraw,
  transferIn,
  transferOut,
  fee,
  tax,
  valuationAdjust,
  split,
  liabilityPayment,
  expense,
}

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
