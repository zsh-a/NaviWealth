/// Web / desktop fallback for [HealthPlatformAdapter]. HealthOS isn't
/// shipped to those targets (northstar §1.1) so every call reports
/// "not supported" and the orchestrator short-circuits.
library;

import 'health_platform_adapter.dart';

HealthPlatformAdapter createHealthPlatformAdapter() =>
    const _UnsupportedHealthPlatformAdapter();

class _UnsupportedHealthPlatformAdapter implements HealthPlatformAdapter {
  const _UnsupportedHealthPlatformAdapter();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<bool> hasPermissions() async => false;

  @override
  Future<bool> requestPermissions() async => false;

  @override
  Future<HealthPlatformSnapshot> fetchRange({
    required DateTime from,
    required DateTime to,
  }) async => const HealthPlatformSnapshot.empty();
}
