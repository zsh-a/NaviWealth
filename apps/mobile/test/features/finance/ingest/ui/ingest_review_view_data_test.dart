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
}) => IngestDraft(
  draftId: id,
  ownerUserId: 'u1',
  createdAt: DateTime.utc(2026, 8, 1),
  sourceKind: IngestSourceKind.csv,
  parsed: ParsedTransaction(
    description: id,
    amountMinor: -100,
    currency: 'CNY',
    occurredAt: DateTime.utc(2026, 8, 1),
  ),
  verdict: verdict,
  status: status,
);

void main() {
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
