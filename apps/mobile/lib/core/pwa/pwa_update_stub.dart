import 'pwa_update.dart';

PwaUpdateController createPwaUpdateController() =>
    const _NoopPwaUpdateController();

class _NoopPwaUpdateController implements PwaUpdateController {
  const _NoopPwaUpdateController();

  @override
  bool get isSupported => false;

  @override
  bool get isUpdateAvailableNow => false;

  @override
  Stream<bool> get updateAvailable => const Stream<bool>.empty();

  @override
  void applyUpdate() {}

  @override
  void dispose() {}
}
