/// English strings for the Income Planner P0 surface.
///
/// Kept inline (rather than in `l10n/app_en.arb`) until P1 lands the
/// scanner — at that point the full string surface stabilises and a
/// single l10n migration is cheaper than touching ARBs per phase.
class IncomePlannerStrings {
  const IncomePlannerStrings._();

  static const pageTitle = 'Income Planner';

  // OCC disclosure
  static const occTitle = 'Options risk disclosure';
  static const occSubtitle = 'Read before using';
  static const occBody =
      'Selling cash-secured puts and covered calls have defined and '
      'undefined risks. Sell-puts can require you to buy 100 shares at '
      'strike if assigned; covered calls cap upside above strike. '
      'Income Planner only screens opportunities that match your stated '
      'risk preferences — it does not predict prices and does not place '
      'orders. By continuing you acknowledge you have read OCC '
      'Characteristics and Risks of Standardized Options.';
  static const occAccept = 'I have read and accept';
  static const occCancel = 'Not now';
  static const occLearnMore = 'Open OCC ODD';

  // Empty states
  static const startTitle = 'Set up your stance';
  static const startBody =
      'Tell Income Planner which strategies and risk level you '
      'want, then approve the underlyings you would be happy to '
      'own or sell.';
  static const startCta = 'Configure preferences';

  static const noApprovedTitle = 'No approved underlyings yet';
  static const noApprovedBody =
      'Add the stocks or ETFs you would be willing to long-term hold '
      '(for sell puts) or sell at a higher price (for covered calls). '
      'Income Planner only scans symbols on this list.';
  static const addApprovedCta = 'Add underlying';

  // Profile sheet
  static const profileTitle = 'Preferences';
  static const profileMode = 'Risk mode';
  static const profileModeConservative = 'Conservative';
  static const profileModeBalanced = 'Balanced';
  static const profileModeAggressive = 'Aggressive';
  static const profileModeCustom = 'Custom';
  static const profileAvoidEarnings =
      'Skip candidates within 7 days of earnings';
  static const profileAvoidMacroEvents =
      'Skip candidates within 7 days of CPI / FOMC';
  static const profileOnlyApproved =
      'Only scan symbols on the approved list (recommended)';
  static const profileAllowedStrategies = 'Strategies';
  static const profileAllowPut = 'Cash-secured puts';
  static const profileAllowCall = 'Covered calls';
  static const profileSave = 'Save';
  static const profileCancel = 'Cancel';

  // Approved underlying form
  static const addUnderlyingTitle = 'Add approved underlying';
  static const editUnderlyingTitle = 'Edit underlying';
  static const symbolLabel = 'Symbol';
  static const symbolHint = 'AAPL';
  static const marketLabel = 'Market';
  static const allowPutLabel = 'Allow cash-secured puts';
  static const allowCallLabel = 'Allow covered calls';
  static const saveAction = 'Save';
  static const deleteAction = 'Delete';
  static const cancelAction = 'Cancel';

  // Sections
  static const approvedSectionTitle = 'Approved underlyings';
  static const opportunitiesSectionTitle = 'Opportunities';
  static const opportunitiesEmpty =
      'No cached opportunities yet. Tap “Refresh opportunities” to scan '
      'your approved underlyings.';
  static const refreshAction = 'Refresh opportunities';
  static const refreshRunning = 'Scanning…';
  static const refreshFailedTitle = 'Scan failed';
  static const refreshUniverseEmpty =
      'No symbols are eligible. Add at least one approved underlying '
      'with put/call enabled, or check that you own ≥100 shares for '
      'covered calls.';
  static const lastScanLabel = 'Last scan';
  static const lastScanStale =
      'Cached results are older than 24h — refresh for fresher data.';
  static const opportunitiesAllRejected =
      'No candidates passed your hard filters this scan. Loosen your '
      'preferences (e.g. lower yield floor, wider DTE) and try again.';

  // Opportunity card chips
  static const chipCashSecuredPut = 'Sell put';
  static const chipCoveredCall = 'Covered call';
  static const riskLow = 'Low risk';
  static const riskModerate = 'Moderate';
  static const riskElevated = 'Elevated';

  // Card metrics
  static const metricAnnualized = 'Annualized';
  static const metricCash = 'Cash required';
  static const metricBreakeven = 'Breakeven';
  static const metricDte = 'DTE';
  static const metricStrike = 'Strike';
  static const metricMargin = 'Cushion';
  static const cardDetailsCta = 'Details';

  // Detail sheet
  static const detailWhyGood = 'Why this looks good';
  static const detailWhyRisky = 'Why this is risky';
  static const detailWorstCase = 'Worst case';
  static const detailBestFor = 'Best for';
  static const detailAvoidIf = 'Avoid if';
  static const detailScoreBreakdown = 'Score breakdown';
  static const detailLogTrade = 'Log this trade';

  // Trade journal
  static const journalSectionTitle = 'Trade journal';
  static const journalEmpty =
      'Closed and open positions you log will appear here.';
  static const journalAddCta = 'Log trade';
  static const journalEditTitle = 'Edit trade journal entry';
  static const journalCreditLabel = 'Credit received';
  static const journalDebitLabel = 'Debit paid to close';
  static const journalStatusOpen = 'Open';
  static const journalStatusClosed = 'Closed';
  static const journalStatusAssigned = 'Assigned';
  static const journalStatusExpired = 'Expired';

  // Errors / validation
  static const symbolRequired = 'Symbol is required';
  static const duplicateSymbol = 'This symbol is already on the list';
  static const profileSaveError = 'Could not save preferences';
  static const underlyingSaveError = 'Could not save underlying';

  // Misc
  static const preferencesAction = 'Preferences';
  static const editAction = 'Edit';
}
