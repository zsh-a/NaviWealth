import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:naviwealth/core/logging/app_logger.dart';
import 'package:naviwealth/features/finance/data/market/exceptions.dart';
import 'package:naviwealth/features/finance/data/market/http/clock.dart';
import 'package:naviwealth/features/finance/data/repositories/price_repository.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/market_data_service.dart';
import 'package:naviwealth/features/finance/market/domain/quote.dart';

import 'fx_rate_sync_service.dart';

/// Reason that triggered a coordinator cycle. Used in logs and metrics so
/// "why did the app just fire a burst of quote calls" stays answerable
/// from a trace.
enum PriceSyncReason {
  /// Initial sync fired by [PriceSyncCoordinator.start].
  cold,

  /// `didChangeAppLifecycleState(resumed)` fired after a background→foreground transition.
  appResume,

  /// Daily foreground timer.
  periodic,

  /// External caller: pull-to-refresh, route hook, settings page button.
  manual,

  /// Debounced mutation hook: a repository wrote something that may affect holdings.
  mutation,
}

enum PriceSyncStatus { idle, syncing, fresh, failed }

class PriceSyncStatusEvent {
  const PriceSyncStatusEvent({
    required this.status,
    required this.at,
    this.lastSuccessAt,
    this.lastError,
  });

  final PriceSyncStatus status;
  final DateTime at;
  final DateTime? lastSuccessAt;
  final String? lastError;
}

class PriceSyncStatusBus {
  PriceSyncStatusBus({PriceSyncStatusEvent? initial})
    : _current =
          initial ??
          PriceSyncStatusEvent(
            status: PriceSyncStatus.idle,
            at: DateTime.now(),
          );

  final StreamController<PriceSyncStatusEvent> _ctrl =
      StreamController<PriceSyncStatusEvent>.broadcast();
  PriceSyncStatusEvent _current;

  Stream<PriceSyncStatusEvent> get stream => _ctrl.stream;

  PriceSyncStatusEvent get current => _current;

  void emit(PriceSyncStatusEvent event) {
    _current = event;
    if (!_ctrl.isClosed) _ctrl.add(event);
  }

  Future<void> close() => _ctrl.close();
}

/// Reads the current set of "warmable" assets — securities + crypto + bonds
/// whose symbols can be quoted by the live provider chain. Manual-valuation
/// types (cash, deposits, wealth products, real estate) are excluded; the
/// resolver short-circuits them anyway and forcing a provider lookup would
/// just burn API quota.
typedef HeldAssetsReader = Future<List<Asset>> Function();

/// Reads the active (base, account-currency-set) tuple for the FX pass.
/// Returns `null` to skip FX sync this cycle.
typedef FxSyncInputsReader = Future<FxSyncInputs?> Function();

class FxSyncInputs {
  const FxSyncInputs({required this.baseCurrency, required this.currencies});
  final String baseCurrency;
  final Set<String> currencies;
}

/// Opportunistically warms the [MarketDataService] quote cache and the FX
/// rate store on natural app touchpoints (cold start, resume, periodic
/// timer, manual trigger).
///
/// The coordinator does **not** write to the synced `prices` ledger in
/// Phase D — cache writes are local-only via the existing
/// `CompositeMarketDataService` pipeline. Phase E adds optional
/// daily-snapshot persistence behind a settings toggle.
class PriceSyncCoordinator with WidgetsBindingObserver {
  PriceSyncCoordinator({
    required MarketDataService market,
    required FxRateSyncService fxSync,
    required HeldAssetsReader heldAssets,
    required FxSyncInputsReader fxInputs,
    PriceRepository? prices,
    bool Function()? writeDailySnapshots,
    Duration interval = const Duration(days: 1),
    Clock clock = const SystemClock(),
    AppLogger? logger,
    PriceSyncStatusBus? statusBus,
  }) : _market = market,
       _fxSync = fxSync,
       _heldAssets = heldAssets,
       _fxInputs = fxInputs,
       _prices = prices,
       _writeDailySnapshots = writeDailySnapshots ?? (() => false),
       _interval = interval,
       _clock = clock,
       _logger = logger ?? AppLogger.instance,
       _statusBus = statusBus;

