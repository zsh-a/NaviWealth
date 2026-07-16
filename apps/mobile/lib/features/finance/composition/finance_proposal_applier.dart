/// FinanceOS implementation of [ProposalApplier]
/// (`docs/architecture/lifeos-shell.md` §4, D-1.6b).
///
/// Dispatches a confirmed [ReadyProposalPlan] to the matching Finance
/// repository write, and reverses it again on undo. The chat UI in
/// `features/ai_chat/` only depends on the core `ProposalApplier`
/// interface — this concrete class is registered via
/// [financeProposalApplierProvider] in `bootstrap.dart`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/features/finance/application/finance_core_proposal_applier.dart';
import 'package:naviwealth/features/finance/application/finance_trade_proposal_applier.dart';
import 'package:naviwealth/features/finance/data/repositories/account_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/manual_asset_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/price_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/fire/application/fire_proposal_applier.dart';
import 'package:naviwealth/features/finance/investment/data/providers.dart';
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_entry_service.dart';
import 'package:naviwealth/features/finance/liabilities/data/liability_repository.dart';
import 'package:naviwealth/features/finance/liabilities/data/providers.dart';
import 'package:naviwealth/features/finance/options_income/application/options_proposal_applier.dart';
import 'package:naviwealth/features/finance/options_income/data/providers.dart';

import '../../../core/ai/composition/proposal_applier.dart';
import '../../../core/ai/composition/proposal_apply_state.dart';
import '../../../core/ai/composition/proposal_plan.dart';
import '../../../core/ai/write/drift_ai_touched_store.dart';
import '../../../core/ai/write/providers.dart';
import '../../../core/auth/current_user.dart';

export 'finance_proposal_kinds.dart' show kFinanceProposalAppliedKinds;

/// Drift table-name prefixes written by FinanceOS proposal appliers.
/// Used by the cross-domain composite to route undo explicitly.
const Set<String> kFinanceProposalAppliedTablePrefixes = {
  'journal_entries',
  'accounts',
  'assets',
  'fire_',
  'options_',
};

class FinanceProposalApplier implements ProposalApplier {
  FinanceProposalApplier({
    required TradeEntryService tradeEntryService,
    required this.journalEntryRepo,
    required PriceRepository priceRepo,
    required this.accountRepo,
    required this.manualAssetRepo,
    required LiabilityRepository liabilityRepo,
    required this.optionsApplier,
    required this.fireApplier,
    required this.currentUserId,
    this.aiTouchedStore,
  }) : coreApplier = FinanceCoreProposalApplier(
         journalEntryRepo: journalEntryRepo,
         accountRepo: accountRepo,
         manualAssetRepo: manualAssetRepo,
         liabilityRepo: liabilityRepo,
         currentUserId: currentUserId,
       ),
       tradeApplier = FinanceTradeProposalApplier(
         tradeEntryService: tradeEntryService,
         journalEntryRepo: journalEntryRepo,
         priceRepo: priceRepo,
         currentUserId: currentUserId,
       );

  final JournalEntryRepository journalEntryRepo;
  final AccountRepository accountRepo;
  final ManualAssetRepository manualAssetRepo;
  final FinanceCoreProposalApplier coreApplier;
  final FinanceTradeProposalApplier tradeApplier;
  final OptionsProposalApplier optionsApplier;
  final FireProposalApplier fireApplier;

  /// When present, every successful [apply] records an AI-
  /// touch entry keyed by `(entityType, entityId)`. Optional so
  /// existing tests (which inject the applier with hand-rolled stubs)
  /// don't need a Drift DB to compile. Production wiring in
  /// `features/ai_chat/data/providers.dart` always supplies it.
  final DriftAiTouchedStore? aiTouchedStore;

  /// Resolves the current single-user owner id, used to mint stable
  /// `system-account:<userId>:<path>` ids for the seeded
  /// expense / liability tree. Same shape as
  /// [MutationStamper.currentUserId] — production wiring delegates
  /// to that lookup so the applier never disagrees with the repo
  /// about the active user.
  final Future<String> Function() currentUserId;

  /// Run the compensating write encoded in [state]. No-op if [state] isn't
  /// in the `applied` status.
  @override
  Future<void> undo(ProposalApplyState state) async {
    if (state.status != ProposalApplyStatus.applied) return;
    final id = state.appliedEntityId;
    final table = state.appliedTable;
    if (id == null || table == null) return;
    switch (table) {
      case 'journal_entries':
        await journalEntryRepo.softDelete(id);
      case 'accounts':
        await accountRepo.softDelete(id);
      case 'assets':
        await manualAssetRepo.softDelete(id, reason: 'undo');
      case 'options_trade_journal':
        await optionsApplier.undoJournalEntry(id);
      default:
        throw ProposalApplyException('unknown undo table: $table');
    }
  }

