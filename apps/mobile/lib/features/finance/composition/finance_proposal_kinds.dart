/// FinanceOS contributions to [proposalKindRegistryProvider]
/// (`docs/architecture/lifeos-shell.md` §4).
///
/// Every Finance `propose_*` tool registers its kind metadata here:
/// icon + label + editable fields shown in the inline edit sheet +
/// preview row builder for the expanded card. Adding a new Finance
/// proposal kind = add one entry to [kFinanceProposalKinds].
library;

import 'package:forui/forui.dart';

import '../../../core/ai/composition/proposal_kind_registry.dart';
import '../../../core/ai/composition/proposal_plan.dart';
import '../../../l10n/gen/app_localizations.dart';

/// Active Finance kinds. Bootstrap merges these into
/// [proposalKindRegistryProvider] alongside any other domains.
const List<ProposalKindMeta> kFinanceProposalKinds = [
  ProposalKindMeta(
    kind: 'trade',
    icon: FLucideIcons.trendingUp,
    label: _tradeLabel,
    toolName: 'propose_trade',
    editableFields: _tradeFields,
    previewRows: _tradeRows,
  ),
  ProposalKindMeta(
    kind: 'expense',
    icon: FLucideIcons.receipt,
    label: _expenseLabel,
    toolName: 'propose_expense',
    editableFields: _expenseFields,
    previewRows: _expenseRows,
  ),
  ProposalKindMeta(
    kind: 'liability_payment',
    icon: FLucideIcons.banknote,
    label: _liabilityPaymentLabel,
    toolName: 'propose_liability_payment',
    editableFields: _liabilityPaymentFields,
    previewRows: _liabilityPaymentRows,
  ),
  ProposalKindMeta(
    kind: 'account_create',
    icon: FLucideIcons.landmark,
    label: _accountCreateLabel,
    toolName: 'propose_account_create',
    editableFields: _accountCreateFields,
    previewRows: _accountCreateRows,
  ),
  ProposalKindMeta(
    kind: 'asset_valuation',
    icon: FLucideIcons.refreshCw,
    label: _assetValuationLabel,
    toolName: 'propose_asset_valuation',
    editableFields: _assetValuationFields,
    previewRows: _assetValuationRows,
  ),
  ProposalKindMeta(
    kind: 'fire_plan_update',
    icon: FLucideIcons.flag,
    label: _firePlanUpdateLabel,
    toolName: 'propose_fire_plan_update',
    // FIRE OS proposals don't expose payload fields for inline edit;
    // the diff is rendered via the existing `payload.before` /
    // `payload.after` shape and applied verbatim on confirm.
    previewRows: _firePlanUpdateRows,
  ),
  ProposalKindMeta(
    kind: 'options_profile_update',
    icon: FLucideIcons.slidersHorizontal,
    label: _optionsProfileUpdateLabel,
    toolName: 'propose_options_profile_update',
    previewRows: _optionsProfileUpdateRows,
  ),
  ProposalKindMeta(
    kind: 'options_journal_entry',
    icon: FLucideIcons.candlestickChart,
    label: _optionsJournalEntryLabel,
    toolName: 'propose_options_journal_entry',
    editableFields: _optionsJournalEntryFields,
    previewRows: _optionsJournalEntryRows,
  ),
];

/// Proposal kinds owned by FinanceOS. Derived from the same specs that
/// render proposal cards so UI registration and apply ownership cannot drift.
Set<String> get kFinanceProposalAppliedKinds =>
    kFinanceProposalKinds.map((m) => m.kind).toSet();

// ─── Labels ───

String _tradeLabel(AppLocalizations l) => l.aiChatProposalKindTrade;
String _expenseLabel(AppLocalizations l) => l.aiChatProposalKindExpense;
String _liabilityPaymentLabel(AppLocalizations l) =>
    l.aiChatProposalKindLiabilityPayment;
String _accountCreateLabel(AppLocalizations l) =>
    l.aiChatProposalKindAccountCreate;
String _assetValuationLabel(AppLocalizations l) =>
    l.aiChatProposalKindAssetValuation;
String _firePlanUpdateLabel(AppLocalizations l) =>
    l.aiChatProposalKindFirePlanUpdate;
String _optionsProfileUpdateLabel(AppLocalizations l) =>
    l.aiChatProposalKindOptionsProfileUpdate;
String _optionsJournalEntryLabel(AppLocalizations l) =>
    l.aiChatProposalKindOptionsJournalEntry;

// ─── Editable fields ───

List<ProposalKindEditField> _tradeFields(AppLocalizations l) => [
  ProposalKindEditField(
    payloadKey: 'quantity',
    label: l.aiChatFieldQuantity,
    numeric: true,
  ),
  ProposalKindEditField(
    payloadKey: 'price',
    label: l.aiChatFieldPrice,
    numeric: true,
  ),
  ProposalKindEditField(
    payloadKey: 'fee',
    label: l.aiChatFieldFee,
    numeric: true,
  ),
  ProposalKindEditField(
    payloadKey: 'tax',
    label: l.aiChatFieldTax,
    numeric: true,
  ),
  ProposalKindEditField(payloadKey: 'note', label: l.aiChatFieldNote),
];

