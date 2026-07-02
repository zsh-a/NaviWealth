/// §5.10.1 Layer 3 — local store for "user dismissed this insight".
///
/// The dashboard re-derives insights every time the underlying data
/// changes, so a card the user explicitly dismissed would otherwise
/// pop right back. This store records "(kind, scopeHash) was hidden
/// at T" so the feed provider can filter the list before rendering.
///
/// Backed by [SharedPreferences] for now — the §5.10.8 plan calls
/// for a Drift table (`dismissed_insight_keys`) so the dismissal
/// state survives a wipe / reinstall through cloud sync, but the
/// shared-prefs MVP keeps the schema bump out of S3 and avoids the
/// build_runner regeneration churn. A follow-up can promote it
/// without breaking this surface (the public API does not expose
/// the storage backend).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/insight_models.dart';

/// Composite key the store keeps. [scopeHash] disambiguates two
/// instances of the same kind (e.g. two duplicate-charge clusters
/// against different merchants) so dismissing one doesn't suppress
/// the others.
class DismissedInsightKey {
  const DismissedInsightKey({required this.kind, required this.scopeHash});

  final InsightKind kind;

  /// Caller-provided stable identifier — typically derived from the
  /// fields that make the insight unique (merchant key + amount, the
  /// month being summarised, etc.). Empty string is allowed and
  /// means "any insight of this kind".
  final String scopeHash;

  String get _serialised => '${kind.name}|$scopeHash';

  @override
  bool operator ==(Object other) =>
      other is DismissedInsightKey &&
      other.kind == kind &&
      other.scopeHash == scopeHash;

  @override
  int get hashCode => Object.hash(kind, scopeHash);
}

class DismissedInsightsStore {
  DismissedInsightsStore(this._prefs);

  final SharedPreferences _prefs;

  static const String _prefsKey = 'dismissed_insight_keys.v1';

  /// Streams the current dismissed set so providers can rebuild when
  /// it changes. The first emission is synchronous-ish (next event
  /// loop turn) so dependents settle promptly.
  Stream<Set<DismissedInsightKey>> watch() {
    final controller = StreamController<Set<DismissedInsightKey>>.broadcast();
    void emit() => controller.add(_load());
    _listeners.add(emit);
    controller.onCancel = () => _listeners.remove(emit);
    scheduleMicrotask(emit);
    return controller.stream;
  }

  Set<DismissedInsightKey> currentSnapshot() => _load();

  /// Marks [key] dismissed. No-op if already dismissed.
  Future<void> dismiss(DismissedInsightKey key) async {
    final current = _load();
    if (!current.add(key)) return;
    await _save(current);
    _notify();
  }

  /// Clears every dismissal (test seam + future "show me everything
  /// again" toggle).
  Future<void> clearAll() async {
    await _prefs.remove(_prefsKey);
    _notify();
  }

  Set<DismissedInsightKey> _load() {
    final raw = _prefs.getStringList(_prefsKey) ?? const <String>[];
    final out = <DismissedInsightKey>{};
    for (final entry in raw) {
      final parts = entry.split('|');
      if (parts.length < 2) continue;
      final kind = _kindFromName(parts.first);
      if (kind == null) continue;
      out.add(
        DismissedInsightKey(kind: kind, scopeHash: parts.sublist(1).join('|')),
      );
    }
    return out;
  }

  Future<void> _save(Set<DismissedInsightKey> set) async {
    await _prefs.setStringList(
      _prefsKey,
      set.map((k) => k._serialised).toList(growable: false),
    );
  }

  static InsightKind? _kindFromName(String name) {
    for (final k in InsightKind.values) {
      if (k.name == name) return k;
    }
    return null;
  }

  // Single-process change broadcaster. `watch()` emits when any
  // [dismiss]/[clearAll] runs in the same isolate.
  static final Set<void Function()> _listeners = <void Function()>{};
  void _notify() {
    for (final l in List<void Function()>.from(_listeners)) {
      l();
    }
  }
}

final dismissedInsightsStoreProvider = Provider<DismissedInsightsStore>(
  (ref) => DismissedInsightsStore(ref.watch(sharedPreferencesProvider)),
);

/// Live set of dismissed insight keys. Providers that compose the
/// feed can filter against this snapshot.
final dismissedInsightKeysProvider = StreamProvider<Set<DismissedInsightKey>>((
  ref,
) {
  return ref.watch(dismissedInsightsStoreProvider).watch();
});
