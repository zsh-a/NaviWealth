import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

enum BiometricAvailability { available, notEnrolled, unsupported }

abstract interface class BiometricAuthService {
  Future<BiometricAvailability> availability();

  Future<bool> authenticate({required String reason});
}

final biometricAuthServiceProvider = Provider<BiometricAuthService>((ref) {
  return LocalAuthBiometricAuthService();
});

final biometricAvailabilityProvider = FutureProvider<BiometricAvailability>((
  ref,
) {
  return ref.watch(biometricAuthServiceProvider).availability();
});

class LocalAuthBiometricAuthService implements BiometricAuthService {
  LocalAuthBiometricAuthService({LocalAuthentication? auth})
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<BiometricAvailability> availability() async {
    if (kIsWeb) return BiometricAvailability.unsupported;
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return BiometricAvailability.unsupported;
      final canCheck = await _auth.canCheckBiometrics;
      final enrolled = await _auth.getAvailableBiometrics();
      if (canCheck && enrolled.isNotEmpty) {
        return BiometricAvailability.available;
      }
      return BiometricAvailability.notEnrolled;
    } catch (_) {
      return BiometricAvailability.unsupported;
    }
  }

  @override
  Future<bool> authenticate({required String reason}) async {
    if (await availability() != BiometricAvailability.available) return false;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}
