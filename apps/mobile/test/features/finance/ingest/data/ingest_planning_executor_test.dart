import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/ai_tools/local_skills/local_skills.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_pipeline.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_planning_executor.dart';
import 'package:naviwealth/features/finance/ingest/domain/ingest_models.dart';

void main() {
  test('executor round-trips device payload and existing target', () async {
    final analysis = await runIngestPlanning(
      IngestPlanningRequest(
        payload: const DeviceIngestPlanningPayload(
          kind: IngestSourceKind.csv,
          raw:
              'date,description,amount,currency\n'
              '2026-05-10,Netflix,-68.00,CNY\n',
          defaultCurrency: 'CNY',
        ),
        existingLedger: [
          TransactionInput(
            id: 'existing-netflix',
            description: 'Netflix',
            amountMinor: '-6800',
            currency: 'cny',
            occurredAt: DateTime.utc(2026, 5, 10),
          ),
        ],
      ),
    );

    expect(analysis.isRejected, isFalse);
    expect(analysis.rows, hasLength(1));
    expect(analysis.rows.single.verdict, DedupVerdict.duplicate);
    expect(
      (analysis.rows.single.target as ExistingEntryTarget).id,
      'existing-netflix',
    );
    expect(analysis.rows.single.parsed.occurredAt, DateTime.utc(2026, 5, 10));
  });

  test('executor round-trips pre-parsed rows and batch target', () async {
    final at = DateTime.utc(2026, 5, 10, 12, 30, 1);
    final rows = [
      ParsedTransaction(
        description: '瑞幸咖啡 拿铁',
        amountMinor: -1800,
        currency: 'CNY',
        occurredAt: at,
        confidence: 0.82,
      ),
      ParsedTransaction(
        description: '瑞幸咖啡 拿铁',
        amountMinor: -1800,
        currency: 'CNY',
        occurredAt: at,
        confidence: 0.82,
      ),
    ];

    final analysis = await runIngestPlanning(
      IngestPlanningRequest(
        payload: PreParsedIngestPlanningPayload(rows),
        existingLedger: const <TransactionInput>[],
      ),
    );

    expect(analysis.rows, hasLength(2));
    expect(analysis.rows.first.verdict, DedupVerdict.newTxn);
    expect(analysis.rows.last.verdict, DedupVerdict.duplicate);
    expect((analysis.rows.last.target as BatchRowTarget).index, 0);
    expect(analysis.rows.last.parsed.occurredAt, at);
    expect(analysis.rows.last.parsed.confidence, 0.82);
  });
}
