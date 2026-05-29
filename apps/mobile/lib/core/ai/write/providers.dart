/// Wave 35 / 39 — Riverpod surface for the persisted undo + AI-touched
/// stores.
///
/// Provides:
///   - `undoStackProvider` — singleton [DriftUndoStack] scoped to the
///     current user.
///   - `undoEntriesStreamProvider` — stream of newest-first persisted
///     entries; the persistent undo banner watches this.
///   - `aiTouchedStoreProvider` — singleton [DriftAiTouchedStore].
///   - `aiTouchedAtProvider((entityType, entityId))` — autoDispose
///     family that detail pages watch to render `AiSourceMark`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/providers.dart';
import '../../auth/current_user.dart';
import 'drift_ai_touched_store.dart';
import 'drift_undo_stack.dart';

final undoStackProvider = Provider<DriftUndoStack?>((ref) {
  final dbAsync = ref.watch(appDatabaseProvider);
  final ownerUserId = ref.watch(activeUserIdProvider);
  return dbAsync.when(
    data: (db) {
      final stack = DriftUndoStack(db, ownerUserId: ownerUserId);
      ref.onDispose(stack.dispose);
      return stack;
    },
    loading: () => null,
    error: (_, _) => null,
  );
});

final undoEntriesStreamProvider = StreamProvider<List<PersistedUndoEntry>>((
  ref,
) async* {
  final stack = ref.watch(undoStackProvider);
  if (stack == null) {
    yield const <PersistedUndoEntry>[];
    return;
  }
  yield* stack.watchAll();
});

/// Wave 39 — owner-scoped [DriftAiTouchedStore]. Disposed when the
/// user logs out or the DB closes.
final aiTouchedStoreProvider = Provider<DriftAiTouchedStore?>((ref) {
  final dbAsync = ref.watch(appDatabaseProvider);
  final ownerUserId = ref.watch(activeUserIdProvider);
  return dbAsync.when(
    data: (db) {
      final store = DriftAiTouchedStore(db, ownerUserId: ownerUserId);
      ref.onDispose(store.dispose);
      return store;
    },
    loading: () => null,
    error: (_, _) => null,
  );
});

/// Wave 39 — detail-page surface. `family((entityType, entityId))`
/// streams the latest [AiTouchedEntity] (or null). Auto-dispose so
/// off-screen detail pages release their subscription.
final aiTouchedAtProvider = StreamProvider.autoDispose
    .family<AiTouchedEntity?, ({String entityType, String entityId})>((
      ref,
      key,
    ) async* {
      final store = ref.watch(aiTouchedStoreProvider);
      if (store == null) {
        yield null;
        return;
      }
      yield* store.watchLatest(key.entityType, key.entityId);
    });
