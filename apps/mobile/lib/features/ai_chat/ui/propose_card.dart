import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/haptics/haptics.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/proposal_applier.dart';
import '../data/providers.dart';
import '../domain/chat_models.dart';
import '../domain/proposal_apply_state.dart';
import '../domain/proposal_plan.dart';

String proposalKindLabel(AppLocalizations l10n, ProposalKind kind) =>
    switch (kind) {
      ProposalKind.trade => l10n.aiChatProposalKindTrade,
      ProposalKind.expense => l10n.aiChatProposalKindExpense,
      ProposalKind.liabilityPayment => l10n.aiChatProposalKindLiabilityPayment,
      ProposalKind.accountCreate => l10n.aiChatProposalKindAccountCreate,
      ProposalKind.assetValuation => l10n.aiChatProposalKindAssetValuation,
      ProposalKind.unknown => l10n.aiChatProposalKindUnknown,
    };

/// FIR-67 — confirmation card rendered for `propose_*` tool calls.
///
/// Single source of truth for the lifecycle: pending → applying → applied
/// → undone (or cancelled / errored). The persisted state lives on the
/// underlying `ToolInvocation.applyState`, so a chat reload reproduces
/// whatever decision the user made on this turn.
class ProposeCard extends ConsumerStatefulWidget {
  const ProposeCard({
    super.key,
    required this.sessionId,
    required this.message,
    required this.invocation,
    required this.plan,
  });

  final String sessionId;
  final ChatMessage message;
  final ToolInvocation invocation;
  final ProposalPlan plan;

  @override
  ConsumerState<ProposeCard> createState() => _ProposeCardState();
}

class _ProposeCardState extends ConsumerState<ProposeCard> {
  Timer? _undoTicker;
  // Override values applied via the inline edit sheet, layered on top of
  // the original plan when the user finally confirms.
  Map<String, Object?>? _overrides;

  ProposalApplyState get _applyState =>
      widget.invocation.applyState ?? ProposalApplyState.pending;

  @override
  void initState() {
    super.initState();
    _maybeStartUndoTicker();
  }

  @override
  void didUpdateWidget(ProposeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeStartUndoTicker();
  }

  void _maybeStartUndoTicker() {
    final state = _applyState;
    if (state.status == ProposalApplyStatus.applied) {
      _undoTicker?.cancel();
      _undoTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        // Trigger a rebuild so the undo button disappears once the 60s
        // window elapses — the UI condition reads `appliedAt` against
        // wall clock, no extra state required.
        setState(() {});
      });
    } else {
      _undoTicker?.cancel();
      _undoTicker = null;
    }
  }

  @override
  void dispose() {
    _undoTicker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    if (plan is ClarificationProposalPlan) {
      return _ClarificationView(plan: plan);
    }
    if (plan is! ReadyProposalPlan) {
      return const SizedBox.shrink();
    }
    final state = _applyState;
    switch (state.status) {
      case ProposalApplyStatus.applied:
      case ProposalApplyStatus.undone:
      case ProposalApplyStatus.cancelled:
        return _CollapsedView(
          plan: plan,
          applyState: state,
          onUndo: state.status == ProposalApplyStatus.applied &&
                  state.isUndoableAt(DateTime.now())
              ? _onUndo
              : null,
        );
      case ProposalApplyStatus.pending:
      case ProposalApplyStatus.errored:
      case ProposalApplyStatus.applying:
        return _ExpandedView(
          plan: plan,
          applyState: state,
          overrides: _overrides,
          onConfirm: _onConfirm,
          onCancel: _onCancel,
          onEdit: () => _onEdit(plan),
        );
    }
  }

  Future<void> _persist(ProposalApplyState newState) async {
    final repo = await ref.read(chatRepositoryProvider.future);
    await repo.updateToolApplyState(
      sessionId: widget.sessionId,
      messageId: widget.message.id,
      toolInvocationId: widget.invocation.id,
      newState: newState,
    );
  }

  Future<void> _onConfirm() async {
    final plan = widget.plan;
    if (plan is! ReadyProposalPlan) return;
    Haptics.primaryPress();
    final effective = _overrides == null
        ? plan
        : ReadyProposalPlan(
            proposalId: plan.proposalId,
            kind: plan.kind,
            summaryZh: plan.summaryZh,
            payload: <String, Object?>{...plan.payload, ..._overrides!},
            warnings: plan.warnings,
            missing: plan.missing,
          );

    await _persist(_applyState.copyWith(status: ProposalApplyStatus.applying));
    try {
      final applier = await ref.read(proposalApplierProvider.future);
      final result = await applier.apply(effective);
      if (!mounted) return;
      await _persist(result);
      _maybeStartUndoTicker();
    } on ProposalApplyException catch (e) {
      Haptics.error();
      await _persist(
        _applyState.copyWith(
          status: ProposalApplyStatus.errored,
          errorMessage: e.message,
        ),
      );
    } catch (e) {
      Haptics.error();
      await _persist(
        _applyState.copyWith(
          status: ProposalApplyStatus.errored,
          errorMessage: e.toString(),
        ),
      );
    }
  }

  Future<void> _onCancel() async {
    await _persist(
      _applyState.copyWith(status: ProposalApplyStatus.cancelled),
    );
  }

  Future<void> _onUndo() async {
    final l10n = AppLocalizations.of(context);
    final state = _applyState;
    if (state.status != ProposalApplyStatus.applied) return;
    try {
      final applier = await ref.read(proposalApplierProvider.future);
      await applier.undo(state);
      if (!mounted) return;
      await _persist(state.copyWith(status: ProposalApplyStatus.undone));
    } on ProposalApplyException catch (e) {
      await _persist(
        state.copyWith(
          status: ProposalApplyStatus.errored,
          errorMessage: l10n.aiChatProposalUndoFailure(e.message),
        ),
      );
    } catch (e) {
      await _persist(
        state.copyWith(
          status: ProposalApplyStatus.errored,
          errorMessage: l10n.aiChatProposalUndoFailure(e.toString()),
        ),
      );
    }
  }

  Future<void> _onEdit(ReadyProposalPlan plan) async {
    final result = await showGlassModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => ProposalEditSheet(
        plan: plan,
        initial: _overrides,
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _overrides = result);
  }
}

