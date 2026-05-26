import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/providers.dart';
import '../../../data/domain/asset.dart';
import '../../investment/data/providers.dart' show holdingsSnapshotProvider;
import '../domain/concentration_risk.dart';
import '../domain/equity_allocation.dart';
import '../domain/equity_classification.dart';
import 'equity_assets_repository.dart';
import 'risk_threshold_preferences.dart';

/// Read-only repository for stock / ETF / mutual-fund rows. Used by the
/// analytics layer until a dedicated equity write repository ships.
final equityAssetsRepositoryProvider = FutureProvider<EquityAssetsRepository>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return EquityAssetsRepository(db);
});

/// Live list of all equity-class assets the user holds in the database.
final equityAssetsStreamProvider = StreamProvider.autoDispose<List<Asset>>((
  ref,
) async* {
  final repo = await ref.watch(equityAssetsRepositoryProvider.future);
  yield* repo.watchAll();
});

/// Manual classification overrides. The current binding is in-memory only
/// — overrides reset on app restart. A persistent store will land in a
/// follow-up alongside the override editing UI.
final equityClassificationOverrideStoreProvider =
    Provider<InMemoryEquityClassificationOverrideStore>(
      (ref) => InMemoryEquityClassificationOverrideStore(),
    );

/// Default classifier composing the asset row + the override store.
final equityClassifierProvider = Provider<EquityClassifier>((ref) {
  final overrides = ref.watch(equityClassificationOverrideStoreProvider);
  return DefaultEquityClassifier(overrides: overrides);
});

/// Per-asset thresholds for [MarketCapBucket]. Defaults to the FIR-53
/// product values (200B / 2B). Overridable from settings later.
final marketCapThresholdsProvider = Provider<MarketCapThresholds>(
  (ref) => MarketCapThresholds.defaults(),
);

/// User's selected base currency. Until the settings repository exposes
/// its row through Riverpod, fall back to the dashboard default so the
/// totals row has *something* to label itself with.
final analyticsBaseCurrencyProvider = Provider<String>((ref) => 'CNY');

/// Composite analytics view for a single allocation [dimension]. Watches
/// the holdings snapshot, the asset list, and the classifier; recomputes
/// the aggregation whenever any input changes.
final equityAllocationViewProvider = FutureProvider.autoDispose
    .family<EquityAllocationView, EquityAllocationDimension>((
      ref,
      dimension,
    ) async {
      final snapshots = await ref.watch(holdingsSnapshotProvider.future);
      final assets = await ref.watch(equityAssetsStreamProvider.future);
      final classifier = ref.watch(equityClassifierProvider);
      final baseCurrency = ref.watch(analyticsBaseCurrencyProvider);
      final thresholds = ref.watch(marketCapThresholdsProvider);

      final assetById = <String, Asset>{for (final a in assets) a.id: a};

      return const EquityAllocationService().aggregate(
        snapshots: snapshots.values,
        assetLookup: (id) => assetById[id],
        classifier: classifier,
        dimension: dimension,
        baseCurrency: baseCurrency,
        asOf: DateTime.now().toUtc(),
        thresholds: thresholds,
      );
    });

/// Concentration-risk alerts for the current portfolio. Re-evaluates when
/// holdings, asset metadata, classifier, or threshold settings change.
final concentrationAlertsProvider =
    FutureProvider.autoDispose<List<ConcentrationAlert>>((ref) async {
      final snapshots = await ref.watch(holdingsSnapshotProvider.future);
      final assets = await ref.watch(equityAssetsStreamProvider.future);
      final classifier = ref.watch(equityClassifierProvider);
      final thresholds = ref.watch(concentrationThresholdsProvider);

      final assetById = <String, Asset>{for (final a in assets) a.id: a};

      return const ConcentrationRiskService().detect(
        snapshots: snapshots.values,
        assetLookup: (id) => assetById[id],
        classifier: classifier,
        thresholds: thresholds,
      );
    });
