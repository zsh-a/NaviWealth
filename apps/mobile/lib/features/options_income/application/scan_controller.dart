import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'package:naviwealth/core/sync/mutation_context.dart';
import '../../../domain/values/money.dart';
import '../data/providers.dart';
import '../domain/options_strategy_profile.dart';
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

  Future<ScanResult?> runScan({
    required Money availableCash,
    Map<String, int> holdingsBySymbol = const {},
    Map<String, Decimal> exposureBySymbol = const {},
    Set<String> upcomingEarningsSymbols = const {},
    bool upcomingMacroEvent = false,
  }) async {
    if (state is ScanRunning) return null;
    state = ScanRunning(startedAt: DateTime.now().toUtc());
    try {
      final orchestrator = await _ref.read(scanOrchestratorProvider.future);
      final ownerUserId = await _ref.read(currentUserIdProvider)();
      final profile = _ref.read(optionsStrategyProfileProvider).value;
      if (profile == null) {
        throw StateError('profile_missing');
      }
      final approved = _ref.read(approvedUnderlyingsProvider).value ?? const [];
      final inputs = ScanInputs(
        ownerUserId: ownerUserId,
        profile: profile,
        approved: approved,
        holdingsBySymbol: holdingsBySymbol,
        exposureBySymbol: exposureBySymbol,
        availableCash: availableCash,
        upcomingEarningsSymbols: upcomingEarningsSymbols,
        upcomingMacroEvent: upcomingMacroEvent,
      );
      final result = await orchestrator.run(inputs);
      // Touch cached read providers so the UI rebinds without staleness.
      _ref.invalidate(cachedOpportunitiesProvider);
      _ref.invalidate(latestScanStateProvider);
      state = ScanSuccess(result: result);
      return result;
    } catch (e) {
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
