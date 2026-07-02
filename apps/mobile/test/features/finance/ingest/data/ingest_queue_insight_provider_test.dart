import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_queue_insight_provider.dart';
import 'package:naviwealth/features/finance/ingest/data/providers.dart';
import 'package:naviwealth/features/finance/ingest/domain/ingest_models.dart';
import 'package:naviwealth/features/home/data/dashboard_insights_provider.dart';
import 'package:naviwealth/features/home/domain/insight_models.dart';

IngestDraft _draft(String id, DedupVerdict verdict) => IngestDraft(
  draftId: id,
  ownerUserId: 'u1',
  createdAt: DateTime.utc(2026, 5, 10),
  sourceKind: IngestSourceKind.csv,
  parsed: ParsedTransaction(
    description: 'x',
    amountMinor: -100,
    currency: 'CNY',
    occurredAt: DateTime.utc(2026, 5, 10),
  ),
  verdict: verdict,
  status: DraftStatus.pending,
);

Future<IngestQueueSummary?> _summaryFor(List<IngestDraft> drafts) async {
  final container = ProviderContainer(
    overrides: [
      pendingIngestDraftsProvider.overrideWith((ref) => Stream.value(drafts)),
    ],
  );
  addTearDown(container.dispose);
  // Keep the autoDispose stream alive across the async gap so it isn't
  // torn down mid-loading before Stream.value emits.
  final sub = container.listen(ingestQueueInsightProvider, (_, _) {});
  addTearDown(sub.close);
  await container.read(pendingIngestDraftsProvider.future);
  return container.read(ingestQueueInsightProvider);
}

void main() {
  test('null when the queue is empty', () async {
    expect(await _summaryFor(const []), isNull);
  });

  test('counts pending + fresh subset', () async {
    final s = await _summaryFor([
      _draft('a', DedupVerdict.newTxn),
      _draft('b', DedupVerdict.newTxn),
      _draft('c', DedupVerdict.duplicate),
      _draft('d', DedupVerdict.likelyDuplicate),
    ]);
    expect(s, isNotNull);
    expect(s!.pendingCount, 4);
    expect(s.freshCount, 2);
    expect(s.isEmpty, isFalse);
    expect(s.scopeHash, '4:2');
  });

  test('insightScopeHash is stable for the ingestQueue kind', () {
    final hash = insightScopeHash(
      const InsightItem(
        icon: FLucideIcons.inbox,
        kind: InsightKind.ingestQueue,
        ingestPendingCount: 7,
        ingestFreshCount: 3,
      ),
    );
    expect(hash, '7:3');
  });
}
