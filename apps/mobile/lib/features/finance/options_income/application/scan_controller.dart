import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:naviwealth/core/logging/app_logger.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/features/finance/income_strategy/data/providers.dart';
import 'package:naviwealth/features/finance/income_strategy/domain/income_strategy.dart';
import '../data/providers.dart';
import 'leaps_scan_targets.dart';
import 'scan_inputs_bridge.dart';
import 'scan_orchestrator.dart';

/// Lifecycle states the Income Planner page renders.
sealed class ScanState {
  const ScanState();
}

class ScanIdle extends ScanState {
  const ScanIdle();
}

class ScanRunning extends ScanState {
  const ScanRunning({required this.startedAt});
  final DateTime startedAt;
}

class ScanSuccess extends ScanState {
  const ScanSuccess({required this.result});
  final ScanResult result;
}

class ScanFailure extends ScanState {
  const ScanFailure({required this.error});
  final Object error;
}

class ScanController extends Notifier<ScanState> {
  @override
  ScanState build() => const ScanIdle();

  Future<ScanResult?> runScan() async {
    if (state is ScanRunning) return null;
    state = ScanRunning(startedAt: DateTime.now().toUtc());
    final logger = AppLogger.instance;
    try {
      logger.i('options-income scan: requested');
      final sideInputs = await ref.read(scanSideInputsProvider.future);
      final orchestrator = await ref.read(scanOrchestratorProvider.future);
      final ownerUserId = await ref.read(currentUserIdProvider)();
      final profile = ref.read(optionsStrategyProfileProvider).value;
      if (profile == null) {
        throw StateError('profile_missing');
      }
      final approved = ref.read(approvedUnderlyingsProvider).value ?? const [];
      final plans = await ref.read(incomeStrategyPlansProvider.future);
      final leapsPositions =
          ref.read(leapsCallPositionsProvider).value ?? const [];
      PortfolioIncomeStrategySnapshot? portfolio;
      try {
        portfolio = await ref.read(portfolioIncomeStrategyProvider.future);
      } catch (_) {
        // Funding context is best-effort; the LEAPS lane still scans with
        // budget-only filtering when the snapshot is unavailable.
        portfolio = null;
      }
      final leapsTargets = buildLeapsScanTargets(
        plans: plans,
        positions: leapsPositions,
        portfolio: portfolio,
      );
      logger.d(
        'options-income scan: inputs '
        'approved=${approved.map((a) => a.symbol).join(",")} '
        'cash=${sideInputs.availableCash.amount} '
        '${sideInputs.availableCash.currency} '
        'holdings=${sideInputs.holdingsBySymbol} '
        'exposures=${sideInputs.exposureBySymbol}',
      );
      final inputs = ScanInputs(
        ownerUserId: ownerUserId,
        profile: profile,
        approved: approved,
        holdingsBySymbol: sideInputs.holdingsBySymbol,
        exposureBySymbol: sideInputs.exposureBySymbol,
        availableCash: sideInputs.availableCash,
        upcomingEarningsSymbols: const {},
        upcomingMacroEvent: false,
        eventDataAvailable: false,
        leapsTargets: leapsTargets,
      );
      final result = await orchestrator.run(inputs);
      logger.i(
        'options-income scan: completed '
        'scanId=${result.scanId} '
        'universe=${result.universe.join(",")} '
        'opportunities=${result.opportunities.length} '
        'rejected=${result.rejected.length} '
        'errors=${result.errors} '
        'warnings=${result.warnings}',
      );
      // Touch cached read providers so the UI rebinds without staleness.
      ref.invalidate(cachedOpportunitiesProvider);
      ref.invalidate(latestScanStateProvider);
      state = ScanSuccess(result: result);
      return result;
    } catch (e, st) {
      logger.e('options-income scan: failed', error: e, stackTrace: st);
      state = ScanFailure(error: e);
      return null;
    }
  }
}

final scanControllerProvider = NotifierProvider<ScanController, ScanState>(
  ScanController.new,
);
