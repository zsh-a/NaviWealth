import 'dart:async';

/// Network responses carry a revision; only current responses may start a
/// commit. Local writes are serialized so an already-started write finishes
/// before logout or another identity replaces it.
class SessionTransitions {
  int _revision = 0;
  int? _pending;
  bool _disposed = false;
  Future<void> _writes = Future.value();

  int get revision => _revision;
  bool get isPending => _pending != null;

  /// Riverpod may rebuild a notifier instance. Keep the write queue and advance
  /// the revision so neither queued nor late work from its old build can start.
  int restart() {
    _disposed = false;
    _pending = null;
    return ++_revision;
  }

  int begin() {
    if (_disposed) throw StateError('Session transitions are disposed');
    _pending = ++_revision;
    return _revision;
  }

  bool isCurrent(int revision) => !_disposed && revision == _revision;

  void finish(int revision) {
    if (_pending == revision) _pending = null;
  }

  Future<T?> commit<T>(int revision, Future<T> Function() write) async {
    final previous = _writes;
    final completion = Completer<void>();
    _writes = completion.future;
    try {
      await previous;
      if (!isCurrent(revision)) return null;
      return await write();
    } finally {
      completion.complete();
    }
  }

  void dispose() {
    _disposed = true;
    _pending = null;
    _revision++;
  }
}
