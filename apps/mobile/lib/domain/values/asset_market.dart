/// Logical market a symbol belongs to.
///
/// Used by the market-data layer to pick the right provider chain. Not the
/// same as the asset class — an A-share ETF and an A-share stock share the
/// same market routing but differ in asset class.
enum AssetMarket { cnA, hkStock, usStock, crypto, fx, unknown }
