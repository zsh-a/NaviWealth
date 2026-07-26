import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'package:naviwealth/core/logging/app_logger.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import '../data/providers.dart';
import '../domain/options_strategy_profile.dart';
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

class ScanController extends StateNotifier<ScanState> {
  ScanController(this._ref) : super(const ScanIdle());

  final Ref _ref;

  Future<ScanResult?> runScan() async {
    if (state is ScanRunning) return null;
    state = ScanRunning(startedAt: DateTime.now().toUtc());
    final logger = AppLogger.instance;
    try {
      logger.i('options-income scan: requested');
      final sideInputs = await _ref.read(scanSideInputsProvider.future);
      final orchestrator = await _ref.read(scanOrchestratorProvider.future);
      final ownerUserId = await _ref.read(currentUserIdProvider)();
      final profile = _ref.read(optionsStrategyProfileProvider).value;
      if (profile == null) {
        throw StateError('profile_missing');
      }
      final approved = _ref.read(approvedUnderlyingsProvider).value ?? const [];
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
      _ref.invalidate(cachedOpportunitiesProvider);
      _ref.invalidate(latestScanStateProvider);
      state = ScanSuccess(result: result);
      return result;
    } catch (e, st) {
      logger.e('options-income scan: failed', error: e, stackTrace: st);
      state = ScanFailure(error: e);
      return null;
    }
  }

  void clear() {
    state = const ScanIdle();
  }

  /// Quick accessor for the OptionsStrategyProfile cast used by `runScan`
  /// callers that want to short-circuit when the profile is missing.
  OptionsStrategyProfile? get currentProfile =>
      _ref.read(optionsStrategyProfileProvider).value;
}

final scanControllerProvider = StateNotifierProvider<ScanController, ScanState>(
  (ref) {
    return ScanController(ref);
  },
);
