import 'package:decimal/decimal.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/price_mutation_receipt.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/journal_entry.dart';
import 'package:naviwealth/features/finance/domain/models/posting.dart';
import 'package:naviwealth/features/finance/domain/models/price_observation.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/finance/investment/application/trade_entry_submission_service.dart';
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_draft.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_execution.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_models.dart';

final testNow = DateTime.utc(2026, 7, 10, 8);

SyncMeta testSync({String owner = 'owner-a', int counter = 1}) => SyncMeta(
  ownerUserId: owner,
  updatedAt: testNow.add(Duration(minutes: counter)),
  updatedByDevice: 'device-a',
  hlc: Hlc(
    wallMillis: testNow.millisecondsSinceEpoch + counter,
    counter: counter,
    nodeId: 'device-a',
  ),
);

RebalancePlan testPlan({bool reverseCollections = false, Decimal? buyAmount}) {
  const cashDrift = Drift(
    category: AssetCategory.cash,
    actualWeight: 0.5,
    targetWeight: 0.4,
    severity: DriftSeverity.warning,
  );
  const stockDrift = Drift(
    category: AssetCategory.stock,
    assetId: 'us_stock:AAPL',
    assetLabel: 'Apple',
    actualWeight: 0.5,
    targetWeight: 0.6,
    severity: DriftSeverity.warning,
  );
  final sell = SuggestedTrade(
    category: AssetCategory.cash,
    direction: TradeDirection.sell,
    amount: Money(Decimal.fromInt(100), 'USD'),
    description: 'Reduce cash',
  );
  final buy = SuggestedTrade(
    category: AssetCategory.stock,
    assetId: 'us_stock:AAPL',
    assetLabel: 'Apple',
    direction: TradeDirection.buy,
    amount: Money(buyAmount ?? Decimal.fromInt(100), 'USD'),
    description: 'Buy Apple',
  );
  final weights = reverseCollections
      ? <AssetCategory, double>{
          AssetCategory.cash: 0.4,
          AssetCategory.stock: 0.5,
        }
      : <AssetCategory, double>{
          AssetCategory.stock: 0.5,
          AssetCategory.cash: 0.4,
        };
  final targets = reverseCollections
      ? <String, AssetTargetAllocation>{
          'us_stock:AAPL': const AssetTargetAllocation(
            assetId: 'us_stock:AAPL',
            label: 'Apple',
            category: AssetCategory.stock,
            weight: 0.1,
          ),
        }
      : <String, AssetTargetAllocation>{
          'us_stock:AAPL': const AssetTargetAllocation(
            assetId: 'us_stock:AAPL',
            label: 'Apple',
            category: AssetCategory.stock,
            weight: 0.1,
          ),
        };
  return RebalancePlan(
    target: TargetAllocation(weights: weights, assetTargets: targets),
    actualWeights: reverseCollections
        ? {AssetCategory.cash: 0.5, AssetCategory.stock: 0.5}
        : {AssetCategory.stock: 0.5, AssetCategory.cash: 0.5},
    drifts: reverseCollections
        ? [stockDrift, cashDrift]
        : [cashDrift, stockDrift],
    trades: reverseCollections ? [buy, sell] : [sell, buy],
    estimatedFees: Money(Decimal.parse('0.2'), 'USD'),
    estimatedTaxes: Money(Decimal.zero, 'USD'),
    driftBeforePct: 0.1,
    driftAfterPct: 0.001,
    totalAssets: Money(Decimal.fromInt(1000), 'USD'),
  );
}