  final MarketDataService _market;
  final FxRateSyncService _fxSync;
  final HeldAssetsReader _heldAssets;
  final FxSyncInputsReader _fxInputs;
  final PriceRepository? _prices;
  final bool Function() _writeDailySnapshots;
  final Duration _interval;
  final Clock _clock;
  final AppLogger _logger;
  final PriceSyncStatusBus? _statusBus;

  Timer? _timer;
  Timer? _mutationDebounce;
  bool _started = false;
  bool _foreground = true;
  bool _paused = false;
  Future<void>? _inFlight;

  /// When the last successful cycle completed. Exposed so tests / metrics
  /// can assert progress.
  DateTime? lastSuccessAt;

  /// Total number of completed cycles since [start]. Includes errored runs.
  int cycleCount = 0;

  /// Idempotent. Safe to call from bootstrap.
  void start() {
    if (_started) return;
    _started = true;
    _logger.i(
      'price_sync_coordinator: started (interval=${_interval.inMinutes}min)',
    );
    WidgetsBinding.instance.addObserver(this);
    _restartTimer();
    unawaited(triggerNow(reason: PriceSyncReason.cold));
  }

  void stop() {
    if (!_started) return;
    _started = false;
    _logger.i('price_sync_coordinator: stopped');
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _timer = null;
    _mutationDebounce?.cancel();
    _mutationDebounce = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (!_foreground) {
          _foreground = true;
          _logger.d('price_sync_coordinator: app resumed');
          if (!_paused) {
            unawaited(triggerNow(reason: PriceSyncReason.appResume));
          }
        }
        _restartTimer();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _foreground = false;
        _timer?.cancel();
        _timer = null;
    }
  }

  void pause() {
    _paused = true;
    _logger.i('price_sync_coordinator: paused');
  }

  void resume() {
    if (_paused) {
      _paused = false;
      _logger.i('price_sync_coordinator: resumed');
      unawaited(triggerNow(reason: PriceSyncReason.manual));
    }
  }

  /// Debounced 2s mutation hook. Repositories that change holdings
  /// (manual valuation, trade post, dividend) call this; rapid bursts
  /// fold into a single cycle.
  void onMutationAffectingHoldings() {
    _mutationDebounce?.cancel();
    _mutationDebounce = Timer(const Duration(seconds: 2), () {
      unawaited(triggerNow(reason: PriceSyncReason.mutation));
    });
  }

  /// Run a sync cycle now. Concurrent calls share the same in-flight
  /// future to avoid fan-out bursts.
  Future<void> triggerNow({
    PriceSyncReason reason = PriceSyncReason.manual,
  }) async {
    if (_paused) return;
    final existing = _inFlight;
    if (existing != null) return existing;
    final future = _runCycle(reason);
    _inFlight = future;
    try {
      await future;
    } finally {
      _inFlight = null;
    }
  }

  Future<void> _runCycle(PriceSyncReason reason) async {
    cycleCount++;
    _logger.d('price_sync_coordinator: cycle reason=${reason.name}');
    _emitStatus(PriceSyncStatus.syncing);
    try {
      await _warmQuotes();
      await _syncFx();
      lastSuccessAt = _clock.now();
      _emitStatus(PriceSyncStatus.fresh, lastSuccessAt: lastSuccessAt);
      _logger.d('price_sync_coordinator: cycle ok');
    } catch (e, st) {
      _emitStatus(PriceSyncStatus.failed, lastError: e.toString());
      _logger.w(
        'price_sync_coordinator: cycle error (non-fatal)',
        error: e,
        stackTrace: st,
      );
    }
  }

  void _emitStatus(
    PriceSyncStatus status, {
    DateTime? lastSuccessAt,
    String? lastError,
  }) {
    _statusBus?.emit(
      PriceSyncStatusEvent(
        status: status,
        at: _clock.now(),
        lastSuccessAt: lastSuccessAt ?? this.lastSuccessAt,
        lastError: lastError,
      ),
    );
  }

  Future<void> _warmQuotes() async {
    final assets = await _heldAssets();
    var warmed = 0;
    var snapshots = 0;
    final canPersist = _prices != null && _writeDailySnapshots();
    for (final asset in assets) {
      if (!_isWarmable(asset)) continue;
      final market = assetMarketFromWire(asset.market);
      try {
        final resp = await _market.getQuote(asset.symbol, market: market);
        warmed++;
        if (canPersist && resp.freshness == DataFreshness.live) {
          final wrote = await _maybeWriteDailySnapshot(asset, resp);
          if (wrote) snapshots++;
        }
      } on MarketDataException catch (e) {
        // Provider chain already handled fallback; this is the
        // "nothing in any chain succeeded" case. Skip and continue.
        _logger.d('warm: ${asset.symbol} skipped: $e');
      }
    }
    if (warmed > 0) {
      _logger.d(
        'price_sync_coordinator: warmed $warmed quote(s); '
        'wrote $snapshots daily snapshot(s)',
      );
    }
  }

  /// Phase E. Writes one `auto:<provider>` row into the `prices` ledger per
  /// UTC day per held asset, skipping when:
  ///   - the same UTC day already has a `manual*` row (user-curated wins)
  ///   - the same UTC day already has an `auto:*` row (idempotent)
  ///   - the quote's currency doesn't match the asset's preferred quote
  ///     currency (avoids cross-currency pollution).
  ///
  /// Returns true when a row was inserted.
  Future<bool> _maybeWriteDailySnapshot(
    Asset asset,
    MarketResponse<Quote> resp,
  ) async {
    final prices = _prices;
    if (prices == null) return false;
    if (resp.data.currency.toUpperCase() != asset.currency.toUpperCase()) {
      return false;
    }
    final today = _floorToUtcDay(_clock.now());
    final tomorrow = today.add(const Duration(days: 1));
    final existing = await prices.latestAt(
      unit: asset.id,
      quoteCurrency: asset.currency,
      asOf: tomorrow.subtract(const Duration(microseconds: 1)),
    );
    if (existing != null) {
      final existingDay = _floorToUtcDay(existing.observedOn);
      if (!existingDay.isBefore(today)) {
        // Already have a row for today (manual or auto). Skip.
        return false;
      }
    }
    try {
      await prices.record(
        unit: asset.id,
        quoteCurrency: asset.currency,
        observedOn: today,
        perUnit: resp.data.price,
        source: 'auto:${resp.source}',
      );
      return true;
    } catch (e, st) {
      _logger.w(
        'price_sync_coordinator: snapshot write failed for ${asset.id}',
        error: e,
        stackTrace: st,
      );
      return false;
    }
  }

  static DateTime _floorToUtcDay(DateTime d) {
    final u = d.toUtc();
    return DateTime.utc(u.year, u.month, u.day);
  }

  Future<void> _syncFx() async {
    final inputs = await _fxInputs();
    if (inputs == null) return;
    if (inputs.currencies.isEmpty) return;
    try {
      final synced = await _fxSync.syncRates(
        baseCurrency: inputs.baseCurrency,
        accountCurrencies: inputs.currencies,
      );
      if (synced > 0) {
        _logger.d('price_sync_coordinator: fx synced $synced pair(s)');
      }
    } catch (e, st) {
      _logger.w(
        'price_sync_coordinator: fx sync failed (non-fatal)',
        error: e,
        stackTrace: st,
      );
    }
  }

  bool _isWarmable(Asset asset) {
    if (asset.symbol.trim().isEmpty) return false;
    if (kManualValuationAssetTypes.contains(asset.type)) return false;
    if (asset.type == AssetType.custom) return false;
    if (asset.type == AssetType.realEstate) return false;
    if (asset.type == AssetType.vehicle) return false;
    if (asset.type == AssetType.commodity) return false;
    return true;
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(
      _interval,
      (_) => unawaited(triggerNow(reason: PriceSyncReason.periodic)),
    );
  }
}
