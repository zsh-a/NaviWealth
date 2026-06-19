/// Dispatch for structured undo entries persisted in [DriftUndoStack].
///
/// Storage only knows `kind + payload`; this layer owns the reversible-write
/// lookup. Concrete reverters are registered by app/domain composition so
/// `core/ai/write` stays domain-neutral.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'drift_undo_stack.dart';
import 'providers.dart';

typedef PersistedUndoReverter = Future<void> Function(PersistedUndoEntry entry);

enum PersistedUndoDispatchStatus { applied, missing, expired, unsupported }

class PersistedUndoDispatchResult {
  const PersistedUndoDispatchResult(this.status, {this.entry});

  final PersistedUndoDispatchStatus status;
  final PersistedUndoEntry? entry;

  bool get didApply => status == PersistedUndoDispatchStatus.applied;
}

class PersistedUndoDispatcher {
  PersistedUndoDispatcher({
    required DriftUndoStack stack,
    required Map<String, PersistedUndoReverter> reverters,
    DateTime Function()? now,
  }) : _stack = stack,
       _reverters = reverters,
       _now = now ?? DateTime.now;

  final DriftUndoStack _stack;
  final Map<String, PersistedUndoReverter> _reverters;
  final DateTime Function() _now;

  Future<PersistedUndoDispatchResult> undo(String token) async {
    final entry = await _stack.take(token);
    if (entry == null) {
      return const PersistedUndoDispatchResult(
        PersistedUndoDispatchStatus.missing,
      );
    }
    final expiresAt = entry.expiresAt;
    if (expiresAt != null && !expiresAt.isAfter(_now().toUtc())) {
      return PersistedUndoDispatchResult(
        PersistedUndoDispatchStatus.expired,
        entry: entry,
      );
    }
    final reverter = _reverters[entry.kind];
    if (reverter == null) {
      return PersistedUndoDispatchResult(
        PersistedUndoDispatchStatus.unsupported,
        entry: entry,
      );
    }
    await reverter(entry);
    return PersistedUndoDispatchResult(
      PersistedUndoDispatchStatus.applied,
      entry: entry,
    );
  }
}

final persistedUndoRevertersProvider =
    Provider<Map<String, PersistedUndoReverter>>((ref) {
      return const <String, PersistedUndoReverter>{};
    });

final persistedUndoDispatcherProvider = Provider<PersistedUndoDispatcher?>((
  ref,
) {
  final stack = ref.watch(undoStackProvider);
  if (stack == null) return null;
  return PersistedUndoDispatcher(
    stack: stack,
    reverters: ref.watch(persistedUndoRevertersProvider),
  );
});
