import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/ingest/domain/ingest_models.dart';
import 'package:naviwealth/features/finance/ingest/domain/ingest_parse_diagnostics.dart';
import 'package:naviwealth/features/finance/ingest/domain/ingest_quality_report.dart';

void main() {
  test('exports stable counts without financial source content', () {
    final report = IngestQualityReport.fromResult(
      IngestSourceKind.csv,
      IngestResult(
        drafts: [
          _draft('new', DedupVerdict.newTxn),
          _draft('duplicate', DedupVerdict.duplicate),
        ],
        parseIssues: const [
          IngestParseIssue(
            lineNumber: 8,
            code: IngestParseIssueCode.invalidAmount,
          ),
        ],
        parseCandidateRowCount: 3,
        parseDiagnosticsComplete: true,
      ),
    );

    final encoded = report.encode();
    final json = jsonDecode(encoded) as Map<String, Object?>;
    expect(json['new_count'], 1);
    expect(json['duplicate_count'], 1);
    expect(json['skipped_count'], 1);
    expect(json['issue_counts'], {'invalidAmount': 1});
    expect(encoded, isNot(contains('merchant-secret')));
    expect(encoded, isNot(contains('12345')));
    expect(encoded, isNot(contains('CNY')));
  });
}

IngestDraft _draft(String id, DedupVerdict verdict) => IngestDraft(
  draftId: id,
  ownerUserId: 'owner',
  createdAt: DateTime.utc(2026, 7, 1),
  sourceKind: IngestSourceKind.csv,
  parsed: ParsedTransaction(
    description: 'merchant-secret',
    amountMinor: -12345,
    currency: 'CNY',
    occurredAt: DateTime.utc(2026, 7, 1),
  ),
  verdict: verdict,
  status: DraftStatus.pending,
);
