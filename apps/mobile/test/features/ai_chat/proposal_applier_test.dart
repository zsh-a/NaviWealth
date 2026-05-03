import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/data/db/app_database.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/invariants.dart';
import 'package:naviwealth/data/repositories/account_repository.dart';
import 'package:naviwealth/data/repositories/expense_category_repository.dart';
import 'package:naviwealth/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/data/repositories/manual_asset_repository.dart';
import 'package:naviwealth/features/ai_chat/data/proposal_applier.dart';
import 'package:naviwealth/features/ai_chat/domain/proposal_apply_state.dart';
import 'package:naviwealth/features/ai_chat/domain/proposal_plan.dart';
import 'package:naviwealth/features/investment/data/transaction_repository.dart';
import 'package:naviwealth/features/investment/domain/trade_entry/default_trade_entry_service.dart';
import 'package:naviwealth/features/liabilities/data/liability_repository.dart';

import '../../data/db/test_database.dart';
import '../../data/repositories/_stub_stamper.dart';
import '../investment/domain/trade_entry/_fakes.dart';

/// Wires every repository the applier needs against a single in-memory
/// AppDatabase. Tests then poke a [ReadyProposalPlan] in and assert that
/// the right side-effect landed in Drift + the outbox, without standing
/// up the chat layer.
class _Harness {
  _Harness({
    required this.db,
    required this.outbox,
    required this.applier,
    required this.transactionRepo,
    required this.accountRepo,
    required this.expenseCategoryRepo,
    required this.manualAssetRepo,
    required this.liabilityRepo,
    required this.journalEntryRepo,
  });

  final AppDatabase db;
  final InMemoryOutboxStore outbox;
  final ProposalApplier applier;
  final TransactionRepository transactionRepo;
  final AccountRepository accountRepo;
  final ExpenseCategoryRepository expenseCategoryRepo;
  final ManualAssetRepository manualAssetRepo;
  final LiabilityRepository liabilityRepo;
  final JournalEntryRepository journalEntryRepo;

  static Future<_Harness> create() async {
    final db = makeTestDatabase();
    final outbox = InMemoryOutboxStore();
    final stamper = makeStubStamper();

    final accountRepo = AccountRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
    );
    final transactionRepo = TransactionRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
    );
    final expenseCategoryRepo = ExpenseCategoryRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
    );
    final manualAssetRepo = ManualAssetRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
    );
    final liabilityRepo = LiabilityRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
    );
    final journalEntryRepo = JournalEntryRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
      // FIR-131 wave 3f — expense JEs land in CNY (matching the
      // legacy expense flow's default), so identity FX is enough.
      fxRateSource: const IdentityFxRateSource(),
      baseCurrency: 'CNY',
    );

    final tradeService = DefaultTradeEntryService(
      market: FakeMarketDataService(),
      fx: fxConverter(
        base: 'USD',
        quote: 'CNY',
        rate: '7',
        on: DateTime.utc(2026, 4, 30),
      ),
      stampHlc: CountingHlcStamper().call,
      ownerUserId: 'u-test',
      deviceId: 'dev-test',
    );

    final applier = ProposalApplier(
      transactionRepo: transactionRepo,
      tradeEntryService: tradeService,
      journalEntryRepo: journalEntryRepo,
      accountRepo: accountRepo,
      manualAssetRepo: manualAssetRepo,
      liabilityRepo: liabilityRepo,
      currentUserId: () async => 'u-test',
    );
    await expenseCategoryRepo.seedDefaults();
    return _Harness(
      db: db,
      outbox: outbox,
      applier: applier,
      transactionRepo: transactionRepo,
      accountRepo: accountRepo,
      expenseCategoryRepo: expenseCategoryRepo,
      manualAssetRepo: manualAssetRepo,
      liabilityRepo: liabilityRepo,
      journalEntryRepo: journalEntryRepo,
    );
  }
}

