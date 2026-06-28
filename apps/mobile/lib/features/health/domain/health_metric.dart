/// HealthOS domain entity (`docs/domains/healthos-domain.md` §1, D-2.1).
///
/// One row in the `health_metrics` table: a single measurement keyed
/// by [kind] + [capturedAt]. See [HealthMetricKind] for the canonical
/// list and per-kind unit conventions.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:naviwealth/core/sync/sync_meta.dart';

import 'health_metric_kind.dart';

part 'health_metric.freezed.dart';

@freezed
abstract class HealthMetric with _$HealthMetric {
  const factory HealthMetric({
    /// String UUID. Stable across syncs; same convention as Finance.
    required String id,

    /// Wall-time the measurement is *about* (UTC). Session start for
    /// sleep, calendar-day-start for daily summaries.
    required DateTime capturedAt,

    required HealthMetricKind kind,

    /// Numeric value in [unit]. See [HealthMetricKindX.defaultUnit].
    required double value,

    /// SI-style unit string (`'s'`, `'ms'`, `'count'`, `'bpm'`,
    /// `'kcal'`, `'kg'`, `'fraction'`).
    required String unit,

    /// Kind-specific extra payload (sleep stages histogram, averaging
    /// window, …) JSON-encoded. `null` when the row has no extras.
    String? payloadJson,

    /// Best-effort device attribution (`'iPhone'`, `'Apple Watch'`,
    /// `'manual'`, …). Free text — pass through from the platform
    /// adapter.
    String? sourceDevice,

    /// Sync metadata — owner / HLC / soft-delete tombstone. Same shape
    /// as every other synced domain entity.
    required SyncMeta sync,
  }) = _HealthMetric;
}
