import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/composition/proposal_applier.dart';
import 'package:naviwealth/core/ai/composition/proposal_apply_state.dart';
import 'package:naviwealth/core/ai/composition/proposal_plan.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/finance/ai_tools/local_skills/local_skills.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_builders.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/invariants.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_confirm_service.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_dedup.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_dedup_candidate.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_dedup_service.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_draft_store.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_external_confirmation_coordinator.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_pipeline.dart';
import 'package:naviwealth/features/finance/ingest/data/providers.dart';
import 'package:naviwealth/features/finance/ingest/domain/ingest_models.dart';
import 'package:naviwealth/features/finance/ingest/domain/ingest_source_reference.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/persistence/test_database.dart';
import '../../data/repositories/_stub_stamper.dart';

ParsedTransaction row({
  String description = 'Luckin Coffee',
  int amount = -1800,
  int day = 18,
}) => ParsedTransaction(
  description: description,
  amountMinor: amount,
  currency: 'CNY',
  occurredAt: DateTime.utc(2026, 6, day, 10),
);

TransactionInput ledgerRow(ParsedTransaction parsed) => TransactionInput(
  id: 'recorded',
  description: parsed.description,
  amountMinor: parsed.amountMinor.toString(),
  currency: parsed.currency,
  occurredAt: parsed.occurredAt,
);

class CountingApplier implements ProposalApplier {
  int calls = 0;
  @override
  Future<ProposalApplyState> apply(ReadyProposalPlan plan) async {
    calls++;
    return ProposalApplyState(
      status: ProposalApplyStatus.applied,
      appliedEntityId: 'recorded-$calls',
      appliedTable: 'journal_entries',
      appliedAt: DateTime.utc(2026, 6, 18),
      undoData: const <String, Object?>{},
      shortLabel: 'audit',
    );
  }

  @override
  Future<void> undo(ProposalApplyState state) async {}
}

