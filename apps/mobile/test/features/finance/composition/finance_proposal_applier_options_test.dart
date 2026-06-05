import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/composition/proposal_apply_state.dart';
import 'package:naviwealth/core/ai/composition/proposal_plan.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/features/finance/composition/finance_proposal_applier.dart';
import 'package:naviwealth/features/finance/data/domain/invariants.dart';
import 'package:naviwealth/features/finance/data/repositories/account_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/manual_asset_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/price_repository.dart';
import 'package:naviwealth/features/investment/domain/models/lot.dart';
import 'package:naviwealth/features/investment/domain/trade_entry/trade_draft.dart';
import 'package:naviwealth/features/investment/domain/trade_entry/trade_entry_plan.dart';
import 'package:naviwealth/features/investment/domain/trade_entry/trade_entry_service.dart';
import 'package:naviwealth/features/liabilities/data/liability_repository.dart';
import 'package:naviwealth/features/options_income/data/options_strategy_profile_repository.dart';
import 'package:naviwealth/features/options_income/data/trade_journal_repository.dart';
import 'package:naviwealth/features/options_income/domain/options_strategy_profile.dart';
import 'package:naviwealth/features/options_income/domain/trade_journal_entry.dart';

import '../../../core/persistence/test_database.dart';
import '../../../features/finance/data/repositories/_stub_stamper.dart';

void main() {
  late AppDatabase db;
  late InMemoryOutboxStore outbox;
  late OptionsStrategyProfileRepository profileRepo;
  late TradeJournalRepository journalRepo;
  late FinanceProposalApplier applier;

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
    final priceRepo = PriceRepository(db: db, outbox: outbox, stamper: stamper);
    final journalEntryRepo = JournalEntryRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
      fxRateSource: const IdentityFxRateSource(),
      baseCurrency: 'USD',
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
    applier = FinanceProposalApplier(
      tradeEntryService: _UnusedTradeEntryService(),
      journalEntryRepo: journalEntryRepo,
      priceRepo: priceRepo,
      accountRepo: AccountRepository(db: db, outbox: outbox, stamper: stamper),
      manualAssetRepo: ManualAssetRepository(
        db: db,
        outbox: outbox,
        stamper: stamper,
        priceRepo: priceRepo,
        journalEntryRepo: journalEntryRepo,
      ),
      liabilityRepo: LiabilityRepository(
        db: db,
        outbox: outbox,
        stamper: stamper,
        journalEntryRepo: journalEntryRepo,
      ),
      optionsProfileRepo: profileRepo,
      tradeJournalRepo: journalRepo,
      currentUserId: () async => 'u-test',
    );
  });

  tearDown(() async => db.close());

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

class _UnusedTradeEntryService implements TradeEntryService {
  @override
  Future<TradeEntryPlan> buildPlan(
    TradeDraft draft, {
    required List<Lot> openLots,
  }) {
    throw StateError('tradeEntryService should not be used by options tests');
  }
}