  /// Persist [plan] via the appropriate repository. Returns a state stamped
  /// `applied` with the produced entity id. Throws [ProposalApplyException]
  /// (after wrapping the underlying error) if the write fails — the caller
  /// surfaces the message to the user instead of swallowing.
  @override
  Future<ProposalApplyState> apply(ReadyProposalPlan plan) async {
    try {
      final at = DateTime.now().toUtc();
      final state = switch (plan.kind) {
        'trade' => await tradeApplier.applyTrade(plan, at),
        'expense' => await coreApplier.applyExpense(plan, at),
        'income' => await coreApplier.applyIncome(plan, at),
        'liability_payment' => await coreApplier.applyLiabilityPayment(
          plan,
          at,
        ),
        'account_create' => await coreApplier.applyAccountCreate(plan, at),
        'asset_valuation' => await coreApplier.applyAssetValuation(plan, at),
        'fire_plan_update' => await fireApplier.applyPlanUpdate(plan, at),
        'options_profile_update' => await optionsApplier.applyProfileUpdate(
          plan,
        ),
        'options_journal_entry' => await optionsApplier.applyJournalEntry(
          plan,
          at,
        ),
        _ => throw ProposalApplyException(
          'unknown proposal kind: ${plan.kind}',
        ),
      };
      // When an apply succeeds, record the AI touch keyed by
      // (entityType, entityId). Detail pages surface a tiny sparkle
      // prefix for recent touches; the touch survives across restarts
      // because the table is persisted in Drift.
      await _recordTouch(plan, state, at);
      return state;
    } on ProposalApplyException {
      rethrow;
    } catch (e) {
      throw ProposalApplyException(e.toString());
    }
  }

  Future<void> _recordTouch(
    ReadyProposalPlan plan,
    ProposalApplyState state,
    DateTime at,
  ) async {
    final store = aiTouchedStore;
    if (store == null) return;
    if (state.status != ProposalApplyStatus.applied) return;
    final entityId = state.appliedEntityId;
    final entityType = state.appliedTable;
    if (entityId == null || entityType == null) return;
    try {
      await store.recordTouch(
        AiTouchedEntity(
          entityType: entityType,
          entityId: entityId,
          touchedAt: at,
          kindLabel: plan.kind,
        ),
      );
    } catch (_) {
      // Best-effort — failing to record the AI-touch metadata must
      // never break the apply path. The mark is decorative.
    }
  }
}

/// Finance-domain applier wiring. Resolves all repositories +
/// fire writers once and instantiates [FinanceProposalApplier]. Used by
/// `bootstrap.dart` to override `proposalApplierProvider`.
final financeProposalApplierProvider = FutureProvider<ProposalApplier>((
  ref,
) async {
  final tradeService = await ref.watch(tradeEntryServiceProvider.future);
  final journalEntryRepo = await ref.watch(
    journalEntryRepositoryProvider.future,
  );
  final priceRepo = await ref.watch(priceRepositoryProvider.future);
  final accountRepo = await ref.watch(accountRepositoryProvider.future);
  final manualAssetRepo = await ref.watch(manualAssetRepositoryProvider.future);
  final liabilityRepo = await ref.watch(liabilityRepositoryProvider.future);
  final optionsProfileRepo = await ref.watch(
    optionsStrategyProfileRepositoryProvider.future,
  );
  final tradeJournalRepo = await ref.watch(
    tradeJournalRepositoryProvider.future,
  );
  final optionsLedgerService = await ref.watch(
    optionsJournalLedgerServiceProvider.future,
  );
  final fireApplier = ref.watch(fireProposalApplierProvider);
  final currentUserId = ref.watch(currentUserIdProvider);
  final touched = ref.watch(aiTouchedStoreProvider);
  return FinanceProposalApplier(
    tradeEntryService: tradeService,
    journalEntryRepo: journalEntryRepo,
    priceRepo: priceRepo,
    accountRepo: accountRepo,
    manualAssetRepo: manualAssetRepo,
    liabilityRepo: liabilityRepo,
    optionsApplier: OptionsProposalApplier(
      profileRepo: optionsProfileRepo,
      tradeJournalRepo: tradeJournalRepo,
      ledgerService: optionsLedgerService,
      currentUserId: currentUserId,
    ),
    fireApplier: fireApplier,
    currentUserId: currentUserId,
    aiTouchedStore: touched,
  );
});
