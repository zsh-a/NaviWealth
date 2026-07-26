import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:naviwealth/core/logging/app_logger.dart';
import 'package:naviwealth/features/finance/data/market/providers/options/options_chain_provider.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:uuid/uuid.dart';

import '../data/options_opportunity_cache_repository.dart';
import '../domain/approved_underlying.dart';
import '../domain/option_contract.dart';
import '../domain/options_opportunity.dart';
import '../domain/options_strategy_profile.dart';
import '../domain/services/leaps_opportunity_scorer.dart';
import '../domain/services/opportunity_scorer.dart';

part 'scan_orchestrator_diagnostics.dart';
part 'scan_orchestrator_models.dart';
part 'scan_orchestrator_scoring.dart';

const _uuid = Uuid();
const _scanBudget = Duration(seconds: 45);
const _perUnderlyingFetchTimeout = Duration(seconds: 15);

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
    LeapsOpportunityScorer leapsScorer = const LeapsOpportunityScorer(),
  }) : _chainProvider = chainProvider,
       _scorer = scorer,
       _leapsScorer = leapsScorer,
       _cache = cache;

  final OptionsChainProvider _chainProvider;
  final OpportunityScorer _scorer;
  final LeapsOpportunityScorer _leapsScorer;
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
          scorer: _scorer,
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

    // Buy-side LEAPS lane: separate DTE window, calls only, budget-aware.
    for (final target in inputs.leapsTargets) {
      if (DateTime.now().toUtc().isAfter(deadline)) {
        errors['scan'] = 'scan timed out after ${_scanBudget.inSeconds}s';
        logger.w(
          'options-income scan: budget exhausted before LEAPS '
          '${target.symbol}',
        );
        break;
      }
      try {
        logger.d(
          'options-income scan: fetching LEAPS ${target.symbol} '
          'dte=${inputs.profile.leapsMinDte}-${inputs.profile.leapsMaxDte}',
        );
        final snapshot = await _chainProvider
            .fetchChain(
              OptionsChainRequest(
                underlying: target.symbol,
                minDte: inputs.profile.leapsMinDte,
                maxDte: inputs.profile.leapsMaxDte,
              ),
            )
            .timeout(_perUnderlyingFetchTimeout);
        final ignoreOiFloor = _openInterestUnavailable(snapshot);
        var scoredCount = 0;
        final laneOpps = <OptionsOpportunity>[];
        for (final contract in snapshot.contracts) {
          if (contract.type != OptionType.call) continue;
          final scored = _leapsScorer.scoreOne(
            contract: contract,
            profile: inputs.profile,
            budgetRemaining: target.budgetRemaining,
            groupFundingPool: target.groupFundingPool,
            ignoreOpenInterestFloor: ignoreOiFloor,
            now: now,
          );
          if (scored != null) {
            laneOpps.add(scored);
            scoredCount++;
          } else {
            final rejection = _leapsScorer.filter(
              contract: contract,
              profile: inputs.profile,
              budgetRemaining: target.budgetRemaining,
              ignoreOpenInterestFloor: ignoreOiFloor,
            );
            if (rejection != null) rejected.add(rejection);
          }
        }
        // Keep the top few per underlying — LEAPS chains list dozens of
        // near-identical strikes.
        laneOpps.sort((a, b) => b.score.compareTo(a.score));
        opportunities.addAll(laneOpps.take(3));
        logger.d(
          'options-income scan: LEAPS ${target.symbol} '
          'scored=$scoredCount kept=${laneOpps.take(3).length}',
        );
      } catch (e, st) {
        AppLogger.instance.w(
          'options-income scan: LEAPS ${target.symbol} failed',
          error: e,
          stackTrace: st,
        );
        errors['LEAPS:${target.symbol}'] = e.toString();
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
      universe: <String>{
        for (final ap in universe) ap.symbol,
        for (final target in inputs.leapsTargets) target.symbol,
      }.toList(),
      errors: errors,
      warnings: warnings,
    );
  }
}
