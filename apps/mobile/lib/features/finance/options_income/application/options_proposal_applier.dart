import 'package:decimal/decimal.dart';
import 'package:naviwealth/core/ai/composition/proposal_applier.dart';
import 'package:naviwealth/core/ai/composition/proposal_apply_state.dart';
import 'package:naviwealth/core/ai/composition/proposal_plan.dart';
import 'package:naviwealth/features/finance/options_income/application/options_journal_ledger_service.dart';
import 'package:naviwealth/features/finance/options_income/data/leaps_call_position_repository.dart';
import 'package:naviwealth/features/finance/options_income/data/options_strategy_profile_repository.dart';
import 'package:naviwealth/features/finance/options_income/data/trade_journal_repository.dart';
import 'package:naviwealth/features/finance/options_income/domain/leaps_call_position.dart';
import 'package:naviwealth/features/finance/options_income/domain/options_strategy_profile.dart';
import 'package:naviwealth/features/finance/options_income/domain/trade_journal_entry.dart';

/// Options Income proposal writer owned by the Options Income slice.
///
/// The Finance composition applier routes confirmed proposal plans here, but
/// the actual Income Planner profile / trade-journal persistence remains in
/// the slice that owns those tables and domain contracts.
class OptionsProposalApplier {
  const OptionsProposalApplier({
    required this.profileRepo,
    required this.tradeJournalRepo,
    required this.leapsCallRepo,
    required this.currentUserId,
    this.ledgerService,
  });

  final OptionsStrategyProfileRepository profileRepo;
  final TradeJournalRepository tradeJournalRepo;
  final LeapsCallPositionRepository leapsCallRepo;
  final OptionsJournalLedgerService? ledgerService;
  final Future<String> Function() currentUserId;

  Future<ProposalApplyState> applyProfileUpdate(
    ReadyProposalPlan plan,
    DateTime at,
  ) async {
    final after = plan.payload['after'];
    if (after is! Map) {
      throw ProposalApplyException(
        'options_profile_update payload missing `after` field',
      );
    }
    final ownerUserId = await currentUserId();
    final current = await profileRepo.get(ownerUserId);
    if (current == null) {
      throw ProposalApplyException('Income Planner profile is not initialized');
    }
    final before = _profilePayload(current);
    final updated = _profileWithPayload(
      current,
      Map<String, Object?>.from(after),
    );
    final saved = await profileRepo.upsert(updated);
    return ProposalApplyState(
      status: ProposalApplyStatus.applied,
      appliedEntityId: saved.sync.ownerUserId,
      appliedTable: 'options_strategy_profile',
      appliedAt: at,
      undoData: <String, Object?>{'before': before},
      shortLabel: 'Updated ${plan.summaryZh}',
    );
  }

  Future<void> undoProfileUpdate(ProposalApplyState state) async {
    final before = state.undoData?['before'];
    if (before is! Map) {
      throw ProposalApplyException('Income Planner undo snapshot is missing');
    }
    final ownerUserId = await currentUserId();
    final current = await profileRepo.get(ownerUserId);
    if (current == null) {
      throw ProposalApplyException('Income Planner profile is not initialized');
    }
    await profileRepo.upsert(
      _profileWithPayload(current, Map<String, Object?>.from(before)),
    );
  }

  OptionsStrategyProfile _profileWithPayload(
    OptionsStrategyProfile current,
    Map<String, Object?> payload,
  ) {
    return current.copyWith(
      mode: _parseOptionsMode(payload['mode']) ?? current.mode,
      minDte: _optionalInt(payload['min_dte']) ?? current.minDte,
      maxDte: _optionalInt(payload['max_dte']) ?? current.maxDte,
      minAnnualizedYield:
          _optionalDecimalRaw(payload['min_annualized_yield']) ??
          current.minAnnualizedYield,
      minOpenInterest:
          _optionalInt(payload['min_open_interest']) ?? current.minOpenInterest,
      minVolume: _optionalInt(payload['min_volume']) ?? current.minVolume,
      maxCapitalPerTradePct:
          _optionalDecimalRaw(payload['max_capital_per_trade_pct']) ??
          current.maxCapitalPerTradePct,
      onlyOnApprovedUnderlyings: true,
    );
  }

  Map<String, Object?> _profilePayload(OptionsStrategyProfile profile) =>
      <String, Object?>{
        'mode': profile.mode.name,
        'min_dte': profile.minDte,
        'max_dte': profile.maxDte,
        'min_annualized_yield': profile.minAnnualizedYield.toString(),
        'min_open_interest': profile.minOpenInterest,
        'min_volume': profile.minVolume,
        'max_capital_per_trade_pct': profile.maxCapitalPerTradePct.toString(),
      };

