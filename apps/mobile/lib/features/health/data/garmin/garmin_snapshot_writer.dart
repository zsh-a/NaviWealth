/// Writes normalized Garmin `HealthSnapshot` JSON into HealthOS.
library;

import 'dart:convert';

import 'package:naviwealth/core/logging/app_logger.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';

import '../../domain/health_metric_kind.dart';
import '../health_metric_ingestor.dart';
import '../health_metric_repository.dart';
import 'garmin_snapshot_normalizer.dart';

/// Outcome of writing one Garmin snapshot to Drift.
class GarminWriteResult {
  const GarminWriteResult({
    required this.upserted,
    required this.unchanged,
    this.errors = const [],
  });

  final int upserted;
  final int unchanged;
  final List<String> errors;

  int get total => upserted + unchanged;
  bool get ok => errors.isEmpty;
}

class GarminSnapshotWriter {
  GarminSnapshotWriter({
    required HealthMetricRepository repository,
    required MutationStamper stamper,
    AppLogger? logger,
    GarminSnapshotNormalizer normalizer = const GarminSnapshotNormalizer(),
  }) : _ingestor = HealthMetricIngestor(
         repository: repository,
         stamper: stamper,
       ),
       _logger = logger ?? AppLogger.instance,
       _normalizer = normalizer;

  final HealthMetricIngestor _ingestor;
  final AppLogger _logger;
  final GarminSnapshotNormalizer _normalizer;

  Future<GarminWriteResult> writeSnapshotJson(String snapshotJson) async {
    _logger.i('HealthOS Garmin snapshot decode: bytes=${snapshotJson.length}');
    final json = jsonDecode(snapshotJson) as Map<String, dynamic>;
    return writeSnapshotMap(json);
  }

  Future<GarminWriteResult> writeSnapshotMap(
    Map<String, dynamic> snapshot,
  ) async {
    _logger.i(
      'HealthOS Garmin snapshot normalize: keys=${snapshot.keys.toList()}',
    );
    final batch = _normalizer.normalize(snapshot);
    _logger.i(
      'HealthOS Garmin snapshot normalized: rows=${batch.rows.length} '
      'counts=${_formatCounts(batch.countsByKind)} errors=${batch.errors}',
    );
    final result = await _ingestor.ingestRaw(batch.rows);
    _logger.i(
      'HealthOS Garmin snapshot persisted: total=${result.total} '
      'upserted=${result.upserted} unchanged=${result.unchanged}',
    );
    return GarminWriteResult(
      upserted: result.upserted,
      unchanged: result.unchanged,
      errors: batch.errors,
    );
  }

  String _formatCounts(Map<HealthMetricKind, int> counts) {
    final entries = counts.entries.toList()
      ..sort((a, b) => a.key.wire.compareTo(b.key.wire));
    return {
      for (final entry in entries) entry.key.wire: entry.value,
    }.toString();
  }
}
