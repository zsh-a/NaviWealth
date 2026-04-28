import 'dart:async';
import 'dart:js_interop';

import 'pwa_update.dart';

PwaUpdateController createPwaUpdateController() => _WebPwaUpdateController();

@JS('naviwealthPwa')
external _NwPwaBridge? get _bridge;

extension type _NwPwaBridge._(JSObject _) implements JSObject {
  external bool get updateAvailable;
  external String? get version;
  external void onUpdateAvailable(JSFunction cb);
  external void applyUpdate();
}

class _WebPwaUpdateController implements PwaUpdateController {
  _WebPwaUpdateController() {
    final bridge = _bridge;
    if (bridge == null) return;
    if (bridge.updateAvailable) {
      _emit(true);
    }
    // Register a single listener — the JS bridge is allowed to fan out to
    // multiple callbacks but every fire reaches the same Dart sink.
    bridge.onUpdateAvailable(_handleUpdate.toJS);
  }

  final StreamController<bool> _controller = StreamController<bool>.broadcast();
  bool _latest = false;

  void _handleUpdate() {
    _emit(true);
  }

  void _emit(bool value) {
    _latest = value;
    if (!_controller.isClosed) {
      _controller.add(value);
    }
  }

  @override
  bool get isSupported => _bridge != null;

  @override
  bool get isUpdateAvailableNow {
    final bridge = _bridge;
    if (bridge == null) return false;
    return bridge.updateAvailable || _latest;
  }

  @override
  Stream<bool> get updateAvailable => _controller.stream;

  @override
  void applyUpdate() {
    _bridge?.applyUpdate();
  }

  @override
  void dispose() {
    _controller.close();
  }
}
