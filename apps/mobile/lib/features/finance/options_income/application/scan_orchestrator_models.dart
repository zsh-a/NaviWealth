part of 'scan_orchestrator.dart';

/// Snapshot of a holding the orchestrator needs for filtering. We keep a
/// tiny shape rather than depending on [HoldingSnapshot] to keep the
/// orchestrator decoupled from the investment feature's import graph.
class HoldingsLite {
  const HoldingsLite({required this.shares, required this.symbol});

  final int shares;
  final String symbol;
}

/// One underlying whose plan enables the LEAPS call sleeve. Carries the
/// budget and group-funding context the buy-side scorer needs.
class LeapsScanTarget {
  const LeapsScanTarget({
    required this.symbol,
    this.budgetRemaining,
    this.groupFundingPool,
  });

  final String symbol;

  /// Plan `max_cost` minus the gross cost of already-open LEAPS on this
  /// underlying. Null when the plan sets no budget.
  final Money? budgetRemaining;

  /// Realized income (wheel + dividends) across the underlying's strategy
  /// group — the pool that pays for LEAPS premium. Null without context.
  final Money? groupFundingPool;
}

class ScanInputs {
  const ScanInputs({
    required this.ownerUserId,
    required this.profile,
    required this.approved,
    required this.holdingsBySymbol,
    required this.exposureBySymbol,
    required this.availableCash,
    required this.upcomingEarningsSymbols,
    required this.upcomingMacroEvent,
    this.eventDataAvailable = false,
    this.leapsTargets = const <LeapsScanTarget>[],
  });

  final String ownerUserId;
  final OptionsStrategyProfile profile;
  final List<ApprovedUnderlying> approved;

  /// Buy-side LEAPS lane universe. Empty when no plan enables the sleeve.
  final List<LeapsScanTarget> leapsTargets;

  /// Symbol -> integer share count. Symbols not in the map default to 0.
  final Map<String, int> holdingsBySymbol;

  /// Symbol -> current portfolio weight as a 0..1 decimal. Missing means
  /// exposure is unknown and the scorer falls back to a neutral fit score.
  final Map<String, Decimal> exposureBySymbol;

  final Money availableCash;

  final Set<String> upcomingEarningsSymbols;
  final bool upcomingMacroEvent;

  /// Whether earnings and macro-event inputs came from a real, current
  /// calendar. False keeps event filtering and scoring neutral.
  final bool eventDataAvailable;
}

class ScanResult {
  const ScanResult({
    required this.scanId,
    required this.scannedAt,
    required this.opportunities,
    required this.rejected,
    required this.universe,
    required this.errors,
    required this.warnings,
  });

  /// New scan id (UUIDv4).
  final String scanId;
  final DateTime scannedAt;
  final List<OptionsOpportunity> opportunities;
  final List<RejectedCandidate> rejected;

  /// Underlyings actually queried (approved intersect allowed).
  final List<String> universe;

  /// Per-symbol fetch errors. Non-fatal — scan continues for other symbols.
  final Map<String, String> errors;

  /// Per-symbol data-quality warnings. These are not scan failures; they
  /// explain why a successfully fetched chain may still yield no candidates.
  final Map<String, String> warnings;
}

class _PerSymbolResult {
  const _PerSymbolResult({required this.opportunities, required this.rejected});

  final List<OptionsOpportunity> opportunities;
  final List<RejectedCandidate> rejected;
}
