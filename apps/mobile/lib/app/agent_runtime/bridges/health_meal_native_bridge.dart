/// Host adapter for the shared meal-recognition core. No domain prompt or
/// provider response parsing belongs on this side of the native boundary.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_json.dart';
import 'package:naviwealth/core/config/providers.dart';
import 'package:naviwealth/core/native/lifeos_native_runtime.dart';
import 'package:naviwealth/src/rust/api/health_meal.dart' as rust;

abstract interface class HealthMealNativeApi {
  Future<String> recognize({required String requestJson});
  Future<Uint8List> normalizePhoto({required Uint8List bytes});
}

class FrbHealthMealNativeApi implements HealthMealNativeApi {
  const FrbHealthMealNativeApi();

  @override
  Future<String> recognize({required String requestJson}) =>
      rust.healthMealRecognizeJson(requestJson: requestJson);

  @override
  Future<Uint8List> normalizePhoto({required Uint8List bytes}) =>
      rust.healthMealNormalizePhoto(bytes: bytes);
}

abstract interface class HealthMealNativeBridge {
  Future<Map<String, Object?>> recognize({
    required Map<String, Object?> request,
  });
  Future<Uint8List> normalizePhoto(Uint8List bytes);
}

final healthMealNativeBridgeProvider = Provider<HealthMealNativeBridge>((ref) {
  final config = ref.watch(appConfigProvider);
  return FfiHealthMealNativeBridge(
    api: const FrbHealthMealNativeApi(),
    initialize: initLifeosNativeRuntime,
    libraryPath: config.rustEmbedderLibraryPath.isEmpty
        ? null
        : config.rustEmbedderLibraryPath,
  );
});

class FfiHealthMealNativeBridge implements HealthMealNativeBridge {
  const FfiHealthMealNativeBridge({
    required HealthMealNativeApi api,
    required LifeosNativeRuntimeInitializer initialize,
    String? libraryPath,
  }) : _api = api,
       _initialize = initialize,
       _libraryPath = libraryPath;

  final HealthMealNativeApi _api;
  final LifeosNativeRuntimeInitializer _initialize;
  final String? _libraryPath;

  @override
  Future<Map<String, Object?>> recognize({
    required Map<String, Object?> request,
  }) async {
    await _initialize(libraryPath: _libraryPath);
    final response = await _api.recognize(requestJson: jsonEncode(request));
    return agentRuntimeDecodeObject(response, label: 'shared meal recognition');
  }

  @override
  Future<Uint8List> normalizePhoto(Uint8List bytes) async {
    await _initialize(libraryPath: _libraryPath);
    return _api.normalizePhoto(bytes: bytes);
  }
}
