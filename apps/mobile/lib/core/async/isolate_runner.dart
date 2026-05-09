import 'dart:async';

import 'isolate_runner_stub.dart'
    if (dart.library.io) 'isolate_runner_io.dart'
    if (dart.library.html) 'isolate_runner_web.dart'
    if (dart.library.js_interop) 'isolate_runner_web.dart'
    as impl;

/// Run [computation] in a background isolate and return the result.
///
/// [computation] must be a top-level or static function. Its argument and
/// return value must be sendable across isolate boundaries (plain Dart
/// objects — no Flutter widgets, no Drift database handles, no closures
/// that capture non-sendable state).
///
/// On web, isolates are unavailable; the computation runs on the main
/// thread inside a microtask.
Future<T> runInIsolate<T>(T Function() computation) =>
    impl.runInIsolate(computation);
