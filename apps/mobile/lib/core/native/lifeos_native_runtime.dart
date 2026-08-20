/// Shared, domain-neutral initialization for the app's `lifeos_native`
/// flutter_rust_bridge runtime.
library;

import 'lifeos_native_runtime_io.dart'
    if (dart.library.js_interop) 'lifeos_native_runtime_web.dart';

typedef LifeosNativeRuntimeInitializer =
    Future<void> Function({String? libraryPath});

/// Owns one idempotent native-runtime initialization attempt.
///
/// Concurrent callers share the same future. A failed attempt is evicted so a
/// later foreground retry can recover after the native library becomes
/// available.
final class LifeosNativeRuntime {
  LifeosNativeRuntime({LifeosNativeRuntimeInitializer? loader})
    : _loader = loader ?? loadLifeosNativeRuntime;

  final LifeosNativeRuntimeInitializer _loader;
  Future<void>? _initFuture;

  Future<void> initialize({String? libraryPath}) {
    return _initFuture ??= _initialize(libraryPath: libraryPath);
  }

  Future<void> _initialize({String? libraryPath}) async {
    try {
      await _loader(libraryPath: libraryPath);
    } on Object {
      _initFuture = null;
      rethrow;
    }
  }
}

final LifeosNativeRuntime _sharedLifeosNativeRuntime = LifeosNativeRuntime();

/// Initializes the process-wide `lifeos_native` runtime exactly once.
Future<void> initLifeosNativeRuntime({String? libraryPath}) {
  return _sharedLifeosNativeRuntime.initialize(libraryPath: libraryPath);
}
