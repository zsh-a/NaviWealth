/// Cross-domain enum types used by Drift table definitions in
/// `core/persistence/`.
///
/// These enums were extracted from `features/finance/data/domain/enums.dart`
/// so that `core/persistence/tables.dart` and `app_database.dart` do not
/// import from `features/`. The original file re-exports this library for
/// backward compatibility.
///
/// Stored on disk via Drift's `EnumNameConverter`-style mapping (see
/// `lib/core/persistence/converters.dart`), so adding a value at the **end**
/// of an enum is forward-compatible, but renaming or reordering existing
/// values requires a migration that rewrites the persisted name.

/// Wealth-container category — the user-visible "what kind of account is
/// this" semantic. Drives icons, defaults, AI behaviour (cash counts toward
/// liquidity, broker counts toward risk exposure, credit is short-term
/// liability with billing cycles, etc.).
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
enum AccountSide { asset, liability, income, expense, equity }

/// Auto-derive the accounting side from a wealth-container category.
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
/// the user rather than fetched from a market data provider.
const Set<AssetType> kManualValuationAssetTypes = {
  AssetType.cash,
  AssetType.bankDepositTerm,
  AssetType.bankDepositDemand,
  AssetType.wealthProduct,
};

/// Subset of [AssetType] whose canonical id is `<market>:<symbol>`
/// and which `SecuritiesAssetRepository.watchSecurities` lists by default.
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
enum RepaymentMethod { equalInstallment, equalPrincipal }

/// How the [Liability] interest rate is determined.
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

/// OpLog operation kind.
enum OpKind { insert, update, delete }

/// Beancount-style lifecycle flag for a `JournalEntry` row.
enum EntryFlag { confirmed, pending, padding }
