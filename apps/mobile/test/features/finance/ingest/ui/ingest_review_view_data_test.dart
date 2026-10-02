import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_confirm_service.dart';
import 'package:naviwealth/features/finance/ingest/domain/ingest_models.dart';
import 'package:naviwealth/features/finance/ingest/ui/ingest_review_view_data.dart';

final _sync = SyncMeta(
  ownerUserId: 'u1',
  updatedAt: DateTime.utc(2026, 8, 1),
  updatedByDevice: 'test',
  hlc: Hlc.zero('test'),
);

Account _account(String id, AccountCategory type, {bool archived = false}) =>
    Account(
      id: id,
      type: type,
      name: id,
      currency: 'CNY',
      archived: archived,
      sync: _sync,
    );

IngestDraft _draft(
  String id, {
  DraftStatus status = DraftStatus.pending,
  DedupVerdict verdict = DedupVerdict.newTxn,
  IngestTransactionKind kind = IngestTransactionKind.expense,
  String? category,
  int amountMinor = -100,
  DateTime? occurredAt,
}) => IngestDraft(
  draftId: id,
  ownerUserId: 'u1',
  createdAt: DateTime.utc(2026, 8, 1),
  sourceKind: IngestSourceKind.csv,
  parsed: ParsedTransaction(
    description: id,
    amountMinor: amountMinor,
    currency: 'CNY',
    occurredAt: occurredAt ?? DateTime.utc(2026, 8, 1),
    kind: kind,
    categoryHint: category,
  ),
  verdict: verdict,
  status: status,
);

void main() {
  test('batch counts exclude typed destinations and transient recovery', () {
    final data = IngestReviewViewData.from(
      accounts: const [],
      items: [
        IngestReviewItem(draft: _draft('expense')),
        IngestReviewItem(
          draft: _draft('income', kind: IngestTransactionKind.income),
        ),
        IngestReviewItem(
          draft: _draft('transfer', kind: IngestTransactionKind.transfer),
        ),
        IngestReviewItem(
          draft: _draft('trade', kind: IngestTransactionKind.trade),
        ),
        IngestReviewItem(draft: _draft('recovering')),
      ],
      selectedAccountId: null,
      pendingFinalizeIds: {'recovering'},
      filter: IngestReviewFilter.ready,
    );
    expect(data.items.map((item) => item.draft.draftId), ['expense', 'income']);
    expect(data.freshCount, 2);
    expect(data.allItems, hasLength(5));
    expect(data.filterCounts[IngestReviewFilter.attention], 3);
  });

  test(
    'search and filtering include records after 200 duplicates in a long queue',
    () {
      final items = [
        for (var i = 0; i < 2000; i++)
          IngestReviewItem(
            draft: _draft(
              'row-$i',
              verdict: i < 200 ? DedupVerdict.duplicate : DedupVerdict.newTxn,
              category: i == 1999 ? 'Travel' : null,
            ),
          ),
      ];
      final data = IngestReviewViewData.from(
        accounts: const [],
        items: items,
        selectedAccountId: null,
        pendingFinalizeIds: const {},
        filter: IngestReviewFilter.ready,
      );
      expect(data.items, hasLength(1800));
      expect(data.freshCount, 1800);
      final searched = IngestReviewViewData.from(
        accounts: const [],
        items: items,
        selectedAccountId: null,
        pendingFinalizeIds: const {},
        query: 'TRAVEL row-1999',
        filter: IngestReviewFilter.ready,
      );
      expect(searched.items.single.draft.draftId, 'row-1999');
      expect(searched.allItems, hasLength(2000));
    },
  );

  test('attention keeps failures and recovery actionable without admitting duplicates to batch writes', () {
    final items = [
      IngestReviewItem(draft: _draft('failure')),
      IngestReviewItem(
        draft: _draft('likely', verdict: DedupVerdict.likelyDuplicate),
      ),
      IngestReviewItem(
        draft: _draft('certain', verdict: DedupVerdict.duplicate),
      ),
      IngestReviewItem(draft: _draft('unreadable'), recoveryUnreadable: true),
    ];
    final data = IngestReviewViewData.from(
      accounts: const [],
      items: items,
      selectedAccountId: null,
      pendingFinalizeIds: const {},
      filter: IngestReviewFilter.attention,
      attentionIds: {'failure'},
    );
    expect(data.items.map((item) => item.draft.draftId), [
      'failure',
      'likely',
      'unreadable',
    ]);
    expect(data.freshCount, 1);
    expect(data.filterCounts[IngestReviewFilter.duplicate], 1);
  });

  test('date and amount sorting are stable for equal values', () {
    final items = [
      IngestReviewItem(draft: _draft('first', amountMinor: -200)),
      IngestReviewItem(draft: _draft('second', amountMinor: -200)),
      IngestReviewItem(
        draft: _draft(
          'newer',
          amountMinor: -300,
          occurredAt: DateTime.utc(2026, 8, 2),
        ),
      ),
    ];
    for (final sort in [IngestReviewSort.newest, IngestReviewSort.amount]) {
      final data = IngestReviewViewData.from(
        accounts: const [],
        items: items,
        selectedAccountId: null,
        pendingFinalizeIds: const {},
        sort: sort,
      );
      expect(data.items.map((item) => item.draft.draftId), [
        'newer',
        'first',
        'second',
      ]);
    }
  });

  test('filters archived accounts and prefers cash as fallback', () {
    final data = IngestReviewViewData.from(
      accounts: <Account>[
        _account('archived-cash', AccountCategory.cash, archived: true),
        _account('broker', AccountCategory.broker),
        _account('bank', AccountCategory.bank),
        _account('cash', AccountCategory.cash),
      ],
      items: const <IngestReviewItem>[],
      selectedAccountId: 'missing',
      pendingFinalizeIds: const <String>{},
    );

    expect(data.payableAccounts.map((account) => account.id), <String>[
      'broker',
      'bank',
      'cash',
    ]);
    expect(data.selectedAccountId, 'cash');
  });

  test('preserves a valid selection and derives actionable fresh drafts', () {
    final fresh = _draft('fresh');
    final duplicate = _draft(
      'duplicate',
      verdict: DedupVerdict.likelyDuplicate,
    );
    final finalizedElsewhere = _draft('finalized-elsewhere');
    final dismissed = _draft('dismissed', status: DraftStatus.dismissed);
    final unreadable = _draft('unreadable');
    final data = IngestReviewViewData.from(
      accounts: <Account>[
        _account('bank', AccountCategory.bank),
        _account('cash', AccountCategory.cash),
      ],
      items: <IngestReviewItem>[
        IngestReviewItem(draft: fresh),
        IngestReviewItem(draft: duplicate),
        IngestReviewItem(draft: finalizedElsewhere),
        IngestReviewItem(draft: dismissed),
        IngestReviewItem(draft: unreadable, recoveryUnreadable: true),
      ],
      selectedAccountId: 'bank',
      pendingFinalizeIds: const <String>{'finalized-elsewhere'},
    );

    expect(data.selectedAccountId, 'bank');
    expect(data.actionableDrafts.map((draft) => draft.draftId), <String>[
      'fresh',
      'duplicate',
    ]);
    expect(data.freshCount, 1);
  });

  test('has no fallback selection when every account is archived', () {
    final data = IngestReviewViewData.from(
      accounts: <Account>[
        _account('cash', AccountCategory.cash, archived: true),
      ],
      items: const <IngestReviewItem>[],
      selectedAccountId: 'cash',
      pendingFinalizeIds: const <String>{},
    );

    expect(data.payableAccounts, isEmpty);
    expect(data.selectedAccountId, isNull);
  });
}