List<ProposalKindEditField> _expenseFields(AppLocalizations l) => [
  ProposalKindEditField(
    payloadKey: 'amount',
    label: l.aiChatFieldAmount,
    numeric: true,
  ),
  ProposalKindEditField(
    payloadKey: 'date',
    label: l.aiChatFieldDate,
    hint: l.aiChatFieldDateHint,
  ),
  ProposalKindEditField(payloadKey: 'note', label: l.aiChatFieldNote),
];

List<ProposalKindEditField> _liabilityPaymentFields(AppLocalizations l) => [
  ProposalKindEditField(
    payloadKey: 'amount',
    label: l.aiChatFieldAmount,
    numeric: true,
  ),
  ProposalKindEditField(
    payloadKey: 'date',
    label: l.aiChatFieldDate,
    hint: l.aiChatFieldDateHint,
  ),
  ProposalKindEditField(payloadKey: 'note', label: l.aiChatFieldNote),
];

List<ProposalKindEditField> _accountCreateFields(AppLocalizations l) => [
  ProposalKindEditField(payloadKey: 'name', label: l.aiChatFieldAccountName),
  ProposalKindEditField(
    payloadKey: 'institution',
    label: l.aiChatFieldInstitution,
  ),
  ProposalKindEditField(payloadKey: 'note', label: l.aiChatFieldNote),
];

List<ProposalKindEditField> _assetValuationFields(AppLocalizations l) => [
  ProposalKindEditField(
    payloadKey: 'new_value',
    label: l.aiChatFieldNewValuation,
    numeric: true,
  ),
  ProposalKindEditField(
    payloadKey: 'date',
    label: l.aiChatFieldDate,
    hint: l.aiChatFieldDateHint,
  ),
  ProposalKindEditField(payloadKey: 'note', label: l.aiChatFieldNote),
];

List<ProposalKindEditField> _optionsJournalEntryFields(AppLocalizations l) => [
  ProposalKindEditField(
    payloadKey: 'entry_credit',
    label: l.aiChatFieldOptionPremium,
    numeric: true,
  ),
  ProposalKindEditField(
    payloadKey: 'opened_at_iso',
    label: l.aiChatFieldDate,
    hint: l.aiChatFieldDateHint,
  ),
  ProposalKindEditField(payloadKey: 'notes', label: l.aiChatFieldNotes),
];

// ─── Preview rows ───

String? _read(
  ReadyProposalPlan plan,
  Map<String, Object?>? overrides,
  String key,
) {
  final ov = overrides?[key];
  if (ov is String && ov.isNotEmpty) return ov;
  final v = plan.payload[key];
  if (v == null) return null;
  final s = v is String ? v : v.toString();
  return s.isEmpty ? null : s;
}

String _tradeTypeLabel(AppLocalizations l10n, String wire) => switch (wire) {
  'buy' => l10n.tradeTypeBuy,
  'sell' => l10n.tradeTypeSell,
  'transferIn' => l10n.tradeTypeTransferIn,
  'transferOut' => l10n.tradeTypeTransferOut,
  'valuationAdjust' => l10n.tradeTypeValuationAdjust,
  _ => wire,
};

List<ProposalKindRow> _tradeRows(
  AppLocalizations l10n,
  ReadyProposalPlan plan,
  Map<String, Object?>? overrides,
) {
  String? r(String k) => _read(plan, overrides, k);
  return [
    if (r('type') != null)
      ProposalKindRow(
        l10n.aiChatRowOperation,
        _tradeTypeLabel(l10n, r('type')!),
      ),
    if (r('asset_symbol') != null || r('asset_name') != null)
      ProposalKindRow(
        l10n.aiChatRowAsset,
        r('asset_name') != null && r('asset_symbol') != null
            ? '${r('asset_name')} (${r('asset_symbol')})'
            : (r('asset_name') ?? r('asset_symbol')!),
      ),
    if (r('account_name') != null)
      ProposalKindRow(l10n.aiChatRowAccount, r('account_name')!),
    if (r('quantity') != null)
      ProposalKindRow(l10n.aiChatRowQuantity, r('quantity')!),
    if (r('price') != null)
      ProposalKindRow(
        l10n.aiChatRowPrice,
        '${r('price')} ${r('currency') ?? ''}'.trim(),
      ),
    if (r('fee') != null && r('fee') != '0' && r('fee') != '0.0')
      ProposalKindRow(l10n.aiChatRowFee, r('fee')!),
    if (r('trade_date') != null)
      ProposalKindRow(l10n.aiChatRowDate, r('trade_date')!),
    if (r('note') != null) ProposalKindRow(l10n.aiChatRowNote, r('note')!),
  ];
}

