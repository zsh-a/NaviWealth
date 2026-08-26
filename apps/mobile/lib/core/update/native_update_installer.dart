import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'native_update_errors.dart';

const MethodChannel _nativeUpdateChannel = MethodChannel(
  'com.naviwealth/native_update',
);

final nativeUpdateInstallerProvider = Provider<NativeUpdateInstaller>(
  (_) => AndroidNativeUpdateInstaller(),
);

abstract interface class NativeUpdateInstaller {
  Future<bool> canInstallPackages();

  Future<void> openInstallSettings();

  Future<void> installApk(String path);
}

final class AndroidNativeUpdateInstaller implements NativeUpdateInstaller {
  @override
  Future<bool> canInstallPackages() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      return await _nativeUpdateChannel.invokeMethod<bool>(
            'can_install_packages',
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error) {
      throw NativeUpdateException(
        NativeUpdateFailure.unsupported,
        cause: error,
      );
    }
  }

  @override
  Future<void> openInstallSettings() async {
    try {
      await _nativeUpdateChannel.invokeMethod<void>('open_install_settings');
    } on MissingPluginException {
      throw const NativeUpdateException(NativeUpdateFailure.unsupported);
    } on PlatformException catch (error) {
      throw NativeUpdateException(
        NativeUpdateFailure.installPermission,
        cause: error,
      );
    }
  }

  @override
  Future<void> installApk(String path) async {
    try {
      await _nativeUpdateChannel.invokeMethod<void>(
        'install_apk',
        <String, Object>{'path': path},
      );
    } on MissingPluginException {
      throw const NativeUpdateException(NativeUpdateFailure.unsupported);
    } on PlatformException catch (error) {
      throw NativeUpdateException(
        _failureForPlatformCode(error.code),
        cause: error,
      );
    }
  }
}

NativeUpdateFailure _failureForPlatformCode(String code) => switch (code) {
  'package_mismatch' ||
  'signature_mismatch' ||
  'downgrade' => NativeUpdateFailure.packageMismatch,
  'install_permission' => NativeUpdateFailure.installPermission,
  _ => NativeUpdateFailure.install,
};
