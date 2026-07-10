import 'package:decimal/decimal.dart';
import 'package:naviwealth/core/ai/write/drift_undo_stack.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/data/securities_catalog/asset_search_hit.dart';
import 'package:naviwealth/features/finance/data/securities_catalog/securities_search_service.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_confirm_service.dart';
import 'package:naviwealth/features/finance/ingest/domain/ingest_models.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/rebalance/data/rebalance_execution_codecs.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_execution.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_models.dart';

const taskFlowOwner = 'golden-owner';
final taskFlowUtc = DateTime.utc(2026, 6, 15, 1, 30);
final taskFlowLocalDate = DateTime(2026, 6, 15, 9, 30);

SyncMeta _sync(int counter) => SyncMeta(
  ownerUserId: taskFlowOwner,
  updatedAt: taskFlowUtc.add(Duration(minutes: counter)),
  updatedByDevice: 'golden-device',
  hlc: Hlc(
    wallMillis: taskFlowUtc.millisecondsSinceEpoch + counter,
    counter: counter,
    nodeId: 'golden-device',
  ),
);

final taskFlowAccounts = <Account>[
  Account(
    id: 'golden-bank-cny',
    type: AccountCategory.bank,
    name: 'Daily checking',
    currency: 'CNY',
    institution: 'Harbor Bank',
    category: AccountSide.asset,
    sync: _sync(1),
  ),
  Account(
    id: 'golden-bank-usd',
    type: AccountCategory.bank,
    name: 'Travel cash',
    currency: 'USD',
    institution: 'Harbor Bank',
    category: AccountSide.asset,
    sync: _sync(2),
  ),
  Account(
    id: 'golden-broker',
    type: AccountCategory.broker,
    name: 'Long-term brokerage',
    currency: 'USD',
    institution: 'Northstar Securities',
    category: AccountSide.asset,
    sync: _sync(3),
  ),
  Account(
    id: 'golden-dining',
    type: AccountCategory.asset,
    name: 'Dining & coffee',
    currency: 'CNY',
    category: AccountSide.expense,
    sync: _sync(4),
  ),
];

final taskFlowIngestItems = <IngestReviewItem>[
  IngestReviewItem(
    draft: IngestDraft(
      draftId: 'golden-ingest-1',
      ownerUserId: taskFlowOwner,
      createdAt: taskFlowUtc,
      sourceKind: IngestSourceKind.csv,
      parsed: ParsedTransaction(
        description: 'Morning coffee',
        amountMinor: -3850,
        currency: 'CNY',
        occurredAt: taskFlowUtc,
        categoryHint: 'golden-dining',
        confidence: 0.98,
      ),
      verdict: DedupVerdict.newTxn,
      status: DraftStatus.pending,
      originLabel: 'june-statement.csv',
    ),
  ),
  IngestReviewItem(
    draft: IngestDraft(
      draftId: 'golden-ingest-2',
      ownerUserId: taskFlowOwner,
      createdAt: taskFlowUtc.add(const Duration(minutes: 1)),
      sourceKind: IngestSourceKind.csv,
      parsed: ParsedTransaction(
        description: 'Metro card top-up',
        amountMinor: -10000,
        currency: 'CNY',
        occurredAt: taskFlowUtc.subtract(const Duration(days: 1)),
        confidence: 0.92,
      ),
      verdict: DedupVerdict.likelyDuplicate,
      status: DraftStatus.pending,
      dedupTargetEntryId: 'existing-entry',
      originLabel: 'june-statement.csv',
    ),
  ),
];

final taskFlowUndoEntry = PersistedUndoEntry(
  token: 'golden-undo-token',
  kind: 'journal_edit',
  payload: const <String, Object?>{
    'summary_zh': 'Updated the monthly investment plan',
  },
  createdAt: taskFlowUtc,
  expiresAt: null,
);