class _ExpandedView extends StatelessWidget {
  const _ExpandedView({
    required this.plan,
    required this.applyState,
    required this.overrides,
    required this.onConfirm,
    required this.onCancel,
    required this.onEdit,
  });

  final ReadyProposalPlan plan;
  final ProposalApplyState applyState;
  final Map<String, Object?>? overrides;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);
    final isApplying = applyState.status == ProposalApplyStatus.applying;
    final isErrored = applyState.status == ProposalApplyStatus.errored;
    final summary = overrides == null
        ? plan.summaryZh
        : l10n.aiChatProposalSummaryEdited(plan.summaryZh);

    return Container(
      margin: const EdgeInsets.only(top: Spacing.s8),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer.withValues(alpha: 0.35),
        borderRadius: Radii.brMd,
        border: Border.all(
          color: cs.tertiary.withValues(alpha: 0.45),
        ),
        boxShadow: AppElevations.of(context).level1,
      ),
      padding: const EdgeInsets.all(Spacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_iconFor(plan.kind), size: 18, color: cs.onTertiaryContainer),
              const SizedBox(width: Spacing.s8),
              Text(
                l10n.aiChatProposalPendingHeader(
                  proposalKindLabel(l10n, plan.kind),
                ),
                style: tt.labelMedium?.copyWith(color: cs.onTertiaryContainer),
              ),
            ],
          ),
          const SizedBox(height: Spacing.s6),
          Text(
            summary,
            style: tt.bodyLarge?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: Spacing.s8),
          ProposalPayloadDetails(plan: plan, overrides: overrides),
          if (plan.warnings.isNotEmpty) ...[
            const SizedBox(height: Spacing.s8),
            for (final w in plan.warnings)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 14,
                      color: cs.tertiary,
                    ),
                    const SizedBox(width: Spacing.s4),
                    Expanded(
                      child: Text(
                        w,
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (isErrored && applyState.errorMessage != null) ...[
            const SizedBox(height: Spacing.s8),
            Text(
              l10n.aiChatProposalFailure(applyState.errorMessage!),
              style: tt.bodySmall?.copyWith(color: cs.error),
            ),
          ],
          const SizedBox(height: Spacing.s12),
          Wrap(
            spacing: Spacing.s8,
            runSpacing: Spacing.s4,
            children: [
              AppButton.primary(
                onPressed: isApplying ? null : onConfirm,
                icon: Icons.check,
                label: isApplying
                    ? l10n.aiChatProposalApplying
                    : l10n.aiChatProposalConfirm,
              ),
              AppButton.secondary(
                onPressed: isApplying ? null : onCancel,
                icon: Icons.close,
                label: l10n.commonCancel,
              ),
              AppButton.tertiary(
                onPressed: isApplying ? null : onEdit,
                icon: Icons.edit_outlined,
                label: l10n.aiChatProposalEdit,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CollapsedView extends StatelessWidget {
  const _CollapsedView({
    required this.plan,
    required this.applyState,
    required this.onUndo,
  });

  final ReadyProposalPlan plan;
  final ProposalApplyState applyState;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);
    final IconData icon;
    final Color color;
    final String label;
    switch (applyState.status) {
      case ProposalApplyStatus.applied:
        icon = Icons.check_circle;
        color = cs.primary;
        label = applyState.shortLabel ??
            l10n.aiChatProposalAppliedFallback(plan.summaryZh);
      case ProposalApplyStatus.undone:
        icon = Icons.undo;
        color = cs.onSurfaceVariant;
        label = l10n.aiChatProposalUndoneLabel(plan.summaryZh);
      case ProposalApplyStatus.cancelled:
        icon = Icons.cancel_outlined;
        color = cs.onSurfaceVariant;
        label = l10n.aiChatProposalCancelledLabel(plan.summaryZh);
      default:
        return const SizedBox.shrink();
    }
    final secondsLeft = onUndo != null && applyState.appliedAt != null
        ? 60 - DateTime.now().difference(applyState.appliedAt!).inSeconds
        : 0;

    return Padding(
      padding: const EdgeInsets.only(top: Spacing.s8),
      child: LiquidGlassCard(
        layer: GlassLayer.tertiary,
        borderRadius: Radii.md,
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.s12,
          vertical: Spacing.s8,
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: Spacing.s8),
            Expanded(
              child: Text(
                label,
                style: tt.bodyMedium?.copyWith(color: cs.onSurface),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onUndo != null && secondsLeft > 0)
              AppButton.tertiary(
                onPressed: onUndo,
                icon: Icons.undo,
                label: l10n.aiChatProposalUndoCountdown(secondsLeft),
              ),
          ],
        ),
      ),
    );
  }
}

class _ClarificationView extends StatelessWidget {
  const _ClarificationView({required this.plan});

  final ClarificationProposalPlan plan;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.s8),
      child: LiquidGlassCard(
        layer: GlassLayer.tertiary,
        borderRadius: Radii.md,
        padding: const EdgeInsets.all(Spacing.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.help_outline, size: 18, color: cs.tertiary),
                const SizedBox(width: Spacing.s8),
                Text(
                  l10n.aiChatProposalNeedsClarificationHeader(
                    proposalKindLabel(l10n, plan.kind),
                  ),
                  style: tt.labelMedium?.copyWith(color: cs.onSurface),
                ),
              ],
            ),
            const SizedBox(height: Spacing.s6),
            Text(
              plan.reason,
              style: tt.bodyMedium?.copyWith(color: cs.onSurface),
            ),
            if (plan.candidates.isNotEmpty) ...[
              const SizedBox(height: Spacing.s8),
              Text(
                l10n.aiChatProposalCandidatesHeading,
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: Spacing.s4),
              Wrap(
                spacing: Spacing.s8,
                runSpacing: Spacing.s4,
                children: [
                  for (final c in plan.candidates)
                    Chip(
                      label: Text(c.label ?? c.id),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Per-field detail rows shown in the expanded card. Surfaces the bits of
/// the payload the user is most likely to want to verify (operation,
/// asset/account, amount, date, note) — anything the model included that
/// doesn't fit those slots stays inside the raw plan, accessible via the
/// edit sheet's "完整编辑" follow-up.
class ProposalPayloadDetails extends StatelessWidget {
  const ProposalPayloadDetails({
    super.key,
    required this.plan,
    this.overrides,
  });

  final ReadyProposalPlan plan;
  final Map<String, Object?>? overrides;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);
    final rows = _rowsFor(l10n, plan, overrides);
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.s8,
        vertical: Spacing.s6,
      ),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.6),
        borderRadius: Radii.brXs,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 64,
                    child: Text(
                      r.label,
                      style: tt.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: Spacing.s8),
                  Expanded(
                    child: Text(
                      r.value,
                      style: tt.bodySmall?.copyWith(color: cs.onSurface),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Inline edit sheet: lets the user override the high-frequency fields
/// (amount / price / note / date) before they confirm. Anything beyond
/// these flows back to the full FIR-44 / FIR-63 / FIR-64 entry pages —
/// surfaced as a TextButton at the bottom of the sheet.
class ProposalEditSheet extends StatefulWidget {
  const ProposalEditSheet({
    super.key,
    required this.plan,
    this.initial,
  });

  final ReadyProposalPlan plan;
  final Map<String, Object?>? initial;

  @override
  State<ProposalEditSheet> createState() => _ProposalEditSheetState();
}

class _ProposalEditSheetState extends State<ProposalEditSheet> {
  late final Map<String, TextEditingController> _controllers;
  late List<_EditableField> _fields;

  @override
  void initState() {
    super.initState();
    _fields = const <_EditableField>[];
    _controllers = {};
  }

  void _ensureFieldsInitialized(AppLocalizations l10n) {
    if (_fields.isNotEmpty) return;
    _fields = _editableFieldsFor(l10n, widget.plan.kind);
    for (final f in _fields) {
      _controllers[f.payloadKey] = TextEditingController(
        text: _initialFor(f.payloadKey),
      );
    }
  }

  String _initialFor(String key) {
    final overridden = widget.initial?[key];
    if (overridden != null) return overridden.toString();
    final raw = widget.plan.payload[key];
    return raw == null ? '' : raw.toString();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, Object?> _collect() {
    final out = <String, Object?>{};
    for (final f in _fields) {
      final text = _controllers[f.payloadKey]!.text.trim();
      if (text.isEmpty) {
        // Setting empty string preserves the field's current value rather
        // than nuking it — applier reads payload via plan.get() which
        // already treats empty as absent.
        continue;
      }
      out[f.payloadKey] = text;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    _ensureFieldsInitialized(l10n);
    final padding = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: Spacing.s16,
          right: Spacing.s16,
          top: Spacing.s12,
          bottom: padding + Spacing.s16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  l10n.aiChatProposalEditKindTitle(
                    proposalKindLabel(l10n, widget.plan.kind),
                  ),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: Spacing.s8),
            for (final f in _fields) ...[
              TextField(
                controller: _controllers[f.payloadKey],
                keyboardType: f.numeric
                    ? const TextInputType.numberWithOptions(decimal: true)
                    : TextInputType.text,
                decoration: InputDecoration(
                  labelText: f.label,
                  hintText: f.hint,
                ),
              ),
              const SizedBox(height: Spacing.s12),
            ],
            AppButton.primary(
              onPressed: () => Navigator.of(context).pop(_collect()),
              label: l10n.aiChatProposalSaveEdits,
            ),
          ],
        ),
      ),
    );
  }
}

class _EditableField {
  const _EditableField({
    required this.payloadKey,
    required this.label,
    this.hint,
    this.numeric = false,
  });
  final String payloadKey;
  final String label;
  final String? hint;
  final bool numeric;
}

List<_EditableField> _editableFieldsFor(
  AppLocalizations l10n,
  ProposalKind kind,
) {
  switch (kind) {
    case ProposalKind.trade:
      return [
        _EditableField(
          payloadKey: 'quantity',
          label: l10n.aiChatFieldQuantity,
          numeric: true,
        ),
        _EditableField(
          payloadKey: 'price',
          label: l10n.aiChatFieldPrice,
          numeric: true,
        ),
        _EditableField(
          payloadKey: 'fee',
          label: l10n.aiChatFieldFee,
          numeric: true,
        ),
        _EditableField(
          payloadKey: 'tax',
          label: l10n.aiChatFieldTax,
          numeric: true,
        ),
        _EditableField(payloadKey: 'note', label: l10n.aiChatFieldNote),
      ];
    case ProposalKind.expense:
      return [
        _EditableField(
          payloadKey: 'amount',
          label: l10n.aiChatFieldAmount,
          numeric: true,
        ),
        _EditableField(
          payloadKey: 'date',
          label: l10n.aiChatFieldDate,
          hint: l10n.aiChatFieldDateHint,
        ),
        _EditableField(payloadKey: 'note', label: l10n.aiChatFieldNote),
      ];
    case ProposalKind.liabilityPayment:
      return [
        _EditableField(
          payloadKey: 'amount',
          label: l10n.aiChatFieldAmount,
          numeric: true,
        ),
        _EditableField(
          payloadKey: 'date',
          label: l10n.aiChatFieldDate,
          hint: l10n.aiChatFieldDateHint,
        ),
        _EditableField(payloadKey: 'note', label: l10n.aiChatFieldNote),
      ];
    case ProposalKind.accountCreate:
      return [
        _EditableField(payloadKey: 'name', label: l10n.aiChatFieldAccountName),
        _EditableField(
          payloadKey: 'institution',
          label: l10n.aiChatFieldInstitution,
        ),
        _EditableField(payloadKey: 'note', label: l10n.aiChatFieldNote),
      ];
    case ProposalKind.assetValuation:
      return [
        _EditableField(
          payloadKey: 'new_value',
          label: l10n.aiChatFieldNewValuation,
          numeric: true,
        ),
        _EditableField(
          payloadKey: 'date',
          label: l10n.aiChatFieldDate,
          hint: l10n.aiChatFieldDateHint,
        ),
        _EditableField(payloadKey: 'note', label: l10n.aiChatFieldNote),
      ];
    case ProposalKind.unknown:
      return const [];
  }
}

class _Row {
  const _Row(this.label, this.value);
  final String label;
  final String value;
}

List<_Row> _rowsFor(
  AppLocalizations l10n,
  ReadyProposalPlan plan,
  Map<String, Object?>? overrides,
) {
  String? read(String key) {
    final ov = overrides?[key];
    if (ov is String && ov.isNotEmpty) return ov;
    final v = plan.payload[key];
    if (v == null) return null;
    final s = v is String ? v : v.toString();
    return s.isEmpty ? null : s;
  }

  switch (plan.kind) {
    case ProposalKind.trade:
      return [
        if (read('type') != null)
          _Row(l10n.aiChatRowOperation, _tradeTypeLabel(l10n, read('type')!)),
        if (read('asset_symbol') != null || read('asset_name') != null)
          _Row(
            l10n.aiChatRowAsset,
            read('asset_name') != null && read('asset_symbol') != null
                ? '${read('asset_name')} (${read('asset_symbol')})'
                : (read('asset_name') ?? read('asset_symbol')!),
          ),
        if (read('account_name') != null)
          _Row(l10n.aiChatRowAccount, read('account_name')!),
        if (read('quantity') != null)
          _Row(l10n.aiChatRowQuantity, read('quantity')!),
        if (read('price') != null)
          _Row(
            l10n.aiChatRowPrice,
            '${read('price')} ${read('currency') ?? ''}'.trim(),
          ),
        if (read('fee') != null && read('fee') != '0' && read('fee') != '0.0')
          _Row(l10n.aiChatRowFee, read('fee')!),
        if (read('trade_date') != null)
          _Row(l10n.aiChatRowDate, read('trade_date')!),
        if (read('note') != null) _Row(l10n.aiChatRowNote, read('note')!),
      ];
    case ProposalKind.expense:
      return [
        if (read('amount') != null)
          _Row(
            l10n.aiChatRowAmount,
            '${read('amount')} ${read('currency') ?? ''}'.trim(),
          ),
        if (read('category') != null)
          _Row(l10n.aiChatRowCategory, read('category')!),
        if (read('account_name') != null)
          _Row(l10n.aiChatRowAccount, read('account_name')!),
        if (read('date') != null) _Row(l10n.aiChatRowDate, read('date')!),
        if (read('note') != null) _Row(l10n.aiChatRowNote, read('note')!),
      ];
    case ProposalKind.liabilityPayment:
      return [
        if (read('liability_name') != null)
          _Row(l10n.aiChatRowLiability, read('liability_name')!),
        if (read('amount') != null)
          _Row(
            l10n.aiChatRowAmount,
            '${read('amount')} ${read('currency') ?? ''}'.trim(),
          ),
        if (read('from_account_name') != null)
          _Row(l10n.aiChatRowRepayAccount, read('from_account_name')!),
        if (read('date') != null) _Row(l10n.aiChatRowDate, read('date')!),
        if (read('note') != null) _Row(l10n.aiChatRowNote, read('note')!),
      ];
    case ProposalKind.accountCreate:
      return [
        if (read('name') != null) _Row(l10n.aiChatRowName, read('name')!),
        if (read('type') != null) _Row(l10n.aiChatRowType, read('type')!),
        if (read('currency') != null)
          _Row(l10n.aiChatRowCurrency, read('currency')!),
        if (read('institution') != null)
          _Row(l10n.aiChatRowInstitution, read('institution')!),
        if (read('note') != null) _Row(l10n.aiChatRowNote, read('note')!),
      ];
    case ProposalKind.assetValuation:
      return [
        if (read('asset_name') != null)
          _Row(l10n.aiChatRowAsset, read('asset_name')!),
        if (read('new_value') != null)
          _Row(
            l10n.aiChatRowNewValue,
            '${read('new_value')} ${read('currency') ?? ''}'.trim(),
          ),
        if (read('date') != null) _Row(l10n.aiChatRowDate, read('date')!),
        if (read('note') != null) _Row(l10n.aiChatRowNote, read('note')!),
      ];
    case ProposalKind.unknown:
      return const [];
  }
}

IconData _iconFor(ProposalKind kind) => switch (kind) {
      ProposalKind.trade => Icons.trending_up,
      ProposalKind.expense => Icons.receipt_long,
      ProposalKind.liabilityPayment => Icons.payments_outlined,
      ProposalKind.accountCreate => Icons.account_balance_outlined,
      ProposalKind.assetValuation => Icons.update,
      ProposalKind.unknown => Icons.help_outline,
    };

String _tradeTypeLabel(AppLocalizations l10n, String wire) => switch (wire) {
      'buy' => l10n.tradeTypeBuy,
      'sell' => l10n.tradeTypeSell,
      'transferIn' => l10n.tradeTypeTransferIn,
      'transferOut' => l10n.tradeTypeTransferOut,
      'valuationAdjust' => l10n.tradeTypeValuationAdjust,
      _ => wire,
    };

/// Batch action row shown above multiple pending propose cards in the
/// same assistant turn. Hidden when there's only zero or one ready
/// proposals — the per-card confirm button covers that case already.
class ProposeBatchActions extends ConsumerStatefulWidget {
  const ProposeBatchActions({
    super.key,
    required this.sessionId,
    required this.message,
    required this.pending,
  });

  final String sessionId;
  final ChatMessage message;

  /// (invocation, plan) pairs that are still in `pending` status. Caller
  /// pre-filters; rendering a batch button when there's only one pending
  /// card is just visual noise.
  final List<({ToolInvocation invocation, ReadyProposalPlan plan})> pending;

  @override
  ConsumerState<ProposeBatchActions> createState() =>
      _ProposeBatchActionsState();
}

class _ProposeBatchActionsState extends ConsumerState<ProposeBatchActions> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);
    if (widget.pending.length < 2) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: Spacing.s8),
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.s12,
        vertical: Spacing.s6,
      ),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.4),
        borderRadius: Radii.brMd,
      ),
      child: Row(
        children: [
          Icon(Icons.layers_outlined, size: 18, color: cs.onPrimaryContainer),
          const SizedBox(width: Spacing.s8),
          Expanded(
            child: Text(
              l10n.aiChatProposalBatchPending(widget.pending.length),
              style: tt.labelMedium?.copyWith(color: cs.onPrimaryContainer),
            ),
          ),
          AppButton.primary(
            onPressed: _busy ? null : _confirmAll,
            icon: Icons.done_all,
            label: l10n.aiChatProposalBatchConfirmAll,
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAll() async {
    Haptics.primaryPress();
    setState(() => _busy = true);
    try {
      final applier = await ref.read(proposalApplierProvider.future);
      final repo = await ref.read(chatRepositoryProvider.future);
      for (final entry in widget.pending) {
        final state = entry.invocation.applyState ?? ProposalApplyState.pending;
        if (state.status != ProposalApplyStatus.pending &&
            state.status != ProposalApplyStatus.errored) {
          continue;
        }
        await repo.updateToolApplyState(
          sessionId: widget.sessionId,
          messageId: widget.message.id,
          toolInvocationId: entry.invocation.id,
          newState: state.copyWith(status: ProposalApplyStatus.applying),
        );
        try {
          final result = await applier.apply(entry.plan);
          await repo.updateToolApplyState(
            sessionId: widget.sessionId,
            messageId: widget.message.id,
            toolInvocationId: entry.invocation.id,
            newState: result,
          );
        } on ProposalApplyException catch (e) {
          await repo.updateToolApplyState(
            sessionId: widget.sessionId,
            messageId: widget.message.id,
            toolInvocationId: entry.invocation.id,
            newState: state.copyWith(
              status: ProposalApplyStatus.errored,
              errorMessage: e.message,
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