  Future<ProposalApplyState> applyJournalEntry(
    ReadyProposalPlan plan,
    DateTime at,
  ) async {
    final strategy = parseOptionsStrategyKind(_requireString(plan, 'strategy'));
    if (strategy == null) {
      throw ProposalApplyException(
        'Unsupported options strategy: ${plan.get('strategy')}',
      );
    }
    final openedAt = _parseRequiredDate(plan, 'opened_at_iso');
    final entry = await tradeJournalRepo.create(
      strategy: strategy,
      symbol: _requireString(plan, 'underlying').toUpperCase(),
      optionSymbol: _requireString(plan, 'option_symbol'),
      openedAt: openedAt,
      expirationAt: _parseOptionalDate(plan, 'expiration_at_iso'),
      entryCredit: _requireDecimal(plan, 'entry_credit'),
      fees: _optionalDecimalRaw(plan.payload['fees']),
      currency: (plan.get('currency') ?? 'USD').toUpperCase(),
      status: parseTradeJournalStatus(plan.get('status') ?? 'open'),
      notes: plan.get('notes'),
      brokerageAccountId: plan.get('brokerage_account_id'),
      cashAccountId: plan.get('cash_account_id'),
      underlyingMarket: plan.get('underlying_market'),
      strikePrice: _optionalDecimal(plan, 'strike_price'),
      contractSize: _optionalInt(plan.payload['contract_size']),
      contractQuantity: _optionalInt(plan.payload['contract_quantity']) ?? 1,
    );
    await ledgerService?.mirror(entry);
    return ProposalApplyState(
      status: ProposalApplyStatus.applied,
      appliedEntityId: entry.id,
      appliedTable: 'options_trade_journal',
      appliedAt: at,
      shortLabel: 'Recorded ${plan.summaryZh}',
    );
  }

  Future<void> undoJournalEntry(String id) async {
    final entry = await tradeJournalRepo.get(id);
    if (entry == null) return;
    await ledgerService?.removeMirrors(entry.id);
    await tradeJournalRepo.remove(entry);
  }

  Future<ProposalApplyState> applyLeapsCallPosition(
    ReadyProposalPlan plan,
    DateTime at,
  ) async {
    final mark = _optionalDecimalRaw(plan.payload['current_mark']);
    final position = await leapsCallRepo.create(
      symbol: _requireString(plan, 'underlying'),
      optionSymbol: _requireString(plan, 'option_symbol'),
      openedAt: _parseRequiredDate(plan, 'opened_at_iso'),
      expirationAt: _parseRequiredDate(plan, 'expiration_at_iso'),
      strikePrice: _requireDecimal(plan, 'strike_price'),
      entryDebit: _requireDecimal(plan, 'entry_debit'),
      fees: _optionalDecimalRaw(plan.payload['fees']),
      currency: (plan.get('currency') ?? 'USD').toUpperCase(),
      contractQuantity: _optionalInt(plan.payload['contract_quantity']) ?? 1,
      contractSize: _optionalInt(plan.payload['contract_size']) ?? 100,
      status: parseLeapsCallStatus(plan.get('status') ?? 'open'),
      currentMark: mark,
      currentDelta: _optionalDecimalRaw(plan.payload['current_delta']),
      markedAt: mark == null
          ? null
          : _parseOptionalDate(plan, 'marked_at_iso') ?? at,
      notes: plan.get('notes'),
    );
    return ProposalApplyState(
      status: ProposalApplyStatus.applied,
      appliedEntityId: position.id,
      appliedTable: LeapsCallPositionRepository.tableName,
      appliedAt: at,
      shortLabel: 'Recorded ${plan.summaryZh}',
    );
  }

  Future<void> undoLeapsCallPosition(String id) async {
    final position = await leapsCallRepo.get(id);
    if (position != null) await leapsCallRepo.remove(position);
  }

  String _requireString(ReadyProposalPlan plan, String key) {
    final v = plan.get(key);
    if (v == null || v.isEmpty) {
      throw ProposalApplyException('Missing field $key');
    }
    return v;
  }

  Decimal _requireDecimal(ReadyProposalPlan plan, String key) {
    final raw = plan.payload[key];
    if (raw == null) {
      throw ProposalApplyException('Missing field $key');
    }
    final s = raw is String ? raw : raw.toString();
    final d = Decimal.tryParse(s);
    if (d == null) {
      throw ProposalApplyException('Field $key is not a valid number: $s');
    }
    return d;
  }

  Decimal? _optionalDecimal(ReadyProposalPlan plan, String key) {
    final raw = plan.payload[key];
    if (raw == null) return null;
    final s = raw is String ? raw : raw.toString();
    if (s.isEmpty) return null;
    final d = Decimal.tryParse(s);
    return d == Decimal.zero ? null : d;
  }

  Decimal? _optionalDecimalRaw(Object? raw) {
    if (raw == null) return null;
    final s = raw is String ? raw : raw.toString();
    if (s.isEmpty) return null;
    return Decimal.tryParse(s);
  }

  int? _optionalInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String && raw.isNotEmpty) return int.tryParse(raw);
    return null;
  }

  DateTime _parseRequiredDate(ReadyProposalPlan plan, String key) {
    final raw = _requireString(plan, key);
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      throw ProposalApplyException('Field $key is not a valid date: $raw');
    }
    return parsed.toUtc();
  }

  DateTime? _parseOptionalDate(ReadyProposalPlan plan, String key) {
    final raw = plan.get(key);
    if (raw == null || raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      throw ProposalApplyException('Field $key is not a valid date: $raw');
    }
    return parsed.toUtc();
  }

  OptionsStrategyMode? _parseOptionsMode(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    return switch (raw) {
      'conservative' => OptionsStrategyMode.conservative,
      'balanced' => OptionsStrategyMode.balanced,
      'aggressive' => OptionsStrategyMode.aggressive,
      'custom' => OptionsStrategyMode.custom,
      _ => throw ProposalApplyException(
        'Unsupported Income Planner mode: $raw',
      ),
    };
  }
}