List<ProposalKindRow> _expenseRows(
  AppLocalizations l10n,
  ReadyProposalPlan plan,
  Map<String, Object?>? overrides,
) {
  String? r(String k) => _read(plan, overrides, k);
  return [
    if (r('amount') != null)
      ProposalKindRow(
        l10n.aiChatRowAmount,
        '${r('amount')} ${r('currency') ?? ''}'.trim(),
      ),
    if (r('category') != null)
      ProposalKindRow(l10n.aiChatRowCategory, r('category')!),
    if (r('account_name') != null)
      ProposalKindRow(l10n.aiChatRowAccount, r('account_name')!),
    if (r('date') != null) ProposalKindRow(l10n.aiChatRowDate, r('date')!),
    if (r('note') != null) ProposalKindRow(l10n.aiChatRowNote, r('note')!),
  ];
}

List<ProposalKindRow> _liabilityPaymentRows(
  AppLocalizations l10n,
  ReadyProposalPlan plan,
  Map<String, Object?>? overrides,
) {
  String? r(String k) => _read(plan, overrides, k);
  return [
    if (r('liability_name') != null)
      ProposalKindRow(l10n.aiChatRowLiability, r('liability_name')!),
    if (r('amount') != null)
      ProposalKindRow(
        l10n.aiChatRowAmount,
        '${r('amount')} ${r('currency') ?? ''}'.trim(),
      ),
    if (r('from_account_name') != null)
      ProposalKindRow(l10n.aiChatRowRepayAccount, r('from_account_name')!),
    if (r('date') != null) ProposalKindRow(l10n.aiChatRowDate, r('date')!),
    if (r('note') != null) ProposalKindRow(l10n.aiChatRowNote, r('note')!),
  ];
}

List<ProposalKindRow> _accountCreateRows(
  AppLocalizations l10n,
  ReadyProposalPlan plan,
  Map<String, Object?>? overrides,
) {
  String? r(String k) => _read(plan, overrides, k);
  return [
    if (r('name') != null) ProposalKindRow(l10n.aiChatRowName, r('name')!),
    if (r('type') != null) ProposalKindRow(l10n.aiChatRowType, r('type')!),
    if (r('currency') != null)
      ProposalKindRow(l10n.aiChatRowCurrency, r('currency')!),
    if (r('institution') != null)
      ProposalKindRow(l10n.aiChatRowInstitution, r('institution')!),
    if (r('note') != null) ProposalKindRow(l10n.aiChatRowNote, r('note')!),
  ];
}

List<ProposalKindRow> _assetValuationRows(
  AppLocalizations l10n,
  ReadyProposalPlan plan,
  Map<String, Object?>? overrides,
) {
  String? r(String k) => _read(plan, overrides, k);
  return [
    if (r('asset_name') != null)
      ProposalKindRow(l10n.aiChatRowAsset, r('asset_name')!),
    if (r('new_value') != null)
      ProposalKindRow(
        l10n.aiChatRowNewValue,
        '${r('new_value')} ${r('currency') ?? ''}'.trim(),
      ),
    if (r('date') != null) ProposalKindRow(l10n.aiChatRowDate, r('date')!),
    if (r('note') != null) ProposalKindRow(l10n.aiChatRowNote, r('note')!),
  ];
}

// The applier reads `payload.after`; surface it as a single row so the
// confirm card still shows what's about to change.
List<ProposalKindRow> _firePlanUpdateRows(
  AppLocalizations l10n,
  ReadyProposalPlan plan,
  Map<String, Object?>? overrides,
) {
  return [ProposalKindRow(l10n.aiChatRowNote, plan.summaryZh)];
}

List<ProposalKindRow> _optionsProfileUpdateRows(
  AppLocalizations l10n,
  ReadyProposalPlan plan,
  Map<String, Object?>? overrides,
) {
  final after = plan.payload['after'];
  if (after is! Map) {
    return [ProposalKindRow(l10n.aiChatRowNote, plan.summaryZh)];
  }
  return after.entries
      .map(
        (entry) =>
            ProposalKindRow(entry.key.toString(), entry.value.toString()),
      )
      .toList(growable: false);
}

List<ProposalKindRow> _optionsJournalEntryRows(
  AppLocalizations l10n,
  ReadyProposalPlan plan,
  Map<String, Object?>? overrides,
) {
  String? r(String k) => _read(plan, overrides, k);
  return [
    if (r('strategy') != null)
      ProposalKindRow(
        l10n.incomePlannerProfileAllowedStrategies,
        r('strategy')!,
      ),
    if (r('underlying') != null)
      ProposalKindRow(l10n.aiChatRowUnderlying, r('underlying')!),
    if (r('option_symbol') != null)
      ProposalKindRow(l10n.aiChatRowOptionContract, r('option_symbol')!),
    if (r('entry_credit') != null)
      ProposalKindRow(
        l10n.aiChatFieldOptionPremium,
        '${r('entry_credit')} ${r('currency') ?? ''}'.trim(),
      ),
    if (r('status') != null)
      ProposalKindRow(l10n.liabilityScheduleColStatus, r('status')!),
    if (r('opened_at_iso') != null)
      ProposalKindRow(l10n.aiChatRowDate, r('opened_at_iso')!),
    if (r('notes') != null) ProposalKindRow(l10n.aiChatRowNote, r('notes')!),
  ];
}
