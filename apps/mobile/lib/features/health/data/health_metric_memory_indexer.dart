/// Second production caller of the Memory Runtime
/// (`docs/architecture/lifeos-shell.md` §6.7, `docs/domains/healthos-domain.md` §7, D-2.4b).
///
/// For each `health_metrics` row this indexer emits:
///
/// 1. Always an [EventRecord] in the cross-domain event log so
///    `ContextPack.recentEvents` can surface "user slept 6.5h on
///    2026-05-26" alongside a Finance event from the same day.
/// 2. For notable sleep sessions only an episodic [MemoryRecord]:
///    - Short (< 5h) or long (> 9h): outlier nights worth recalling.
///    - With a `payloadJson` note: user manually flagged the moment.
/// 3. For metric batches with enough history, semantic trend memories
///    and, when the signal should affect planning, procedural rules.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/auth/current_user.dart';

import '../../../core/ai/contracts/context_evidence.dart';
import '../../../core/ai/contracts/event_record.dart';
import '../../../core/ai/contracts/memory_record.dart';
import '../../../core/ai/local/memory/memory_runtime.dart';
import '../../../core/ai/local/memory/providers.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/auth/providers.dart' as core_auth;
import '../domain/health_metric.dart';
import '../domain/health_metric_kind.dart';
import 'providers.dart';

part 'health_metric_memory_indexer_bootstrap.dart';
part 'health_metric_memory_indexer_events.dart';
part 'health_metric_memory_indexer_formatting.dart';
part 'health_metric_memory_indexer_trends.dart';

/// Cross-source label so [ContextPack] can filter ("only health
/// memories") without enum'ing in core.
const String kHealthSource = 'health:health_metrics';

class HealthMetricMemoryIndexer
    with
        _HealthMetricMemoryFormatting,
        _HealthMetricEventMapper,
        _HealthMetricTrendMemoryBuilder {
  HealthMetricMemoryIndexer({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  /// Re-index every supplied metric. Idempotent: repeated calls with
  /// the same input overwrite the same rows (events and memories are
  /// both upserted by stable id).
  ///
  /// Returns `(events, memories)` written. Rows whose [HealthMetric.kind]
  /// is [HealthMetricKind.unknown] are skipped.
  Future<({int events, int memories})> reindex(
    MemoryRuntime runtime,
    Iterable<HealthMetric> metrics, {
    required String ownerUserId,
  }) async {
    var events = 0;
    var memories = 0;
    final now = _clock();
    final rows = metrics
        .where((m) => m.kind != HealthMetricKind.unknown)
        .toList(growable: false);
    for (final m in rows) {
      if (m.kind == HealthMetricKind.unknown) continue;
      await runtime.recordEvent(_eventFor(m, ownerUserId));
      events++;
      final memory = _episodicMemoryFor(m, ownerUserId, now: now);
      if (memory != null) {
        await runtime.remember(memory);
        memories++;
      }
    }
    for (final memory in _trendMemoriesFor(rows, ownerUserId, now: now)) {
      await runtime.remember(memory);
      memories++;
    }
    return (events: events, memories: memories);
  }
}
