import 'dart:convert';

import 'ingest_models.dart';

/// Privacy-safe parser diagnostics for explicit copy/export. This contains
/// stable enums and counts only—never source rows, labels, amounts, currencies,
/// descriptions, or account identifiers.
final class IngestQualityReport {
  const IngestQualityReport({
    required this.sourceKind,
    required this.outcome,
    required this.candidateRowCount,
    required this.draftCount,
    required this.newCount,
    required this.duplicateCount,
    required this.skippedCount,
    required this.diagnosticsComplete,
    required this.issueCounts,
  });

  factory IngestQualityReport.fromResult(
    IngestSourceKind sourceKind,
    IngestResult result,
  ) {
    final issues = <String, int>{};
    for (final issue in result.parseIssues) {
      issues.update(issue.code.name, (count) => count + 1, ifAbsent: () => 1);
    }
    return IngestQualityReport(
      sourceKind: sourceKind,
      outcome: result.isRejected
          ? 'rejected'
          : result.total == 0
          ? 'empty'
          : 'reviewReady',
      candidateRowCount: result.parseCandidateRowCount,
      draftCount: result.total,
      newCount: result.newCount,
      duplicateCount: result.duplicateCount,
      skippedCount: result.skippedCount,
      diagnosticsComplete: result.parseDiagnosticsComplete,
      issueCounts: Map.unmodifiable(issues),
    );
  }

  factory IngestQualityReport.failed(IngestSourceKind sourceKind) =>
      IngestQualityReport(
        sourceKind: sourceKind,
        outcome: 'failed',
        candidateRowCount: 0,
        draftCount: 0,
        newCount: 0,
        duplicateCount: 0,
        skippedCount: 0,
        diagnosticsComplete: false,
        issueCounts: const <String, int>{},
      );

  final IngestSourceKind sourceKind;
  final String outcome;
  final int candidateRowCount;
  final int draftCount;
  final int newCount;
  final int duplicateCount;
  final int skippedCount;
  final bool diagnosticsComplete;
  final Map<String, int> issueCounts;

  Map<String, Object?> toJson() => <String, Object?>{
    'schema_version': 1,
    'source_kind': sourceKind.wire,
    'outcome': outcome,
    'candidate_row_count': candidateRowCount,
    'draft_count': draftCount,
    'new_count': newCount,
    'duplicate_count': duplicateCount,
    'skipped_count': skippedCount,
    'diagnostics_complete': diagnosticsComplete,
    'issue_counts': <String, int>{
      for (final key in issueCounts.keys.toList()..sort())
        key: issueCounts[key]!,
    },
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());
}
