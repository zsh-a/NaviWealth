/// Privacy-safe aggregate quality report for scheduled LifeOS agents.
///
/// The report reads only lifecycle state and evidence-link structure. It never
/// exports summaries, titles, evidence ids, payloads, or user-authored text.
library;

import 'package:drift/drift.dart';

import '../../persistence/app_database.dart';
import 'agent_artifact.dart';

class AgentQualityReport {
  const AgentQualityReport({
    required this.windowStart,
    required this.generatedAt,
    required this.readyRuns,
    required this.noFindingRuns,
    required this.failedRuns,
    required this.artifactCount,
    required this.dismissedOrSnoozedArtifacts,
    required this.evidenceBearingArtifacts,
    required this.fullyAnchoredEvidenceArtifacts,
  });

  final DateTime windowStart;
  final DateTime generatedAt;
  final int readyRuns;
  final int noFindingRuns;
  final int failedRuns;
  final int artifactCount;
  final int dismissedOrSnoozedArtifacts;
  final int evidenceBearingArtifacts;
  final int fullyAnchoredEvidenceArtifacts;

  int get completedRuns => readyRuns + noFindingRuns + failedRuns;

  double get highSignalRate => _rate(readyRuns, completedRuns);
  double get noFindingRate => _rate(noFindingRuns, completedRuns);
  double get failureRate => _rate(failedRuns, completedRuns);
  double get dismissedOrSnoozedRate =>
      _rate(dismissedOrSnoozedArtifacts, artifactCount);
  double get evidenceAnchorCoverageRate =>
      _rate(fullyAnchoredEvidenceArtifacts, evidenceBearingArtifacts);

  Map<String, Object> toJson() => <String, Object>{
    'window_start': windowStart.toUtc().toIso8601String(),
    'generated_at': generatedAt.toUtc().toIso8601String(),
    'completed_runs': completedRuns,
    'ready_runs': readyRuns,
    'no_finding_runs': noFindingRuns,
    'failed_runs': failedRuns,
    'artifact_count': artifactCount,
    'dismissed_or_snoozed_artifacts': dismissedOrSnoozedArtifacts,
    'evidence_bearing_artifacts': evidenceBearingArtifacts,
    'fully_anchored_evidence_artifacts': fullyAnchoredEvidenceArtifacts,
    'high_signal_rate': highSignalRate,
    'no_finding_rate': noFindingRate,
    'failure_rate': failureRate,
    'dismissed_or_snoozed_rate': dismissedOrSnoozedRate,
    'evidence_anchor_coverage_rate': evidenceAnchorCoverageRate,
  };
}

class SqliteAgentQualityReportReader {
  const SqliteAgentQualityReportReader(this._db);

  final AppDatabase _db;

  Future<AgentQualityReport> read({
    required String ownerUserId,
    required DateTime since,
    required DateTime now,
  }) async {
    final sinceMillis = since.toUtc().millisecondsSinceEpoch;
    final runRows = await _db
        .customSelect(
          '''
      SELECT status, COUNT(*) AS count
      FROM agent_runs
      WHERE owner_user_id = ?
        AND started_at >= ?
        AND status IN ('ready', 'no_finding', 'failed')
      GROUP BY status
      ''',
          variables: <Variable<Object>>[
            Variable<String>(ownerUserId),
            Variable<int>(sinceMillis),
          ],
        )
        .get();
    final runCounts = <String, int>{
      for (final row in runRows)
        row.read<String>('status'): row.read<int>('count'),
    };

    final artifactRows = await _db
        .customSelect(
          '''
      SELECT evidence_json, dismissed_at, snoozed_until
      FROM agent_artifacts
      WHERE owner_user_id = ? AND created_at >= ?
      ''',
          variables: <Variable<Object>>[
            Variable<String>(ownerUserId),
            Variable<int>(sinceMillis),
          ],
        )
        .get();
    var suppressed = 0;
    var evidenceBearing = 0;
    var fullyAnchored = 0;
    for (final row in artifactRows) {
      if (row.read<int?>('dismissed_at') != null ||
          row.read<int?>('snoozed_until') != null) {
        suppressed++;
      }
      final evidence = decodeAgentEvidenceRefs(
        row.read<String>('evidence_json'),
      );
      if (evidence.isEmpty) continue;
      evidenceBearing++;
      if (evidence.every(
        (item) => item.route != null && item.route!.trim().isNotEmpty,
      )) {
        fullyAnchored++;
      }
    }

    return AgentQualityReport(
      windowStart: since.toUtc(),
      generatedAt: now.toUtc(),
      readyRuns: runCounts['ready'] ?? 0,
      noFindingRuns: runCounts['no_finding'] ?? 0,
      failedRuns: runCounts['failed'] ?? 0,
      artifactCount: artifactRows.length,
      dismissedOrSnoozedArtifacts: suppressed,
      evidenceBearingArtifacts: evidenceBearing,
      fullyAnchoredEvidenceArtifacts: fullyAnchored,
    );
  }
}

double _rate(int numerator, int denominator) =>
    denominator == 0 ? 0 : numerator / denominator;