RebalanceExecutionRequest testRequest(
  String transactionId, {
  String owner = 'owner-a',
  DateTime? tradeDate,
}) {
  final sync = testSync(owner: owner);
  return RebalanceExecutionRequest(
    transactionId: transactionId,
    account: Account(
      id: 'broker-account',
      type: AccountCategory.broker,
      name: 'Broker',
      currency: 'USD',
      institution: 'Example',
      accountNumber: '1234',
      note: 'Primary',
      category: AccountSide.asset,
      icon: 'account_balance',
      color: '#123456',
      sync: sync,
    ),
    cashAccount: Account(
      id: 'cash-account',
      type: AccountCategory.cash,
      name: 'Cash',
      currency: 'USD',
      category: AccountSide.asset,
      parentId: 'broker-account',
      sync: sync,
    ),
    asset: Asset(
      id: 'us_stock:AAPL',
      type: AssetType.stock,
      symbol: 'AAPL',
      currency: 'USD',
      name: 'Apple',
      market: 'us_stock',
      industry: 'Technology',
      region: 'US',
      isin: 'US0378331005',
      logoUrl: 'https://example.invalid/aapl.png',
      metadataJson: '{"source":"test"}',
      sync: sync,
    ),
    type: TradeType.buy,
    quantity: Decimal.parse('1.25'),
    price: Decimal.parse('123.45'),
    currency: 'USD',
    tradeDate: tradeDate ?? testNow,
    fee: Decimal.parse('0.2'),
    tax: Decimal.zero,
    note: 'rebalance',
  );
}

TradeMutationReceipt testReceipt(
  String transactionId, {
  String owner = 'owner-a',
  DateTime? entryDate,
}) {
  final beforeSync = testSync(owner: owner, counter: 1);
  final afterSync = testSync(owner: owner, counter: 2);
  final before = JournalEntryWithPostings(
    entry: JournalEntry(
      id: transactionId,
      date: entryDate ?? testNow,
      settledOn: testNow.add(const Duration(days: 2)),
      narration: 'Before',
      payee: 'Broker',
      tagIds: const ['rebalance'],
      flag: EntryFlag.confirmed,
      sync: beforeSync,
    ),
    postings: [
      Posting(
        id: '$transactionId-before-posting',
        journalEntryId: transactionId,
        position: 0,
        accountId: 'broker-account',
        units: Decimal.one,
        unit: 'us_stock:AAPL',
        cost: Cost(
          perUnit: Decimal.fromInt(100),
          currency: 'USD',
          lotId: 'lot-before',
          acquiredOn: testNow.subtract(const Duration(days: 30)),
        ),
        sync: beforeSync,
      ),
    ],
  );
  final after = JournalEntryWithPostings(
    entry: JournalEntry(
      id: transactionId,
      date: entryDate ?? testNow,
      narration: 'Buy Apple',
      tagIds: const ['rebalance', 'trade'],
      flag: EntryFlag.confirmed,
      sync: afterSync,
    ),
    postings: [
      Posting(
        id: '$transactionId-posting-1',
        journalEntryId: transactionId,
        position: 0,
        accountId: 'broker-account',
        units: Decimal.one,
        unit: 'us_stock:AAPL',
        cost: Cost(
          perUnit: Decimal.parse('123.45'),
          currency: 'USD',
          lotId: 'lot-after',
          acquiredOn: testNow,
        ),
        price: Price(perUnit: Decimal.parse('123.45'), currency: 'USD'),
        sync: afterSync,
      ),
      Posting(
        id: '$transactionId-posting-2',
        journalEntryId: transactionId,
        position: 1,
        accountId: 'cash-account',
        units: Decimal.parse('-123.45'),
        unit: 'USD',
        sync: afterSync,
      ),
    ],
  );
  return TradeMutationReceipt(
    transactionId: transactionId,
    assetAfter: Asset(
      id: 'us_stock:AAPL',
      type: AssetType.stock,
      symbol: 'AAPL',
      currency: 'USD',
      name: 'Apple',
      market: 'us_stock',
      sync: afterSync,
    ),
    journal: JournalMutationReceipt(before: before, after: after),
    price: PriceMutationReceipt(
      before: PriceObservation(
        id: transactionId,
        unit: 'us_stock:AAPL',
        quoteCurrency: 'USD',
        observedOn: testNow.subtract(const Duration(days: 1)),
        perUnit: Decimal.fromInt(120),
        source: 'market',
        sync: beforeSync,
      ),
      after: PriceObservation(
        id: transactionId,
        unit: 'us_stock:AAPL',
        quoteCurrency: 'USD',
        observedOn: testNow,
        perUnit: Decimal.parse('123.45'),
        source: 'trade',
        sync: afterSync,
      ),
    ),
  );
}
