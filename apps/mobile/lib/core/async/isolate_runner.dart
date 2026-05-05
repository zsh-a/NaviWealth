import 'dart:async';
import 'dart:isolate';

/// Run [computation] in a background isolate and return the result.
///
/// [computation] must be a top-level or static function. Its argument and
/// return value must be sendable across isolate boundaries (plain Dart
/// objects — no Flutter widgets, no Drift database handles, no closures
/// that capture non-sendable state).
Future<T> runInIsolate<T>(T Function() computation) =>
    Isolate.run(computation);
