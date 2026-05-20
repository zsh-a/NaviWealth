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
      'P1 will surface scan results here. Today this page only manages '
      'your stance and your approved underlying list.';

  // Errors / validation
  static const symbolRequired = 'Symbol is required';
  static const duplicateSymbol = 'This symbol is already on the list';
  static const profileSaveError = 'Could not save preferences';
  static const underlyingSaveError = 'Could not save underlying';

  // Misc
  static const preferencesAction = 'Preferences';
  static const editAction = 'Edit';
}