void main() {
  group('ProposalApplier.apply', () {
    late _Harness h;

    setUp(() async {
      h = await _Harness.create();
    });

    tearDown(() async => h.db.close());

    test('account_create persists an Account and undo soft-deletes it',
        () async {
      const plan = ReadyProposalPlan(
        proposalId: 'p',
        kind: ProposalKind.accountCreate,
        summaryZh: '创建账户「招行储蓄」',
        payload: <String, Object?>{
          'name': '招行储蓄',
          'type': 'bank',
          'currency': 'CNY',
        },
      );
      final state = await h.applier.apply(plan);
      expect(state.status, ProposalApplyStatus.applied);
      expect(state.appliedTable, 'accounts');
      final accounts = await h.accountRepo.listActive();
      expect(accounts.single.name, '招行储蓄');

      await h.applier.undo(state);
      final after = await h.accountRepo.listActive();
      expect(after, isEmpty, reason: 'undo should soft-delete the account');
    });

    test('expense persists a TransactionType.expense and undo tombstones it',
        () async {
      final account = await h.accountRepo.create(
        type: AccountType.cash,
        name: '现金',
        currency: 'CNY',
      );
      final plan = ReadyProposalPlan(
        proposalId: 'p',
        kind: ProposalKind.expense,
        summaryZh: '记一笔餐饮支出 35 CNY',
        payload: <String, Object?>{
          'amount': 35,
          'category': 'food',
          'currency': 'CNY',
          'account_id': account.id,
          'date': '2026-04-30T00:00:00Z',
          'note': '午饭',
        },
      );
      // FIR-131 wave 3f — expense proposals now write into the JE
      // ledger, not the legacy `transactions WHERE type='expense'`
      // projection. The applied state should point at
      // `journal_entries`, the JE itself should reflect the user's
      // narration + 2 postings (expense leg + cash leg), and undo
      // soft-deletes the whole entry.
      final state = await h.applier.apply(plan);
      expect(state.status, ProposalApplyStatus.applied);
      expect(state.appliedTable, 'journal_entries');

      final entries = await h.journalEntryRepo.watchAll().first;
      expect(entries, hasLength(1));
      final je = await h.journalEntryRepo.getById(entries.single.id);
      expect(je!.entry.narration, '午饭');
      expect(je.postings, hasLength(2));
      // Cash leg (asset account) carries -35; expense leg carries +35.
      final expenseLeg = je.postings.firstWhere(
        (p) => p.units == Decimal.parse('35'),
      );
      expect(expenseLeg.unit, 'CNY');
      // Slug "food" → FIR-133 `expense:food` account.
      expect(
        expenseLeg.accountId,
        AccountRepository.systemAccountIdForPath(
          'expense:food',
          ownerUserId: 'u-test',
        ),
      );
      final cashLeg = je.postings.firstWhere((p) => p.accountId == account.id);
      expect(cashLeg.units, Decimal.parse('-35'));

      // Undo tombstones the JE so the live stream stops surfacing it.
      await h.applier.undo(state);
      final remaining = await h.journalEntryRepo.watchAll().first;
      expect(remaining, isEmpty);
    });

    test('expense maps backend "housing" slug to FIR-133 housing account',
        () async {
      final account = await h.accountRepo.create(
        type: AccountType.cash,
        name: '现金',
        currency: 'CNY',
      );
      final plan = ReadyProposalPlan(
        proposalId: 'p',
        kind: ProposalKind.expense,
        summaryZh: '房租 4000 CNY',
        payload: <String, Object?>{
          'amount': 4000,
          'category': 'housing',
          'currency': 'CNY',
          'account_id': account.id,
        },
      );
      await h.applier.apply(plan);
      // Backend "housing" slug aliases to local "rent" → FIR-133
      // `expense:housing` account (the resolver inverts the alias).
      final entries = await h.journalEntryRepo.watchAll().first;
      final je = await h.journalEntryRepo.getById(entries.single.id);
      final expenseLeg = je!.postings.firstWhere(
        (p) => p.units == Decimal.parse('4000'),
      );
      expect(
        expenseLeg.accountId,
        AccountRepository.systemAccountIdForPath(
          'expense:housing',
          ownerUserId: 'u-test',
        ),
      );
    });

    test('asset_valuation updates last_price and undo restores previous',
        () async {
      final account = await h.accountRepo.create(
        type: AccountType.realEstate,
        name: '房产账户',
        currency: 'CNY',
      );
      final asset = await h.manualAssetRepo.createWealthProduct(
        accountId: account.id,
        name: '北京房产',
        currency: 'CNY',
        principal: Decimal.parse('1000000'),
        expectedAnnualReturn: Decimal.zero,
      );
      final plan = ReadyProposalPlan(
        proposalId: 'p',
        kind: ProposalKind.assetValuation,
        summaryZh: '更新「北京房产」估值为 1200000 CNY',
        payload: <String, Object?>{
          'asset_id': asset.id,
          'new_value': 1200000,
          'currency': 'CNY',
        },
      );
      final state = await h.applier.apply(plan);
      expect(state.status, ProposalApplyStatus.applied);
      expect(
        state.undoData?['previous_value'],
        '1000000',
        reason: 'previous value captured for undo',
      );
      final after = await h.manualAssetRepo.findById(asset.id);
      expect(after!.lastPrice, Decimal.parse('1200000'));

      await h.applier.undo(state);
      final restored = await h.manualAssetRepo.findById(asset.id);
      expect(restored!.lastPrice, Decimal.parse('1000000'));
    });

    test('liability_payment writes a JE with liability + cash postings',
        () async {
      final fromAccount = await h.accountRepo.create(
        type: AccountType.bank,
        name: '工资账户',
        currency: 'CNY',
      );
      final liabilityAccount = await h.accountRepo.create(
        type: AccountType.liability,
        name: '信用卡负债',
        currency: 'CNY',
        category: AccountCategory.liability,
      );
      final liability = await h.liabilityRepo.create(
        type: LiabilityType.creditCard,
        name: '信用卡',
        principal: Decimal.parse('5000'),
        interestRate: Decimal.parse('0.18'),
        currency: 'CNY',
        accountId: liabilityAccount.id,
      );
      final plan = ReadyProposalPlan(
        proposalId: 'p',
        kind: ProposalKind.liabilityPayment,
        summaryZh: '向「信用卡」还款 1000 CNY',
        payload: <String, Object?>{
          'liability_id': liability.id,
          'from_account_id': fromAccount.id,
          'amount': 1000,
          'currency': 'CNY',
        },
      );
      final state = await h.applier.apply(plan);
      expect(state.status, ProposalApplyStatus.applied);
      expect(state.appliedTable, 'journal_entries');

      final je = await h.journalEntryRepo.getById(state.appliedEntityId!);
      expect(je, isNotNull);
      expect(je!.postings, hasLength(2));
      // Liability leg (debit): reducing the debt.
      final liabilityLeg =
          je.postings.firstWhere((p) => p.accountId == liabilityAccount.id);
      expect(liabilityLeg.units, Decimal.parse('1000'));
      // Cash leg (credit): outflow from the payer account.
      final cashLeg =
          je.postings.firstWhere((p) => p.accountId == fromAccount.id);
      expect(cashLeg.units, Decimal.parse('-1000'));

      // Undo tombstones the JE.
      await h.applier.undo(state);
      final remaining = await h.journalEntryRepo.watchAll().first;
      expect(remaining, isEmpty);
    });

    test('apply throws ProposalApplyException on missing required field',
        () async {
      const plan = ReadyProposalPlan(
        proposalId: 'p',
        kind: ProposalKind.accountCreate,
        summaryZh: 'invalid',
        payload: <String, Object?>{
          'type': 'bank',
          // name missing
        },
      );
      expect(
        () => h.applier.apply(plan),
        throwsA(isA<ProposalApplyException>()),
      );
    });

    test('undo no-ops when state is not applied', () async {
      // Should not throw and should not touch any repo.
      await h.applier.undo(
        const ProposalApplyState(status: ProposalApplyStatus.cancelled),
      );
      expect(await h.accountRepo.listActive(), isEmpty);
    });
  });
}
