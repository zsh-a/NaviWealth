/// Tax jurisdiction code. The coarse `cn / us / hk` enum is intentional —
/// it maps cleanly to the policies we ship out of the box, and `other` lets
/// users plug in a custom rate without forcing us to enumerate every
/// country up front.
///
/// Two roles are tracked separately on the wire:
///
/// - **source jurisdiction** — the country the *asset* (or its issuer) is
///   domiciled in. Determines dividend withholding tax (e.g. US 30 % WHT
///   on US-listed dividends paid to non-US holders).
/// - **holder jurisdiction** — the country the *user* is taxed in.
///   Determines capital gains tax on realized lots.
enum TaxJurisdiction { cn, us, hk, other }
