/// Platform-independent HealthOS adapter contract
/// (`docs/domains/healthos-domain.md` §2, D-2.2).
///
/// Wraps HealthKit (iOS) / Health Connect (Android) reads behind a
/// narrow seam so [HealthSyncService] stays platform-agnostic and
/// testable. Web returns an `unsupported` stub (HealthOS isn't shipped
/// to web — northstar §1.1).
///
/// **Read-only by design** — HealthOS never writes back to the platform
/// store (§10 反目标). The adapter only models reads + permission
/// negotiation.
library;

import 'dart:convert';

part 'health_platform_adapter_models.dart';
part 'health_platform_adapter_sleep_merge.dart';

/// Capability surface the [HealthSyncService] needs from the platform.
abstract class HealthPlatformAdapter {
  /// `true` when the OS supports HealthKit / Health Connect at all.
  /// Returns `false` on web, on Android < HC-available, or when the
  /// Health Connect app isn't installed.
  Future<bool> isAvailable();

  /// `true` when the user has already granted read permissions for the
  /// HealthOS data types. Implementations may return `null` from the
  /// underlying API; we coerce to `false` so the caller can treat
  /// "unknown" as "not yet granted".
  Future<bool> hasPermissions();

  /// Show the OS permission sheet. Returns `true` if the user granted
  /// every requested read scope, `false` if any were denied or the
  /// sheet was dismissed.
  Future<bool> requestPermissions();

  /// One-shot pull of every supported metric in `[from, to)`. The
  /// adapter aggregates platform-side as needed (e.g. summing steps
  /// across multiple sources for a single day) so the service can
  /// just upsert.
  ///
  /// `from`/`to` are interpreted in UTC. Implementations must honour
  /// the half-open interval (don't double-count `to`).
  Future<HealthPlatformSnapshot> fetchRange({
    required DateTime from,
    required DateTime to,
  });
}
