import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/composition/proposal_applier.dart';
import 'package:naviwealth/core/ai/composition/proposal_apply_state.dart';
import 'package:naviwealth/core/ai/composition/proposal_plan.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/features/finance/composition/finance_proposal_applier.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/domain/invariants.dart';
import 'package:naviwealth/features/finance/data/repositories/account_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/manual_asset_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/price_repository.dart';
import 'package:naviwealth/features/finance/liabilities/data/liability_repository.dart';
import 'package:naviwealth/features/investment/domain/models/lot.dart';
import 'package:naviwealth/features/investment/domain/trade_entry/trade_draft.dart';
import 'package:naviwealth/features/investment/domain/trade_entry/trade_entry_plan.dart';
import 'package:naviwealth/features/investment/domain/trade_entry/trade_entry_service.dart';
import 'package:naviwealth/features/options_income/data/options_strategy_profile_repository.dart';
import 'package:naviwealth/features/options_income/data/trade_journal_repository.dart';
import 'package:naviwealth/features/options_income/domain/options_strategy_profile.dart';
import 'package:naviwealth/features/options_income/domain/trade_journal_entry.dart';

import '../../../core/persistence/test_database.dart';
import '../../../features/finance/data/repositories/_stub_stamper.dart';

void main() {
  late AppDatabase db;
  late InMemoryOutboxStore outbox;
  late PriceRepository priceRepo;
  late JournalEntryRepository journalEntryRepo;
  late AccountRepository accountRepo;
  late ManualAssetRepository manualAssetRepo;
  late LiabilityRepository liabilityRepo;
  late OptionsStrategyProfileRepository profileRepo;
  late TradeJournalRepository journalRepo;
  late FinanceProposalApplier applier;
  Map<String, Object?>? firePlanAfter;
  Map<String, Object?>? fireBucketPayload;

  ReadyProposalPlan plan(String kind, Map<String, Object?> payload) =>
      ReadyProposalPlan(
        proposalId: 'p1',
        kind: kind,
        summaryZh: 'summary',
        payload: payload,
      );

  setUp(() {
    db = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    final stamper = makeStubStamper();
    priceRepo = PriceRepository(db: db, outbox: outbox, stamper: stamper);
    journalEntryRepo = JournalEntryRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
      fxRateSource: const _OneFxRateSource(),
      baseCurrency: 'USD',
    );
    accountRepo = AccountRepository(db: db, outbox: outbox, stamper: stamper);
    manualAssetRepo = ManualAssetRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
      priceRepo: priceRepo,
      journalEntryRepo: journalEntryRepo,
    );
    liabilityRepo = LiabilityRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
      journalEntryRepo: journalEntryRepo,
    );
    profileRepo = OptionsStrategyProfileRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
    );
    journalRepo = TradeJournalRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
    );
    firePlanAfter = null;
    fireBucketPayload = null;
    applier = FinanceProposalApplier(
      tradeEntryService: _FakeTradeEntryService(),
      journalEntryRepo: journalEntryRepo,
      priceRepo: priceRepo,
      accountRepo: accountRepo,
      manualAssetRepo: manualAssetRepo,
      liabilityRepo: liabilityRepo,
      optionsProfileRepo: profileRepo,
      tradeJournalRepo: journalRepo,
      currentUserId: () async => 'u-test',
      firePlanWriter: (after) async {
        firePlanAfter = after;
      },
      fireBucketRuleWriter: (payload) async {
        fireBucketPayload = payload;
        return payload['target_id'] as String;
      },
    );
  });

  tearDown(() async => db.close());

  test(
    'expense creates a journal entry against the seeded category account',
    () async {
      final state = await applier.apply(
        plan('expense', {
          'account_id': 'cash-wallet',
          'amount': '42.50',
          'currency': 'CNY',
          'date': '2026-02-03T00:00:00Z',
          'category': 'coffee',
          'note': 'Latte',
        }),
      );

      expect(state.status, ProposalApplyStatus.applied);
      expect(state.appliedTable, 'journal_entries');

      final stored = await journalEntryRepo.getById(state.appliedEntityId!);
      expect(stored, isNotNull);
      expect(stored!.entry.narration, 'Latte');
      expect(stored.postings.map((p) => p.accountId).toSet(), <String>{
        'cash-wallet',
        AccountRepository.systemAccountIdForPath(
          'expense:coffee',
          ownerUserId: 'u-test',
        ),
      });

      await applier.undo(state);
      expect(await journalEntryRepo.getById(state.appliedEntityId!), isNull);
    },
  );

  test('expense rejects unknown category slugs before writing', () async {
    await expectLater(
      applier.apply(
        plan('expense', {
          'account_id': 'cash-wallet',
          'amount': '42.50',
          'category': 'does-not-exist',
        }),
      ),
      throwsA(
        isA<ProposalApplyException>().having(
          (e) => e.message,
          'message',
          contains('Unknown expense category'),
        ),
      ),
    );

    expect(await db.select(db.journalEntries).get(), isEmpty);
  });

  test('account_create persists an account and undo tombstones it', () async {
    final state = await applier.apply(
      plan('account_create', {
        'name': 'Brokerage',
        'type': 'brokerage',
        'currency': 'USD',
        'institution': 'Test Broker',
      }),
    );

    expect(state.status, ProposalApplyStatus.applied);
    expect(state.appliedTable, 'accounts');

    final stored = await accountRepo.findById(state.appliedEntityId!);
    expect(stored, isNotNull);
    expect(stored!.name, 'Brokerage');
    expect(stored.currency, 'USD');

    await applier.undo(state);
    final deleted = await accountRepo.findById(state.appliedEntityId!);
    expect(deleted!.sync.deletedAt, isNotNull);
  });

  test('asset_valuation records a manual asset valuation adjustment', () async {
    final account = await accountRepo.create(
      type: AccountCategory.cash,
      name: 'Cash',
      currency: 'CNY',
    );
    final asset = await manualAssetRepo.createCash(
      accountId: account.id,
      currency: 'CNY',
      balance: Decimal.parse('100'),
      nickname: 'Wallet',
    );

    final state = await applier.apply(
      plan('asset_valuation', {'asset_id': asset.id, 'new_value': '250'}),
    );

    expect(state.status, ProposalApplyStatus.applied);
    expect(state.appliedTable, 'assets');
    expect(
      await manualAssetRepo.cashBalanceFromPostings(asset.id),
      Decimal.parse('250'),
    );
  });

  test(
    'liability_payment writes the principal payment journal entry',
    () async {
      final liability = await liabilityRepo.create(
        type: LiabilityType.mortgage,
        name: 'Mortgage',
        principal: Decimal.parse('120000'),
        interestRate: Decimal.parse('0.05'),
        currency: 'CNY',
        accountId: 'mortgage-liability',
      );

      final state = await applier.apply(
        plan('liability_payment', {
          'liability_id': liability.id,
          'from_account_id': 'checking',
          'amount': '1000',
          'currency': 'CNY',
          'date': '2026-03-04T00:00:00Z',
        }),
      );

      expect(state.status, ProposalApplyStatus.applied);
      expect(state.appliedTable, 'journal_entries');

      final stored = await journalEntryRepo.getById(state.appliedEntityId!);
      expect(stored, isNotNull);
      expect(
        stored!.postings.map((p) => p.accountId).toSet(),
        containsAll(<String>['checking', 'mortgage-liability']),
      );
    },
  );

  test('trade buy writes journal entry and price observation', () async {
    final state = await applier.apply(
      plan('trade', {
        'type': 'buy',
        'asset_id': 'asset-aapl',
        'asset_symbol': 'AAPL',
        'account_id': 'brokerage',
        'counter_account_id': 'cash',
        'quantity': '2',
        'price': '150',
        'currency': 'USD',
        'trade_date': '2026-04-05T00:00:00Z',
      }),
    );

    expect(state.status, ProposalApplyStatus.applied);
    expect(state.appliedTable, 'journal_entries');
    expect(await journalEntryRepo.getById(state.appliedEntityId!), isNotNull);

    final price = await priceRepo.latestAt(
      unit: 'asset-aapl',
      quoteCurrency: 'USD',
      asOf: DateTime.utc(2026, 4, 5),
    );
    expect(price!.perUnit, Decimal.parse('150'));
  });

  test('FIRE proposal branches delegate to injected writers', () async {
    final firePlanState = await applier.apply(
      plan('fire_plan_update', {
        'after': {'target_net_worth': '1000000', 'monthly_expenses': '20000'},
      }),
    );
    expect(firePlanState.appliedTable, 'fire_plans');
    expect(firePlanAfter, containsPair('target_net_worth', '1000000'));

    final bucketState = await applier.apply(
      plan('fire_bucket_rule', {
        'role': 'growth',
        'target_table': 'assets',
        'target_id': 'asset-growth',
        'allocation_pct': 0.6,
      }),
    );
    expect(bucketState.appliedTable, 'fire_bucket_rules');
    expect(bucketState.appliedEntityId, 'asset-growth');
    expect(fireBucketPayload, containsPair('role', 'growth'));
  });

  test('options_profile_update updates Income Planner profile', () async {
    await profileRepo.upsert(
      defaultProfileForMode(OptionsStrategyMode.balanced),
    );

    final state = await applier.apply(
      plan('options_profile_update', {
        'after': {
          'mode': 'aggressive',
          'min_dte': 14,
          'max_dte': 60,
          'min_annualized_yield': '0.18',
          'avoid_earnings': false,
          'only_on_approved_underlyings': false,
        },
      }),
    );

    expect(state.status, ProposalApplyStatus.applied);
    expect(state.appliedTable, 'options_strategy_profile');
    expect(state.appliedAt, isNull);

    final saved = await profileRepo.get('u-test');
    expect(saved!.mode, OptionsStrategyMode.aggressive);
    expect(saved.minDte, 14);
    expect(saved.maxDte, 60);
    expect(saved.minAnnualizedYield, Decimal.parse('0.18'));
    expect(saved.avoidEarnings, isFalse);
    expect(saved.onlyOnApprovedUnderlyings, isFalse);
  });

  test('options_journal_entry creates journal row and can undo it', () async {
    final state = await applier.apply(
      plan('options_journal_entry', {
        'strategy': 'cash_secured_put',
        'underlying': 'nvda',
        'option_symbol': 'NVDA260116P00100000',
        'opened_at_iso': '2026-01-02T00:00:00Z',
        'entry_credit': '1.25',
        'currency': 'USD',
        'status': 'open',
        'notes': 'AI proposed',
      }),
    );

    expect(state.status, ProposalApplyStatus.applied);
    expect(state.appliedTable, 'options_trade_journal');
    expect(state.appliedAt, isNotNull);

    final entry = await journalRepo.get(state.appliedEntityId!);
    expect(entry, isNotNull);
    expect(entry!.strategy, OptionsStrategyKind.cashSecuredPut);
    expect(entry.symbol, 'NVDA');
    expect(entry.entryCredit, Decimal.parse('1.25'));
    expect(entry.status, TradeJournalStatus.open);

    await applier.undo(state);
    expect(await journalRepo.get(state.appliedEntityId!), isNull);
  });
}

class _FakeTradeEntryService implements TradeEntryService {
  @override
  Future<TradeEntryPlan> buildPlan(
    TradeDraft draft, {
    required List<Lot> openLots,
  }) async => TradeEntryPlan(
    trade: PlannedTrade(
      id: draft.transactionId ?? 'trade-test',
      accountId: draft.accountId,
      assetId: draft.asset.id,
      type: draft.type,
      quantity: draft.quantity,
      price: draft.price ?? Decimal.one,
      currency: draft.currency,
      tradeDate: draft.tradeDate,
      fee: draft.fee,
      tax: draft.tax,
      counterAccountId: draft.counterAccountId,
      note: draft.note,
    ),
    pricing: PriceProvenance.userSupplied,
  );
}

class _OneFxRateSource implements FxRateSource {
  const _OneFxRateSource();

  @override
  Decimal? rate({
    required String from,
    required String to,
    required DateTime asOf,
  }) => Decimal.one;
}
