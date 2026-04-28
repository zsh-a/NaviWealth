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

/// Single fact-table entry kind. Anything that mutates a holding or cash
/// position must be one of these so reports can roll up cleanly.
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