void main() {
  test(
    'likely duplicates do not extend the matching chain across imports',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final store = IngestDraftStore(db, ownerUserId: 'u-test');
      addTearDown(store.dispose);
      final first = IngestPipeline().planFromParsed(
        parsed: [row(amount: -10000), row(amount: -10099)],
        source: const IngestSource(kind: IngestSourceKind.csv, payload: ''),
        existingLedger: const [],
        ownerUserId: 'u-test',
      );
      expect(first.drafts.last.verdict, DedupVerdict.likelyDuplicate);
      await store.putAll(first.drafts);
      final evidence = await IngestDedupService(
        store: store,
        repository: JournalEntryRepository(
          db: db,
          outbox: DriftOutboxStore(db),
          stamper: makeStubStamper(),
          fxRateSource: const IdentityFxRateSource(),
          baseCurrency: 'CNY',
        ),
      ).snapshot();
      expect(evidence, hasLength(1));
      expect(
        classifyDedup(row(amount: -10198), evidence).verdict,
        DedupVerdict.newTxn,
      );
    },
  );

  test('unscoped bank counters cannot alias unrelated transactions', () {
    const reference = IngestSourceReference(
      provider: 'bank',
      transactionId: '1',
    );
    final original = row().copyWith(sourceReference: reference);
    final other = row(day: 20).copyWith(sourceReference: reference);
    expect(reference.hasUniqueScope, isFalse);
    expect(
      classifyDedup(other, [
        IngestDedupCandidate.fromParsed(original, id: 'first'),
      ]).verdict,
      DedupVerdict.newTxn,
    );
    expect(ingestProvenanceTags(kind: 'expense', reference: reference), [
      'ingest:kind:expense',
    ]);
  });

  test('missing source id placeholders do not create shared identities', () {
    final result = IngestPipeline().plan(
      source: const IngestSource(
        kind: IngestSourceKind.csv,
        payload:
            'date,description,amount,transactionid\n'
            '2026-06-18T10:00:00Z,Coffee,-18.00,-\n'
            '2026-06-18T15:00:00Z,Coffee,-18.00,-\n',
      ),
      existingLedger: const [],
      ownerUserId: 'u-test',
    );
    expect(result.newCount, 2);
    expect(
      result.drafts.every((draft) => draft.parsed.sourceReference == null),
      isTrue,
    );
  });

  test('a ledger write after preview blocks confirmation and refreshes edited evidence', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = IngestDraftStore(db, ownerUserId: 'u-test');
    addTearDown(store.dispose);
    final repository = JournalEntryRepository(
      db: db,
      outbox: DriftOutboxStore(db),
      stamper: makeStubStamper(),
      fxRateSource: const IdentityFxRateSource(),
      baseCurrency: 'CNY',
    );
    for (final (id, side) in [
      ('bank-a', AccountSide.asset),
      ('u-test:income:salary', AccountSide.income),
    ]) {
      await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              id: id,
              type: AccountCategory.bank,
              name: id,
              currency: 'CNY',
              category: Value(side),
              ownerUserId: 'u-test',
              updatedAt: DateTime.utc(2026),
              updatedByDevice: 'dev-test',
              hlc: const Hlc(wallMillis: 1, counter: 0, nodeId: 'dev-test'),
            ),
          );
    }
    final parsed = row(
      description: 'Salary',
      amount: 1800,
    ).copyWith(kind: IngestTransactionKind.income, categoryHint: 'salary');
    final planned = IngestPipeline().planFromParsed(
      parsed: [parsed],
      source: const IngestSource(kind: IngestSourceKind.csv, payload: ''),
      existingLedger: const [],
      ownerUserId: 'u-test',
    );
    await store.putAll(planned.drafts);
    final build = JournalEntryBuilders.income(
      date: parsed.occurredAt,
      toAccountId: 'bank-a',
      incomeAccountId: 'u-test:income:salary',
      amount: Decimal.fromInt(18),
      currency: 'CNY',
      payee: parsed.description,
    );
    await repository.create(entry: build.entry, postings: build.postings);
    final dedup = IngestDedupService(store: store, repository: repository);
    final applier = CountingApplier();
    final service = IngestConfirmService(
      applier: applier,
      store: store,
      checkDuplicate: dedup.checkForConfirm,
    );
    final confirmed = await service.confirmAllFresh([
      IngestReviewItem(draft: planned.drafts.single),
    ], fromAccountId: 'bank-a');
    expect(confirmed.confirmed, isEmpty);
    expect(
      confirmed.failures.single.error.code,
      IngestConfirmError.duplicateDetected,
    );
    expect(applier.calls, 0);
    await dedup.refreshPending();
    var draft = (await store.listPendingReviewItems()).single.draft;
    expect(draft.verdict, DedupVerdict.duplicate);
    expect(
      (await dedup.checkForConfirm(draft, accountId: 'bank-b')).verdict,
      DedupVerdict.newTxn,
    );
    await store.updateParsed(
      draftId: draft.draftId,
      expectedRevision: draft.revision,
      parsed: parsed.copyWith(amountMinor: 5000),
    );
    await dedup.refreshPending();
    draft = (await store.listPendingReviewItems()).single.draft;
    expect(draft.verdict, DedupVerdict.newTxn);
    expect(draft.dedupTargetEntryId, isNull);
  });

  test(
    'structured ledger entries do not use date drift even without source ids',
    () {
      final original = row().copyWith(dateHasTime: false);
      final candidate = IngestDedupCandidate(
        id: 'confirmed',
        description: original.description,
        amountMinor: original.amountMinor.toString(),
        currency: original.currency,
        occurredAt: original.occurredAt,
        kind: original.kind,
        dateHasTime: false,
        allowDateDrift: false,
      );
      expect(
        classifyDedup(row(day: 19).copyWith(dateHasTime: false), [
          candidate,
        ]).verdict,
        DedupVerdict.newTxn,
      );
    },
  );

  test(
    'source identities survive staging and distinguish provider accounts',
    () {
      const reference = IngestSourceReference(
        provider: 'bank',
        transactionId: '10001',
        account: 'card-a',
      );
      final parsed = row().copyWith(
        sourceReference: reference,
        dateHasTime: false,
      );
      final restored = ParsedTransaction.fromJson(parsed.toJson());
      expect(restored.sourceReference!.identity, reference.identity);
      expect(restored.dateHasTime, isFalse);
      expect(
        const IngestSourceReference(
          provider: 'bank',
          transactionId: '10001',
          account: 'card-b',
        ).identity,
        isNot(reference.identity),
      );
      final tags = ingestProvenanceTags(
        kind: parsed.kind.wire,
        reference: reference,
      );
      expect(tags.join(), isNot(contains('10001')));
      expect(ingestTagsFromPayload([...tags, 'arbitrary:user:tag']), tags);
    },
  );

  test(
    'same provider id wins over changed descriptions, amounts and dates',
    () {
      const reference = IngestSourceReference(
        provider: 'wechatPay',
        transactionId: 'order-123',
      );
      final original = row().copyWith(sourceReference: reference);
      final changed = original.copyWith(
        description: 'Corrected merchant',
        amountMinor: -1900,
        occurredAt: DateTime.utc(2026, 7, 18),
      );
      final index = IngestDedupIndex<String>()
        ..add(IngestDedupCandidate.fromParsed(original, id: 'first'), 'first');
      expect(index.match(changed).verdict, DedupVerdict.duplicate);
      expect(index.match(changed).target, 'first');
    },
  );

  test(
    'distinct source ids never collapse even at exactly the same instant',
    () {
      final original = row().copyWith(
        sourceReference: const IngestSourceReference(
          provider: 'bank',
          transactionId: 'id-a',
          account: 'card-a',
        ),
      );
      final changed = original.copyWith(
        sourceReference: const IngestSourceReference(
          provider: 'bank',
          transactionId: 'id-b',
          account: 'card-a',
        ),
      );
      final index = IngestDedupIndex<String>()
        ..add(IngestDedupCandidate.fromParsed(original, id: 'first'), 'first');
      expect(index.match(changed).verdict, DedupVerdict.newTxn);
    },
  );

  test('precise ledger dates keep daily purchases separate and kinds do not collide', () {
    final index = IngestDedupIndex<String>()
      ..add(
        IngestDedupCandidate(
          id: 'first',
          description: row().description,
          amountMinor: '-1800',
          currency: 'CNY',
          occurredAt: row().occurredAt,
          kind: IngestTransactionKind.expense,
          dateHasTime: true,
          accountId: 'bank-a',
        ),
        'first',
      );
    expect(index.match(row(day: 19)).verdict, DedupVerdict.newTxn);
    expect(
      index.match(row().copyWith(kind: IngestTransactionKind.transfer)).verdict,
      DedupVerdict.newTxn,
    );
    expect(
      index.match(row(), accountId: 'different-account').verdict,
      DedupVerdict.newTxn,
    );
  });

  test('daily same-price purchases remain separate across a long batch', () {
    final result = IngestPipeline().planFromParsed(
      parsed: [for (var day = 1; day <= 14; day++) row(day: day)],
      source: const IngestSource(kind: IngestSourceKind.csv, payload: ''),
      existingLedger: const [],
      ownerUserId: 'audit-owner',
    );
    expect(result.newCount, 14);
    expect(result.duplicateCount, 0);
    // Earlier reviewed rows must not bridge a three-day matching window.
    expect(result.drafts.last.verdict, DedupVerdict.newTxn);
  });

  test('distinct provider order ids remain separate', () {
    final result = IngestPipeline().plan(
      source: const IngestSource(
        kind: IngestSourceKind.csv,
        payload:
            '交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号\n'
            '2026-06-18 10:00:00,商户消费,瑞幸咖啡,拿铁,支出,18.00,零钱,支付成功,order-111,merchant-111\n'
            '2026-06-18 15:00:00,商户消费,瑞幸咖啡,拿铁,支出,18.00,零钱,支付成功,order-222,merchant-222\n',
      ),
      existingLedger: const [],
      ownerUserId: 'audit-owner',
    );
    expect(result.drafts, hasLength(2));
    expect(result.drafts.last.verdict, DedupVerdict.newTxn);
  });

  test('small payments must satisfy the relative amount tolerance', () {
    final result = classifyDedup(row(amount: -200), [
      ledgerRow(row(amount: -300)),
    ]);
    expect(result.verdict, DedupVerdict.newTxn);
  });

  test(
    'shared category and channel words do not equate different products',
    () {
      final parsed = row(description: '示例商户 · 牛奶 · 日用百货 · 余额');
      final existing = ledgerRow(row(description: '示例商户 · 纸巾 · 日用百货 · 余额'));
      expect(classifyDedup(parsed, [existing]).verdict, DedupVerdict.newTxn);
    },
  );

  test(
    'dedup snapshot includes pending drafts beyond the review page limit',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final db = makeTestDatabase();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWith((_) async => db),
          activeUserIdProvider.overrideWith((_) => 'audit-owner'),
        ],
      );
      try {
        await container.read(appDatabaseProvider.future);
        final store = container.read(ingestDraftStoreProvider)!;
        await store.putAll([
          for (var i = 0; i <= 200; i++)
            IngestDraft(
              draftId: 'pending-$i',
              ownerUserId: 'audit-owner',
              createdAt: DateTime.utc(2026, 6, 19).add(Duration(seconds: i)),
              sourceKind: IngestSourceKind.csv,
              parsed: row(
                description: i == 0 ? 'Netflix' : 'Merchant$i',
                amount: -6800,
              ),
              verdict: DedupVerdict.newTxn,
              status: DraftStatus.pending,
            ),
        ]);
        expect(await store.countByStatus(DraftStatus.pending), 201);
        expect(await store.listPendingReviewItems(), hasLength(200));
        final result = await container
            .read(ingestControllerProvider)
            .ingest(
              const IngestSource(
                kind: IngestSourceKind.csv,
                payload: 'date,description,amount,currency\n2026-06-18T10:00:00Z,Netflix,-68.00,CNY\n',
              ),
            );
        expect(result.drafts.single.verdict, DedupVerdict.duplicate);
        expect(await store.countByStatus(DraftStatus.pending), 202);
      } finally {
        container.dispose();
        await db.close();
      }
    },
  );

  test('edits invalidate derived evidence and the live check blocks stale fresh decisions', () async {
    final db = makeTestDatabase();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((_) async => db),
        activeUserIdProvider.overrideWith((_) => 'audit-owner'),
      ],
    );
    try {
      await container.read(appDatabaseProvider.future);
      final store = container.read(ingestDraftStoreProvider)!;
      final parsed = row(amount: -1800);
      final existing = [ledgerRow(parsed)];
      final result = IngestPipeline().planFromParsed(
        parsed: [row(amount: -5000)],
        source: const IngestSource(kind: IngestSourceKind.csv, payload: ''),
        existingLedger: existing,
        ownerUserId: 'audit-owner',
      );
      final draft = result.drafts.single;
      expect(draft.verdict, DedupVerdict.newTxn);
      await store.putAll(result.drafts);
      expect(
        await store.updateParsed(
          draftId: draft.draftId,
          expectedRevision: draft.revision,
          parsed: parsed,
        ),
        isTrue,
      );
      final item = (await store.listPendingReviewItems()).single;
      expect(
        classifyDedup(item.draft.parsed, existing).verdict,
        DedupVerdict.duplicate,
      );
      expect(item.draft.verdict, DedupVerdict.likelyDuplicate);
      expect(item.canBatchConfirm, isFalse);
      final applier = CountingApplier();
      final service = IngestConfirmService(
        applier: applier,
        store: store,
        checkDuplicate: (draft, {accountId}) async =>
            classifyDedup(draft.parsed, existing, accountId: accountId),
      );
      final confirmed = await service.confirmAllFresh([
        IngestReviewItem(
          draft: item.draft.withDedup(DedupVerdict.newTxn, null),
        ),
      ], fromAccountId: 'account');
      expect(confirmed.confirmed, isEmpty);
      expect(
        confirmed.failures.single.error.code,
        IngestConfirmError.duplicateDetected,
      );
      expect(applier.calls, 0);
    } finally {
      container.dispose();
      await db.close();
    }
  });

  test(
    'dismissing a match target releases its dependent draft on refresh',
    () async {
      final db = makeTestDatabase();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWith((_) async => db),
          activeUserIdProvider.overrideWith((_) => 'audit-owner'),
        ],
      );
      try {
        await container.read(appDatabaseProvider.future);
        final store = container.read(ingestDraftStoreProvider)!;
        final result = IngestPipeline().planFromParsed(
          parsed: [row(), row()],
          source: const IngestSource(kind: IngestSourceKind.csv, payload: ''),
          existingLedger: const [],
          ownerUserId: 'audit-owner',
        );
        await store.putAll(result.drafts);
        final service = IngestConfirmService(
          applier: CountingApplier(),
          store: store,
        );
        await service.dismiss(result.drafts.first);
        await IngestDedupService(
          store: store,
          repository: JournalEntryRepository(
            db: db,
            outbox: DriftOutboxStore(db),
            stamper: makeStubStamper(),
            fxRateSource: const IdentityFxRateSource(),
            baseCurrency: 'CNY',
          ),
        ).refreshPending();
        final item = (await store.listPendingReviewItems()).single;
        expect(item.draft.dedupTargetEntryId, isNull);
        expect(item.draft.verdict, DedupVerdict.newTxn);
        expect(item.canBatchConfirm, isTrue);
      } finally {
        container.dispose();
        await db.close();
      }
    },
  );

  test('confirmed transfers participate in reimport reconciliation', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final db = makeTestDatabase();
    for (final id in ['bank-a', 'bank-b']) {
      await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              id: id,
              type: AccountCategory.bank,
              name: id,
              currency: 'CNY',
              category: const Value(AccountSide.asset),
              ownerUserId: 'u-test',
              updatedAt: DateTime.utc(2026),
              updatedByDevice: 'dev-test',
              hlc: const Hlc(wallMillis: 1, counter: 0, nodeId: 'dev-test'),
            ),
          );
    }
    final repository = JournalEntryRepository(
      db: db,
      outbox: DriftOutboxStore(db),
      stamper: makeStubStamper(),
      fxRateSource: const IdentityFxRateSource(),
      baseCurrency: 'CNY',
    );
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWith((_) async => db),
        activeUserIdProvider.overrideWith((_) => 'u-test'),
        journalEntryRepositoryProvider.overrideWith((_) async => repository),
      ],
    );
    try {
      await container.read(appDatabaseProvider.future);
      final store = container.read(ingestDraftStoreProvider)!;
      final controller = container.read(ingestControllerProvider);
      const source = IngestSource(
        kind: IngestSourceKind.csv,
        payload: 'date,description,debit,credit,currency,transactionid,accountnumber\n2026-06-18,Transfer to savings,100.00,,CNY,bank-transfer-100,source-card-a\n',
      );
      final first = await controller.ingest(source);
      final draft = first.drafts.single;
      expect(draft.parsed.kind, IngestTransactionKind.transfer);
      final build = JournalEntryBuilders.transfer(
        date: draft.parsed.occurredAt,
        fromAccountId: 'bank-a',
        toAccountId: 'bank-b',
        amount: Decimal.fromInt(100),
        currency: 'CNY',
        narration: draft.parsed.description,
      );
      await IngestExternalConfirmationCoordinator(store: store)
          .confirm<JournalMutationReceipt>(
            draft,
            kind: IngestExternalKind.transfer,
            apply: (token) => repository.createWithReceipt(
              entry: JournalEntryDraft(
                id: token,
                date: build.entry.date,
                settledOn: build.entry.settledOn,
                narration: build.entry.narration,
                payee: build.entry.payee,
                tagIds: [
                  ...build.entry.tagIds,
                  ...ingestProvenanceTags(
                    kind: draft.parsed.kind.wire,
                    reference: draft.parsed.sourceReference,
                  ),
                ],
                flag: build.entry.flag,
              ),
              postings: build.postings,
            ),
            entityId: (receipt) => receipt.after.entry.id,
          );
      expect(await store.countByStatus(DraftStatus.confirmed), 1);
      expect(await db.select(db.journalEntries).get(), hasLength(1));
      final second = await controller.ingest(source);
      expect(second.drafts.single.verdict, DedupVerdict.duplicate);
      final corrected = IngestPipeline().planFromParsed(
        parsed: [
          draft.parsed.copyWith(
            description: 'Corrected transfer memo',
            occurredAt: DateTime.utc(2026, 7, 18),
          ),
        ],
        source: source,
        existingLedger: await IngestDedupService(
          store: store,
          repository: repository,
        ).readLedger(),
        ownerUserId: 'u-test',
      );
      expect(corrected.drafts.single.verdict, DedupVerdict.duplicate);
    } finally {
      container.dispose();
      await db.close();
    }
  });
}
