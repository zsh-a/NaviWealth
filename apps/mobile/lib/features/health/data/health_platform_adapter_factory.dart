/// Conditional-import factory for [HealthPlatformAdapter].
///
/// Native targets (iOS / Android) get the real `health` plugin impl;
/// web / desktop fall back to a not-supported stub. The factory
/// function name `createHealthPlatformAdapter` must match across both
/// implementations so the Riverpod wiring stays platform-blind.
library;

export 'health_platform_adapter_stub.dart'
    if (dart.library.io) 'health_platform_adapter_io.dart';
