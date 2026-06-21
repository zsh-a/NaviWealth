import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/security/biometric_auth_service.dart';
import 'package:naviwealth/core/security/biometric_lock_gate.dart';
import 'package:naviwealth/core/security/biometric_lock_preferences.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProviderContainer _container(SharedPreferences prefs) {
  return ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
}

Widget _wrap({
  required SharedPreferences prefs,
  required BiometricAuthService service,
}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      biometricAuthServiceProvider.overrideWithValue(service),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => FTheme(
        data: FThemes.slate.light.desktop,
        child: AppMessenger.init(child: child ?? const SizedBox.shrink()),
      ),
      home: const BiometricLockGate(child: Text('Private dashboard')),
    ),
  );
}

void main() {
  group('biometric unlock', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('defaults to off and persists preference changes', () async {
      var prefs = await SharedPreferences.getInstance();
      final c = _container(prefs);

      expect(c.read(biometricUnlockEnabledProvider), isFalse);
      await c.read(biometricUnlockEnabledProvider.notifier).setEnabled(true);
      c.dispose();

      prefs = await SharedPreferences.getInstance();
      final c2 = _container(prefs);
      addTearDown(c2.dispose);

      expect(c2.read(biometricUnlockEnabledProvider), isTrue);
    });

    testWidgets('allows app content when disabled', (tester) async {
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        _wrap(
          prefs: prefs,
          service: _FakeBiometricAuthService(
            availability: BiometricAvailability.available,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Private dashboard'), findsOneWidget);
      expect(find.text('NaviWealth is locked'), findsNothing);
    });

    testWidgets('locks enabled sessions until biometric succeeds', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      final seed = _container(prefs);
      await seed.read(biometricUnlockEnabledProvider.notifier).setEnabled(true);
      seed.dispose();
      final service = _FakeBiometricAuthService(
        availability: BiometricAvailability.available,
      );

      await tester.pumpWidget(_wrap(prefs: prefs, service: service));
      await tester.pumpAndSettle();

      expect(find.text('Private dashboard'), findsNothing);
      expect(find.text('NaviWealth is locked'), findsOneWidget);

      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      expect(service.authenticateCalls, 1);
      expect(find.text('Private dashboard'), findsOneWidget);
    });

    testWidgets('fails open when enabled on unsupported devices', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      final seed = _container(prefs);
      await seed.read(biometricUnlockEnabledProvider.notifier).setEnabled(true);
      seed.dispose();

      await tester.pumpWidget(
        _wrap(
          prefs: prefs,
          service: _FakeBiometricAuthService(
            availability: BiometricAvailability.unsupported,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Private dashboard'), findsOneWidget);
      expect(find.text('NaviWealth is locked'), findsNothing);
    });
  });
}

class _FakeBiometricAuthService implements BiometricAuthService {
  _FakeBiometricAuthService({required BiometricAvailability availability})
    : _availability = availability;

  final BiometricAvailability _availability;

  int _authenticateCalls = 0;

  int get authenticateCalls => _authenticateCalls;

  @override
  Future<BiometricAvailability> availability() async => _availability;

  @override
  Future<bool> authenticate({required String reason}) async {
    _authenticateCalls += 1;
    return true;
  }
}
