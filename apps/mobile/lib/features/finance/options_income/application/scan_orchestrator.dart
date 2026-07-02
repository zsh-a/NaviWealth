import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:naviwealth/core/logging/app_logger.dart';
import 'package:naviwealth/domain/values/money.dart';
import 'package:naviwealth/features/finance/data/market/providers/options/options_chain_provider.dart';
import 'package:uuid/uuid.dart';

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
    required this.warnings,
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

  /// Per-symbol data-quality warnings. These are not scan failures; they
  /// explain why a successfully fetched chain may still yield no candidates.
  final Map<String, String> warnings;
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
    final excluded = <String, List<String>>{};
    final logger = AppLogger.instance;
    logger.i(
      'options-income scan: start '
      'scanId=$scanId provider=${_chainProvider.name} '
      'approved=${inputs.approved.length} '
      'strategies=${allowedStrategies.map((s) => s.wire).join(",")} '
      'dte=${inputs.profile.minDte}-${inputs.profile.maxDte} '
      'minYield=${_pct(inputs.profile.minAnnualizedYield)} '
      'minOI=${inputs.profile.minOpenInterest} '
      'minVol=${inputs.profile.minVolume} '
      'maxSpread=${_pct(inputs.profile.maxBidAskSpreadPct)} '
      'cash=${inputs.availableCash.amount} ${inputs.availableCash.currency}',
    );
    for (final ap in inputs.approved) {
      final symbol = ap.symbol.toUpperCase();
      final shares = inputs.holdingsBySymbol[symbol] ?? 0;
      final wantsPut =
          ap.allowPut &&
          allowedStrategies.contains(OptionsStrategyKind.cashSecuredPut);
      final wantsCall =
          ap.allowCall &&
          allowedStrategies.contains(OptionsStrategyKind.coveredCall) &&
          shares >= 100;
      if (wantsPut || wantsCall) {
        universe.add(ap);
      } else {
        excluded[symbol] = _universeExclusionReasons(
          approved: ap,
          allowedStrategies: allowedStrategies,
          shares: shares,
        );
      }
    }
    logger.d(
      'options-income scan: universe '
      'included=${universe.map((a) => a.symbol.toUpperCase()).join(",")} '
      'excluded=$excluded',
    );

    final opportunities = <OptionsOpportunity>[];
    final rejected = <RejectedCandidate>[];
    final errors = <String, String>{};
    final warnings = <String, String>{};

    for (final ap in universe) {
      if (DateTime.now().toUtc().isAfter(deadline)) {
        errors['scan'] = 'scan timed out after ${_scanBudget.inSeconds}s';
        logger.w('options-income scan: budget exhausted before ${ap.symbol}');
        break;
      }
      try {
        final sw = Stopwatch()..start();
        logger.d(
          'options-income scan: fetching ${ap.symbol} '
          'dte=${inputs.profile.minDte}-${inputs.profile.maxDte}',
        );
        final snapshot = await _chainProvider
            .fetchChain(
              OptionsChainRequest(
                underlying: ap.symbol,
                minDte: inputs.profile.minDte,
                maxDte: inputs.profile.maxDte,
              ),
            )
            .timeout(_perUnderlyingFetchTimeout);
        logger.d(
          'options-income scan: fetched ${ap.symbol} '
          'contracts=${snapshot.contracts.length} '
          'spot=${snapshot.underlyingPriceRaw} ${snapshot.currency} '
          'elapsedMs=${sw.elapsedMilliseconds}',
        );
        final result = _scoreSnapshot(
          snapshot: snapshot,
          ap: ap,
          inputs: inputs,
          now: now,
        );
        final warning = _quoteQualityWarning(
          snapshot,
          minOpenInterest: inputs.profile.minOpenInterest,
        );
        if (warning != null) {
          warnings[ap.symbol.toUpperCase()] = warning;
          logger.w('options-income scan: ${ap.symbol} warning: $warning');
        }
        logger.d(
          'options-income scan: scored ${ap.symbol} '
          'opportunities=${result.opportunities.length} '
          'rejected=${result.rejected.length} '
          'topRejects=${_formatReasonCounts(result.rejected)}',
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
    logger.i(
      'options-income scan: persisting '
      'scanId=$scanId opportunities=${opportunities.length} '
      'rejected=${rejected.length} topRejects=${_formatReasonCounts(rejected)} '
      'errors=$errors warnings=$warnings',
    );

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
      warnings: warnings,
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
    final ignoreOpenInterestFloor = _openInterestUnavailable(snapshot);
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
        ignoreOpenInterestFloor: ignoreOpenInterestFloor,
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
          ignoreOpenInterestFloor: ignoreOpenInterestFloor,
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

List<String> _universeExclusionReasons({
  required ApprovedUnderlying approved,
  required Set<OptionsStrategyKind> allowedStrategies,
  required int shares,
}) {
  final reasons = <String>[];
  if (!approved.allowPut) {
    reasons.add('put_not_allowed');
  } else if (!allowedStrategies.contains(OptionsStrategyKind.cashSecuredPut)) {
    reasons.add('cash_secured_put_strategy_disabled');
  }
  if (!approved.allowCall) {
    reasons.add('call_not_allowed');
  } else if (!allowedStrategies.contains(OptionsStrategyKind.coveredCall)) {
    reasons.add('covered_call_strategy_disabled');
  } else if (shares < 100) {
    reasons.add('covered_call_needs_100_shares_have_$shares');
  }
  return reasons;
}

String _formatReasonCounts(Iterable<RejectedCandidate> rejected) {
  final counts = <String, int>{};
  for (final candidate in rejected) {
    for (final reason in candidate.reasons) {
      counts.update(reason, (value) => value + 1, ifAbsent: () => 1);
    }
  }
  if (counts.isEmpty) return '{}';
  final entries = counts.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      if (byCount != 0) return byCount;
      return a.key.compareTo(b.key);
    });
  return entries.take(8).map((e) => '${e.key}:${e.value}').join(', ');
}

String _pct(Decimal value) => '${(value * Decimal.fromInt(100)).toString()}%';

String? _quoteQualityWarning(
  OptionsChainSnapshot snapshot, {
  required int minOpenInterest,
}) {
  if (snapshot.contracts.isEmpty) return null;
  final total = snapshot.contracts.length;
  final oiBelowFloor = snapshot.contracts
      .where((contract) => contract.openInterest < minOpenInterest)
      .length;
  final emptyQuotes = snapshot.contracts
      .where(
        (contract) =>
            contract.bid.amount <= Decimal.zero &&
            contract.ask.amount <= Decimal.zero,
      )
      .length;
  final allQuoteEmpty = emptyQuotes >= total;
  final allOpenInterestUnavailable = _openInterestUnavailable(snapshot);
  final allOiBelowFloor = oiBelowFloor >= total;
  if (!allQuoteEmpty && !allOpenInterestUnavailable && !allOiBelowFloor) {
    return null;
  }
  final details = <String>[];
  if (allQuoteEmpty) details.add('all contracts have empty bid/ask quotes');
  if (allOpenInterestUnavailable) {
    details.add('open interest appears unavailable from source');
  } else if (allOiBelowFloor) {
    details.add('all contracts are below OI floor');
  }
  return 'Quote quality warning: ${details.join("; ")}. '
      'The chain was fetched successfully, but current tradable quotes '
      'are unavailable or too sparse.';
}

bool _openInterestUnavailable(OptionsChainSnapshot snapshot) {
  final contracts = snapshot.contracts;
  if (contracts.isEmpty) return false;
  final positive = contracts.where((c) => c.openInterest > 0).length;
  final toleratedSparsePositiveCount = (contracts.length * 0.05).floor();
  return positive <= toleratedSparsePositiveCount;
}

class _PerSymbolResult {
  const _PerSymbolResult({required this.opportunities, required this.rejected});
  final List<OptionsOpportunity> opportunities;
  final List<RejectedCandidate> rejected;
}
