import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/share_intents/share_intent_service.dart';

void main() {
  test('share intent capability is limited to native mobile platforms', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final desktop = ProviderContainer();
    addTearDown(desktop.dispose);
    expect(desktop.read(shareIntentPlatformAvailableProvider), isFalse);

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final mobile = ProviderContainer();
    addTearDown(mobile.dispose);
    expect(mobile.read(shareIntentPlatformAvailableProvider), isTrue);
  });

  testWidgets('disabled share intents never open plugin channels', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        shareIntentPlatformAvailableProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);

    final service = container.read(shareIntentServiceProvider);
    service.start();
    service.start();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
