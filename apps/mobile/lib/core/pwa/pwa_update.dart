import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pwa_update_stub.dart'
    if (dart.library.js_interop) 'pwa_update_web.dart';

/// Bridge to the browser service worker registered by `web/index.html`.
///
/// The web implementation talks to `window.naviwealthPwa` via JS interop;
/// every other platform gets a no-op so call sites can stay platform-agnostic.
/// Always check [isSupported] before surfacing update UI — on iOS / Android /
/// desktop this is always false.
abstract class PwaUpdateController {
  /// True only on web builds where a service worker is reachable.
  bool get isSupported;

  /// Emits `true` once the SW reports an updated version is waiting to
  /// activate. Replays the latest value to new listeners (broadcast stream).
  Stream<bool> get updateAvailable;

  /// Synchronous snapshot — useful for `initialData` on a StreamProvider.
  bool get isUpdateAvailableNow;

  /// Tell the waiting service worker to take over. The page reloads as soon
  /// as the new SW claims control (handled in `index.html`).
  void applyUpdate();

  void dispose();
}

/// Singleton controller. The web impl wires JS callbacks in its constructor;
/// keep it Provider-scoped (not per-widget) so we register listeners once.
final pwaUpdateControllerProvider = Provider<PwaUpdateController>((ref) {
  final controller = createPwaUpdateController();
  ref.onDispose(controller.dispose);
  return controller;
});

/// Convenience: streams `true` when an update is available.
final pwaUpdateAvailableProvider = StreamProvider<bool>((ref) {
  final controller = ref.watch(pwaUpdateControllerProvider);
  return controller.updateAvailable;
});
