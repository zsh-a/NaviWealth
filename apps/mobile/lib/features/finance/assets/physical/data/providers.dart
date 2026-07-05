import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/outbox_provider.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';

import 'physical_asset.dart';
import 'physical_asset_repository.dart';

final physicalAssetRepositoryProvider = FutureProvider<PhysicalAssetRepository>(
  (ref) async {
    final db = await ref.watch(appDatabaseProvider.future);
    final outbox = await ref.watch(outboxStoreProvider.future);
    final stamper = await ref.watch(mutationStamperProvider.future);
    final jeRepo = await ref.watch(journalEntryRepositoryProvider.future);
    final priceRepo = await ref.watch(priceRepositoryProvider.future);
    return PhysicalAssetRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
      priceRepo: priceRepo,
      journalEntryRepo: jeRepo,
    );
  },
);

final physicalAssetsListProvider =
    StreamProvider.autoDispose<List<PhysicalAsset>>((ref) async* {
      final repo = await ref.watch(physicalAssetRepositoryProvider.future);
      yield* repo.watchAll();
    });

/// Single-asset detail. Re-fires whenever the underlying list changes so
/// the detail page picks up edits made elsewhere in the app.
final physicalAssetDetailProvider = FutureProvider.autoDispose
    .family<PhysicalAsset?, String>((ref, id) async {
      final list = await ref.watch(physicalAssetsListProvider.future);
      for (final a in list) {
        if (a.id == id) return a;
      }
      // Fallback: the row could be tombstoned but referenced from the URL.
      // Read directly so the detail page can surface a "not found" state.
      final repo = await ref.watch(physicalAssetRepositoryProvider.future);
      return repo.getById(id);
    });

final physicalAssetValuationHistoryProvider = FutureProvider.autoDispose
    .family<List<ValuationPoint>, String>((ref, id) async {
      // Recompute when the list rebuilds so a new valuationAdjust transaction
      // shows up immediately.
      await ref.watch(physicalAssetsListProvider.future);
      final repo = await ref.watch(physicalAssetRepositoryProvider.future);
      return repo.getValuationHistory(id);
    });
