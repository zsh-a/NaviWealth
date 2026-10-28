import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/current_user.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/auth/providers.dart' as auth;
import 'bcr_knowledge_providers.dart';

final bcrKnowledgeForegroundSyncProvider = Provider<BcrForegroundSync?>((ref) {
  final enabled = ref.watch(
    auth.domainOptInsProvider.select(
      (value) => value.value?.contains(DomainScope.knowledge) ?? false,
    ),
  );
  final owner = ref.watch(activeUserIdProvider);
  if (!enabled || owner == null) return null;
  final service = ref.watch(bcrKnowledgeSyncServiceProvider).value;
  if (service == null) return null;
  final driver = BcrForegroundSync(
    refresh: service.syncAll,
    cancel: service.cancelAll,
  );
  ref.onDispose(driver.stop);
  // Cache cleanup keeps connection settings. Offer a foreground rebuild as
  // soon as that cache disappears, with the service retaining retry policy.
  ref.listen(bcrKnowledgeSourcesProvider, (before, after) {
    if (!after.isLoading &&
        after.hasValue &&
        after.value!.length < (before?.value?.length ?? 0)) {
      unawaited(driver.check());
    }
  });
  ref.listen(bcrKnowledgeConnectionsProvider, (before, after) {
    if (!after.isLoading && after.hasValue) {
      final oldConnections = before?.value ?? [];
      final newConnections = after.value!;
      for (final old in oldConnections) {
        if (!newConnections.any((connection) => connection.id == old.id)) {
          service.cancelSource(old.id);
        }
      }
      final oldSignature = oldConnections
          .map((connection) => '${connection.id}:${connection.revision}')
          .join('|');
      final signature = newConnections
          .map((connection) => '${connection.id}:${connection.revision}')
          .join('|');
      if (signature != oldSignature) unawaited(driver.check());
    }
  });
  unawaited(
    Future<void>.microtask(() {
      if (ref.mounted) driver.start();
    }),
  );
  return driver;
});

/// Foreground opportunities only; the sync service owns single-flight, retry
/// deadlines and credentials. No second Navi SyncEngine or OS job is added.
class BcrForegroundSync with WidgetsBindingObserver {
  BcrForegroundSync({
    required this.refresh,
    required this.cancel,
    this.interval = const Duration(seconds: 30),
  });
  final Future<void> Function() refresh;
  final void Function() cancel;
  final Duration interval;
  bool _started = false;
  bool _foreground = false;
  bool _stopped = false;
  Timer? _timer;
  Future<void>? _inFlight;

  void start() {
    if (_started || _stopped) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    if (state == null || state == AppLifecycleState.resumed) _resume();
  }

  void _resume() {
    if (!_started || _foreground) return;
    _foreground = true;
    _timer = Timer.periodic(interval, (_) => unawaited(check()));
    unawaited(check());
  }

  Future<void> check() {
    if (!_foreground || !_started || _stopped) return Future.value();
    return _inFlight ??= refresh()
        .catchError((Object _) {})
        .whenComplete(() => _inFlight = null);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resume();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _foreground = false;
      _timer?.cancel();
      cancel();
    }
  }

  void stop() {
    _stopped = true;
    _started = false;
    _foreground = false;
    _timer?.cancel();
    cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}
