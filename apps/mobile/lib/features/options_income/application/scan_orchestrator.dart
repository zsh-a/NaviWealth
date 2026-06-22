import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:uuid/uuid.dart';

import '../../../core/logging/app_logger.dart';
import '../../../domain/values/money.dart';
import '../../../features/finance/data/market/providers/options/options_chain_provider.dart';
import '../data/options_opportunity_cache_repository.dart';
import '../domain/approved_underlying.dart';
import '../domain/option_contract.dart';
import '../domain/options_opportunity.dart';
import '../domain/options_strategy_profile.dart';
import '../domain/services/opportunity_scorer.dart';

const _uuid = Uuid();
const _scanBudget = Duration(seconds: 45);
const _perUnderlyingFetchTimeout = Duration(seconds: 15);

/// Snapshot of a holding the orchestrator needs for filtering. We keep a
/// tiny shape rather than depending on [HoldingSnapshot] to keep the
/// orchestrator decoupled from the investment feature's import graph.
class HoldingsLite {
  const HoldingsLite({required this.shares, required this.symbol});
  final int shares;
  final String symbol;
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
  });

  final String ownerUserId;
  final OptionsStrategyProfile profile;
  final List<ApprovedUnderlying> approved;

  /// Symbol → integer share count. Symbols not in the map default to 0.
  final Map<String, int> holdingsBySymbol;

  /// Symbol → current portfolio weight as a 0..1 decimal. Missing means
  /// exposure is unknown and the scorer falls back to a neutral fit score.
  final Map<String, Decimal> exposureBySymbol;

  final Money availableCash;

  final Set<String> upcomingEarningsSymbols;
  final bool upcomingMacroEvent;
}

class ScanResult {
  const ScanResult({
    required this.scanId,
    required this.scannedAt,
    required this.opportunities,
    required this.rejected,
    required this.universe,
    required this.errors,
  });

  /// New scan id (UUIDv4).
  final String scanId;
  final DateTime scannedAt;
  final List<OptionsOpportunity> opportunities;
  final List<RejectedCandidate> rejected;

  /// Underlyings actually queried (approved ∩ allowed).
  final List<String> universe;

  /// Per-symbol fetch errors. Non-fatal — scan continues for other symbols.
  final Map<String, String> errors;
}

/// Coordinates one user-initiated scan pass.
///
/// Boundaries:
///   * Only ever called from a user gesture (Income Planner refresh button)
///     — never from a render path or timer.
///   * Mid-scan failures for individual symbols are captured per-symbol; the
///     orchestrator still emits whatever scored cleanly for the others.
class ScanOrchestrator {
  ScanOrchestrator({
    required OptionsChainProvider chainProvider,
    required OpportunityScorer scorer,
    required OptionsOpportunityCacheRepository cache,
  }) : _chainProvider = chainProvider,
       _scorer = scorer,
       _cache = cache;

  final OptionsChainProvider _chainProvider;
  final OpportunityScorer _scorer;
  final OptionsOpportunityCacheRepository _cache;

  Future<ScanResult> run(ScanInputs inputs) async {
    final scanId = _uuid.v4();
    final now = DateTime.now().toUtc();
    final deadline = now.add(_scanBudget);
    final allowedStrategies = inputs.profile.allowedStrategies;
    final universe = <ApprovedUnderlying>[];
    for (final ap in inputs.approved) {
      final symbol = ap.symbol.toUpperCase();
      final wantsPut =
          ap.allowPut &&
          allowedStrategies.contains(OptionsStrategyKind.cashSecuredPut);
      final wantsCall =
          ap.allowCall &&
          allowedStrategies.contains(OptionsStrategyKind.coveredCall) &&
          (inputs.holdingsBySymbol[symbol] ?? 0) >= 100;
      if (wantsPut || wantsCall) universe.add(ap);
    }

    final opportunities = <OptionsOpportunity>[];
    final rejected = <RejectedCandidate>[];
    final errors = <String, String>{};

    for (final ap in universe) {
      if (DateTime.now().toUtc().isAfter(deadline)) {
        errors['scan'] = 'scan timed out after ${_scanBudget.inSeconds}s';
        break;
      }
      try {
        final snapshot = await _chainProvider
            .fetchChain(
              OptionsChainRequest(
                underlying: ap.symbol,
                minDte: inputs.profile.minDte,
                maxDte: inputs.profile.maxDte,
              ),
            )
            .timeout(_perUnderlyingFetchTimeout);
        final result = _scoreSnapshot(
          snapshot: snapshot,
          ap: ap,
          inputs: inputs,
          now: now,
        );
        opportunities.addAll(result.opportunities);
        rejected.addAll(result.rejected);
      } catch (e, st) {
        AppLogger.instance.w(
          'options-income scan: ${ap.symbol} failed',
          error: e,
          stackTrace: st,
        );
        errors[ap.symbol] = e.toString();
      }
    }

    opportunities.sort((a, b) => b.score.compareTo(a.score));

    await _cache.replaceBatch(
      ownerUserId: inputs.ownerUserId,
      scanId: scanId,
      opportunities: opportunities,
    );

    return ScanResult(
      scanId: scanId,
      scannedAt: now,
      opportunities: opportunities,
      rejected: rejected,
      universe: universe.map((a) => a.symbol).toList(),
      errors: errors,
    );
  }

