/// Wave 35 — Riverpod surface for the persisted undo stack.
///
/// Provides:
///   - `undoStackProvider` — singleton [DriftUndoStack] scoped to the
///     current user.
///   - `undoEntriesStreamProvider` — stream of newest-first persisted
///     entries; the persistent undo banner watches this.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/db/providers.dart';
import '../../auth/providers.dart';
import 'drift_undo_stack.dart';

final undoStackProvider = Provider<DriftUndoStack?>((ref) {
  final dbAsync = ref.watch(appDatabaseProvider);
  final auth = ref.watch(authSessionProvider);
  return dbAsync.when(
    data: (db) {
      final stack = DriftUndoStack(db, ownerUserId: auth?.userId);
      ref.onDispose(stack.dispose);
      return stack;
    },
    loading: () => null,
    error: (_, _) => null,
  );
});

final undoEntriesStreamProvider =
    StreamProvider<List<PersistedUndoEntry>>((ref) async* {
  final stack = ref.watch(undoStackProvider);
  if (stack == null) {
    yield const <PersistedUndoEntry>[];
    return;
  }
  yield* stack.watchAll();
});
