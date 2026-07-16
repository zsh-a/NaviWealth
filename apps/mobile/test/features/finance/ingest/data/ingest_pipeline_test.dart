import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/ai_tools/local_skills/local_skills.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_pipeline.dart';
import 'package:naviwealth/features/finance/ingest/domain/ingest_models.dart';

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

  test('Alipay category wins over merchant fallback and still dedups', () {
    final result = build().plan(
      source: const IngestSource(
        kind: IngestSourceKind.csv,
        payload:
            '支付宝支付科技有限公司 电子客户回单\n'
            '交易时间,交易分类,交易对方,对方账号,商品说明,收/支,金额,'
            '收/付款方式,交易状态,交易订单号,商家订单号,备注,\n'
            '2026-07-10 12:30:01,日用百货,麦当劳,merchant@example.com,'
            '家庭装纸巾,支出,31.50,余额,交易成功,trade-1,order-1,,\n'
            '2026-07-09 18:00:00,餐饮美食,示例餐厅,food@example.com,'
            '晚餐,支出,28.00,余额,交易成功,trade-2,order-2,,\n'
            '2026-07-08 09:00:00,投资理财,示例基金,finance@example.com,'
            '基金申购,不计收支,1000.00,余额宝,交易成功,trade-3,order-3,,\n',
        originLabel: '支付宝交易明细.csv',
      ),
      existingLedger: [
        TransactionInput(
          id: 'existing-paper',
          description: '麦当劳 · 家庭装纸巾 · 日用百货 · 余额',
          amountMinor: '-3150',
          currency: 'CNY',
          occurredAt: DateTime.utc(2026, 7, 10),
        ),
      ],
      ownerUserId: 'u1',
    );

    expect(result.total, 2);
    expect(result.drafts[0].parsed.categoryHint, 'groceries');
    expect(result.drafts[0].verdict, DedupVerdict.duplicate);
    expect(result.drafts[0].dedupTargetEntryId, 'existing-paper');
    expect(result.drafts[1].parsed.categoryHint, 'dining');
    expect(result.drafts[1].verdict, DedupVerdict.newTxn);
    expect(result.parseCandidateRowCount, 3);
    expect(result.skippedCount, 1);
    expect(result.accountsForEveryParseCandidate, isTrue);
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

  test('planning preserves one clock read and one id per accepted row', () {
    var clockReads = 0;
    var idReads = 0;
    final pipeline = IngestPipeline(
      clock: () {
        clockReads++;
        return DateTime.utc(2026, 5, 15, 12);
      },
      idGen: () => 'counted-${idReads++}',
    );

    final rejected = pipeline.plan(
      source: const IngestSource(
        kind: IngestSourceKind.receiptImage,
        payload: '<bytes>',
      ),
      existingLedger: const [],
      ownerUserId: 'u1',
    );
    expect(rejected.isRejected, isTrue);
    expect((clockReads, idReads), (0, 0));

    final empty = pipeline.plan(
      source: const IngestSource(kind: IngestSourceKind.csv, payload: ''),
      existingLedger: const [],
      ownerUserId: 'u1',
    );
    expect(empty.drafts, isEmpty);
    expect((clockReads, idReads), (1, 0));

    final rows = pipeline.planFromParsed(
      parsed: [
        ParsedTransaction(
          description: 'A',
          amountMinor: -100,
          currency: 'CNY',
          occurredAt: DateTime.utc(2026, 5, 10),
        ),
        ParsedTransaction(
          description: 'B',
          amountMinor: -200,
          currency: 'CNY',
          occurredAt: DateTime.utc(2026, 5, 11),
        ),
      ],
      source: const IngestSource(
        kind: IngestSourceKind.csv,
        payload: '',
        originLabel: 'counted.csv',
      ),
      existingLedger: const [],
      ownerUserId: 'u1',
      traceId: 'trace-counted',
    );
    expect((clockReads, idReads), (2, 2));
    expect(rows.drafts.map((draft) => draft.draftId), [
      'counted-0',
      'counted-1',
    ]);
    expect(rows.drafts.map((draft) => draft.createdAt).toSet(), {
      DateTime.utc(2026, 5, 15, 12),
    });
    expect(
      rows.drafts.every((draft) => draft.traceId == 'trace-counted'),
      isTrue,
    );
    expect(
      rows.drafts.every((draft) => draft.originLabel == 'counted.csv'),
      isTrue,
    );
  });

  test('pure analysis plus materialization matches the synchronous API', () {
    const source = IngestSource(
      kind: IngestSourceKind.csv,
      payload:
          'date,description,amount,currency\n'
          '2026-05-10,STARBUCKS 04291,-38.00,CNY\n'
          '2026-05-10,STARBUCKS 04291,-38.00,CNY\n',
      originLabel: 'parity.csv',
    );
    final ledger = [
      TransactionInput(
        id: 'existing-coffee',
        description: 'STARBUCKS 04291',
        amountMinor: '-3800',
        currency: 'CNY',
        occurredAt: DateTime.utc(2026, 5, 10),
      ),
    ];
    var syncId = 0;
    final synchronous =
        IngestPipeline(
          clock: () => DateTime.utc(2026, 5, 15, 12),
          idGen: () => 'draft-${syncId++}',
        ).plan(
          source: source,
          existingLedger: ledger,
          ownerUserId: 'u1',
          traceId: 'trace-parity',
        );

    final analysis = analyzeIngestPlanning(
      IngestPlanningRequest(
        payload: DeviceIngestPlanningPayload(
          kind: IngestSourceKind.csv,
          raw: source.payload,
          defaultCurrency: 'CNY',
        ),
        existingLedger: ledger,
      ),
    );
    var materializedId = 0;
    final materialized =
        IngestPipeline(
          clock: () => DateTime.utc(2026, 5, 15, 12),
          idGen: () => 'draft-${materializedId++}',
        ).materialize(
          analysis: analysis,
          source: source,
          ownerUserId: 'u1',
          traceId: 'trace-parity',
        );

    expect(materialized.rejectedReason, synchronous.rejectedReason);
    expect(materialized.drafts, hasLength(synchronous.drafts.length));
    for (var index = 0; index < synchronous.drafts.length; index++) {
      final expected = synchronous.drafts[index];
      final actual = materialized.drafts[index];
      expect(actual.parsed.toJson(), expected.parsed.toJson());
      expect(
        (
          actual.draftId,
          actual.ownerUserId,
          actual.createdAt,
          actual.sourceKind,
          actual.verdict,
          actual.status,
          actual.originLabel,
          actual.dedupTargetEntryId,
          actual.traceId,
          actual.expiresAt,
        ),
        (
          expected.draftId,
          expected.ownerUserId,
          expected.createdAt,
          expected.sourceKind,
          expected.verdict,
          expected.status,
          expected.originLabel,
          expected.dedupTargetEntryId,
          expected.traceId,
          expected.expiresAt,
        ),
      );
    }
  });

  test('materialization rejects forward batch targets', () {
    final pipeline = build();
    final analysis = IngestPlanningAnalysis(
      rows: [
        AnalyzedIngestRow(
          parsed: ParsedTransaction(
            description: 'bad target',
            amountMinor: -100,
            currency: 'CNY',
            occurredAt: DateTime.utc(2026, 5, 10),
          ),
          verdict: DedupVerdict.duplicate,
          target: const BatchRowTarget(0),
        ),
      ],
    );

    expect(
      () => pipeline.materialize(
        analysis: analysis,
        source: const IngestSource(kind: IngestSourceKind.csv, payload: ''),
        ownerUserId: 'u1',
      ),
      throwsStateError,
    );
  });
}