  _PerSymbolResult _scoreSnapshot({
    required OptionsChainSnapshot snapshot,
    required ApprovedUnderlying ap,
    required ScanInputs inputs,
    required DateTime now,
  }) {
    final symbol = ap.symbol.toUpperCase();
    final shares = inputs.holdingsBySymbol[symbol] ?? 0;
    final exposure = inputs.exposureBySymbol[symbol];
    final hasEarnings = inputs.upcomingEarningsSymbols.contains(symbol);
    final hasMacro = inputs.upcomingMacroEvent;
    final opps = <OptionsOpportunity>[];
    final rejs = <RejectedCandidate>[];
    for (final contract in snapshot.contracts) {
      final OptionsStrategyKind strategy;
      switch (contract.type) {
        case OptionType.put:
          if (!ap.allowPut ||
              !inputs.profile.allowedStrategies.contains(
                OptionsStrategyKind.cashSecuredPut,
              )) {
            continue;
          }
          strategy = OptionsStrategyKind.cashSecuredPut;
          break;
        case OptionType.call:
          if (!ap.allowCall ||
              !inputs.profile.allowedStrategies.contains(
                OptionsStrategyKind.coveredCall,
              )) {
            continue;
          }
          strategy = OptionsStrategyKind.coveredCall;
          break;
      }
      final scored = _scorer.scoreOne(
        contract: contract,
        strategy: strategy,
        profile: inputs.profile,
        approved: ap,
        sharesOwned: shares,
        availableCash: inputs.availableCash,
        currentUnderlyingExposurePct: exposure,
        hasUpcomingEarnings: hasEarnings,
        hasUpcomingMacroEvent: hasMacro,
        now: now,
      );
      if (scored != null) {
        opps.add(scored.opportunity);
      } else {
        final rejection = _scorer.filter(
          contract: contract,
          strategy: strategy,
          profile: inputs.profile,
          approved: ap,
          sharesOwned: shares,
          availableCash: inputs.availableCash,
          currentUnderlyingExposurePct: exposure,
          hasUpcomingEarnings: hasEarnings,
          hasUpcomingMacroEvent: hasMacro,
        );
        if (rejection != null) rejs.add(rejection);
      }
    }
    // Keep the top N per (strategy, expiration) tuple so the UI shows
    // variety instead of dozens of near-duplicate strikes.
    final topPerBucket = _topPerBucket(opps);
    return _PerSymbolResult(opportunities: topPerBucket, rejected: rejs);
  }

  /// Within each `(strategy, expiration)` bucket, keep at most 2
  /// strikes — the highest-scoring one and the most conservative one
  /// (highest safety margin). Caller has already sorted globally.
  List<OptionsOpportunity> _topPerBucket(List<OptionsOpportunity> opps) {
    final buckets = <String, List<OptionsOpportunity>>{};
    for (final opp in opps) {
      final key =
          '${opp.strategy.wire}|${opp.contract.expiration.toIso8601String()}';
      buckets.putIfAbsent(key, () => []).add(opp);
    }
    final out = <OptionsOpportunity>[];
    buckets.forEach((_, list) {
      list.sort((a, b) => b.score.compareTo(a.score));
      final best = list.first;
      out.add(best);
      // Most conservative = highest margin of safety, distinct from best.
      OptionsOpportunity? safest;
      Decimal safestMargin = Decimal.zero;
      for (final o in list.skip(1)) {
        if (o.metrics.marginOfSafety > safestMargin) {
          safest = o;
          safestMargin = o.metrics.marginOfSafety;
        }
      }
      if (safest != null) out.add(safest);
    });
    return out;
  }
}

class _PerSymbolResult {
  const _PerSymbolResult({required this.opportunities, required this.rejected});
  final List<OptionsOpportunity> opportunities;
  final List<RejectedCandidate> rejected;
}
