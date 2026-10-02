import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../design_system/preferences/theme_preferences.dart';
import '../auth/current_user.dart';

final localFormDraftStoreProvider = Provider<LocalFormDraftStore?>((ref) {
  final owner = ref.watch(activeUserIdProvider);
  return owner == null
      ? null
      : LocalFormDraftStore(ref.watch(sharedPreferencesProvider), owner: owner);
});

/// Owner-scoped, device-local input only. These snapshots never mutate domain
/// entities or enter sync. Hosts decide how to apply a restored JSON payload.
class LocalFormDraftStore {
  LocalFormDraftStore(this.preferences, {required this.owner});
  final SharedPreferences preferences;
  final String owner;
  static final _queues = Expando<_DraftWriteQueue>();
  _DraftWriteQueue get _queueState =>
      _queues[preferences] ??= _DraftWriteQueue();
  static const prefix = 'naviwealth.forms.drafts.';

  String get _ownerPrefix => '$prefix${base64Url.encode(utf8.encode(owner))}.';
  String _key(String form) => '$_ownerPrefix${Uri.encodeComponent(form)}';

  String _generationKey(String domain) => '$_ownerPrefix-reset.$domain';
  int generation(String form) =>
      preferences.getInt(_generationKey(form.split('.').first)) ?? 0;

  Future<void> clearDomain(String domain) => _queue(() async {
    final domainPrefix = '$_ownerPrefix${Uri.encodeComponent(domain)}.';
    for (final key in preferences.getKeys().where(
      (key) => key.startsWith(domainPrefix),
    )) {
      await preferences.remove(key);
    }
    final generationKey = _generationKey(domain);
    await preferences.setInt(
      generationKey,
      (preferences.getInt(generationKey) ?? 0) + 1,
    );
  });

  Map<String, Object?>? read(String form) {
    final raw = preferences.getString(_key(form));
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic> || json['version'] != 1) return null;
      final savedAt = DateTime.tryParse(json['savedAt'] as String? ?? '');
      if (savedAt == null ||
          DateTime.now().difference(savedAt) > const Duration(days: 7) ||
          savedAt.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
        return null;
      }
      final payload = json['payload'];
      return payload is Map<String, dynamic>
          ? Map<String, Object?>.from(payload)
          : null;
    } on Object {
      return null;
    }
  }

  Future<void> write(String form, Map<String, Object?> payload) {
    final raw = jsonEncode({
      'version': 1,
      'savedAt': DateTime.now().toUtc().toIso8601String(),
      'payload': payload,
    });
    if (raw.length > 65536) return Future<void>.value();
    return _queue(() async {
      await preferences.setString(_key(form), raw);
    });
  }

  Future<void> clear(String form) => _queue(() async {
    await preferences.remove(_key(form));
  });

  Future<void> _queue(Future<void> Function() action) {
    final queue = _queueState;
    final write = queue.pending.then((_) => action());
    queue.pending = write.catchError((Object _) {});
    return write;
  }
}

class _DraftWriteQueue {
  Future<void> pending = Future<void>.value();
}

/// Debounces typing, flushes on navigation/backgrounding, and cancels pending
/// writes before clearing a saved/discarded form. Hosts retain business guards.
class LocalFormDraftSession {
  LocalFormDraftSession(this.store, this.form)
    : pending = store.read(form),
      _generation = store.generation(form);
  final LocalFormDraftStore store;
  final String form;
  final int _generation;
  Map<String, Object?>? pending;
  Map<String, Object?>? _latest;
  String? _signature;
  Timer? _timer;
  bool _closed = false;

  void capture(Map<String, Object?> payload) {
    if (_closed || pending != null || _generation != store.generation(form)) {
      return;
    }
    final signature = jsonEncode(payload);
    if (_signature == signature) return;
    _signature = signature;
    _latest = payload;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 200), flush);
  }

  void accept() => pending = null;

  void discardPending() {
    pending = null;
    unawaited(store.clear(form).catchError((Object _) {}));
  }

  void flush() {
    _timer?.cancel();
    final latest = _latest;
    _latest = null;
    if (latest != null && !_closed && _generation == store.generation(form)) {
      unawaited(store.write(form, latest).catchError((Object _) {}));
    }
  }

  void complete() {
    _closed = true;
    _timer?.cancel();
    _latest = null;
    unawaited(store.clear(form).catchError((Object _) {}));
  }

  void dispose() {
    flush();
    _closed = true;
  }
}