RebalanceExecutionSession taskFlowRebalanceSession() {
  final plan = RebalancePlan(
    target: const TargetAllocation(
      weights: <AssetCategory, double>{
        AssetCategory.cash: 0.2,
        AssetCategory.stock: 0.5,
        AssetCategory.etf: 0.3,
      },
    ),
    actualWeights: const <AssetCategory, double>{
      AssetCategory.cash: 0.35,
      AssetCategory.stock: 0.4,
      AssetCategory.etf: 0.25,
    },
    drifts: const <Drift>[
      Drift(
        category: AssetCategory.cash,
        actualWeight: 0.35,
        targetWeight: 0.2,
        severity: DriftSeverity.critical,
      ),
      Drift(
        category: AssetCategory.stock,
        actualWeight: 0.4,
        targetWeight: 0.5,
        severity: DriftSeverity.warning,
      ),
    ],
    trades: <SuggestedTrade>[
      SuggestedTrade(
        category: AssetCategory.stock,
        assetId: 'us_stock:AAPL',
        assetLabel: 'Apple',
        direction: TradeDirection.buy,
        amount: Money(Decimal.fromInt(5000), 'USD'),
        description: 'Add to Apple',
      ),
      SuggestedTrade(
        category: AssetCategory.etf,
        direction: TradeDirection.buy,
        amount: Money(Decimal.fromInt(2500), 'USD'),
        description: 'Add broad-market ETF',
      ),
      SuggestedTrade(
        category: AssetCategory.cash,
        direction: TradeDirection.sell,
        amount: Money(Decimal.fromInt(7500), 'USD'),
        description: 'Reduce cash reserve',
      ),
    ],
    estimatedFees: Money(Decimal.parse('8.50'), 'USD'),
    estimatedTaxes: Money(Decimal.zero, 'USD'),
    driftBeforePct: 0.15,
    driftAfterPct: 0.012,
    totalAssets: Money(Decimal.fromInt(50000), 'USD'),
  );
  const sessionId = 'golden-rebalance-session';
  final items = <RebalanceExecutionItem>[
    for (var index = 0; index < plan.trades.length; index++)
      RebalanceExecutionItem(
        id: 'golden-rebalance-item-$index',
        sessionId: sessionId,
        ownerUserId: taskFlowOwner,
        position: index,
        suggestion: plan.trades[index],
        state: index == 1
            ? RebalanceExecutionItemState.skipped
            : RebalanceExecutionItemState.needsDetails,
        createdAt: taskFlowUtc,
        updatedAt: taskFlowUtc,
      ),
  ];
  return RebalanceExecutionSession(
    id: sessionId,
    ownerUserId: taskFlowOwner,
    status: RebalanceExecutionSessionStatus.active,
    plan: plan,
    rawPlanJson: RebalancePlanCodec.encode(plan),
    planFingerprint: RebalancePlanFingerprint.compute(plan),
    items: items,
    createdAt: taskFlowUtc,
    updatedAt: taskFlowUtc,
  );
}

final class TaskFlowGoldenSearchService extends SecuritiesSearchService {
  TaskFlowGoldenSearchService({required super.db});

  @override
  Future<List<AssetSearchHit>> searchLocal(
    String query, {
    int limit = 20,
    AssetMarket? market,
  }) async => const <AssetSearchHit>[
    AssetSearchHit(
      id: 'us_stock:AAPL',
      symbol: 'AAPL',
      market: AssetMarket.usStock,
      type: AssetType.stock,
      currency: 'USD',
      source: AssetSearchHitSource.catalog,
      match: AssetSearchHitMatch.exact,
      rank: 0,
      nameEn: 'Apple',
    ),
    AssetSearchHit(
      id: 'us_stock:MSFT',
      symbol: 'MSFT',
      market: AssetMarket.usStock,
      type: AssetType.stock,
      currency: 'USD',
      source: AssetSearchHitSource.catalog,
      match: AssetSearchHitMatch.prefix,
      rank: 1,
      nameEn: 'Microsoft',
    ),
  ];
}
