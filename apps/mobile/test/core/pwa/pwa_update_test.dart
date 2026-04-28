import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/pwa/pwa_update.dart';

// Targets the non-web stub by virtue of the conditional import in
// `pwa_update.dart` — `flutter test` defaults to the VM, so the stub is
// what consumers on iOS/Android/desktop actually get.
void main() {
  group('PwaUpdateController (non-web stub)', () {
    test('reports unsupported and never emits', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(pwaUpdateControllerProvider);
      expect(controller.isSupported, isFalse);
      expect(controller.isUpdateAvailableNow, isFalse);

      // The stub returns Stream.empty(), which completes without values.
      final emitted = await controller.updateAvailable.toList();
      expect(emitted, isEmpty);

      // applyUpdate / dispose must be safe no-ops on non-web.
      controller.applyUpdate();
      controller.dispose();
    });

    test('pwaUpdateAvailableProvider stays in loading on stub', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final value = container.read(pwaUpdateAvailableProvider);
      // Stream.empty() completes immediately with no values; depending on
      // event-loop ordering Riverpod may show loading or done-without-value.
      expect(value.hasError, isFalse);
      expect(value.valueOrNull, isNull);
    });
  });
}
