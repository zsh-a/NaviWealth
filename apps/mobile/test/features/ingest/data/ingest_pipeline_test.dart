import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/local/skills/skills.dart';
import 'package:naviwealth/features/ingest/data/ingest_pipeline.dart';
import 'package:naviwealth/features/ingest/domain/ingest_models.dart';

void main() {
  var counter = 0;
  IngestPipeline build() => IngestPipeline(
    clock: () => DateTime.utc(2026, 5, 15, 12),
    idGen: () => 'draft-${counter++}',
  );

  setUp(() => counter = 0);

  test('plan parses, normalizes category, and dedups against ledger', () {
    final pipeline = build();
    final result = pipeline.plan(
      source: const IngestSource(
        kind: IngestSourceKind.pasteText,
        payload:
            'date,description,amount,currency\n'
            '2026-05-10,STARBUCKS 04291,-38.00,CNY\n'
            '2026-05-12,Unknown Vendor,-12.00,CNY\n',
        originLabel: '粘贴文本',
      ),
      existingLedger: [
        TransactionInput(
          id: 'je-1',
          description: 'STARBUCKS 04291',
          amountMinor: '-3800',
          currency: 'CNY',
          occurredAt: DateTime.utc(2026, 5, 10),
        ),
      ],
      ownerUserId: 'u1',
      traceId: 'trace-1',
    );

    expect(result.isRejected, isFalse);
    expect(result.total, 2);

    final coffee = result.drafts.firstWhere(
      (d) => d.parsed.description.contains('STARBUCKS'),
    );
    // Reused on-device classifier filled the category hint.
    expect(coffee.parsed.categoryHint, 'coffee');
    // Already in the ledger → flagged, not silently added.
    expect(coffee.verdict, DedupVerdict.duplicate);
    expect(coffee.dedupTargetEntryId, 'je-1');
    expect(coffee.status, DraftStatus.pending);
    expect(coffee.ownerUserId, 'u1');
    expect(coffee.traceId, 'trace-1');
    expect(coffee.createdAt, DateTime.utc(2026, 5, 15, 12));

    final fresh = result.drafts.firstWhere(
      (d) => d.parsed.description.contains('Unknown'),
    );
    expect(fresh.verdict, DedupVerdict.newTxn);
    expect(result.newCount, 1);
    expect(result.duplicateCount, 1);
  });

  test('non-device-parsable sources are rejected, never silently dropped', () {
    final result = build().plan(
      source: const IngestSource(
        kind: IngestSourceKind.receiptImage,
        payload: '<bytes>',
      ),
      existingLedger: const [],
      ownerUserId: 'u1',
    );
    expect(result.isRejected, isTrue);
    expect(result.drafts, isEmpty);
    expect(result.rejectedReason, contains('Vision'));
  });

  test('empty payload yields zero drafts without rejection', () {
    final result = build().plan(
      source: const IngestSource(kind: IngestSourceKind.csv, payload: ''),
      existingLedger: const [],
      ownerUserId: 'u1',
    );
    expect(result.isRejected, isFalse);
    expect(result.total, 0);
  });

  test('dedups repeated rows inside the imported batch', () {
    final result = build().plan(
      source: const IngestSource(
        kind: IngestSourceKind.csv,
        payload:
            '交易时间,交易对方,商品,收/支,金额(元),当前状态\n'
            '2026-05-10 12:30:01,瑞幸咖啡,拿铁,支出,18.00,支付成功\n'
            '2026-05-10 12:30:01,瑞幸咖啡,拿铁,支出,18.00,支付成功\n',
      ),
      existingLedger: const [],
      ownerUserId: 'u1',
    );

    expect(result.total, 2);
    expect(result.drafts[0].verdict, DedupVerdict.newTxn);
    expect(result.drafts[1].verdict, DedupVerdict.duplicate);
    expect(result.drafts[1].dedupTargetEntryId, result.drafts[0].draftId);
  });

  test('dedups periodic re-imports against pending drafts', () {
    final pipeline = build();
    final first = pipeline.plan(
      source: const IngestSource(
        kind: IngestSourceKind.csv,
        payload:
            'date,description,amount,currency\n'
            '2026-05-10,Netflix,-68.00,CNY\n',
      ),
      existingLedger: const [],
      ownerUserId: 'u1',
    );
    final pendingAsLedger = [
      TransactionInput(
        id: first.drafts.single.draftId,
        description: first.drafts.single.parsed.description,
        amountMinor: first.drafts.single.parsed.amountMinor.toString(),
        currency: first.drafts.single.parsed.currency,
        occurredAt: first.drafts.single.parsed.occurredAt,
      ),
    ];

    final second = pipeline.plan(
      source: const IngestSource(
        kind: IngestSourceKind.csv,
        payload:
            'date,description,amount,currency\n'
            '2026-05-10,Netflix,-68.00,CNY\n',
      ),
      existingLedger: pendingAsLedger,
      ownerUserId: 'u1',
    );

    expect(second.drafts.single.verdict, DedupVerdict.duplicate);
    expect(
      second.drafts.single.dedupTargetEntryId,
      first.drafts.single.draftId,
    );
  });
}
