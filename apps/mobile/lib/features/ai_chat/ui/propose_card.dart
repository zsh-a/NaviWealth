import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/haptics/haptics.dart';
import '../../../design_system/design_system.dart';
import '../data/proposal_applier.dart';
import '../data/providers.dart';
import '../domain/chat_models.dart';
import '../domain/proposal_apply_state.dart';
import '../domain/proposal_plan.dart';

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
          errorMessage: '撤销失败：${e.message}',
        ),
      );
    } catch (e) {
      await _persist(
        state.copyWith(
          status: ProposalApplyStatus.errored,
          errorMessage: '撤销失败：$e',
        ),
      );
    }
  }

  Future<void> _onEdit(ReadyProposalPlan plan) async {
    final result = await showModalBottomSheet<Map<String, Object?>>(
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
    final isApplying = applyState.status == ProposalApplyStatus.applying;
    final isErrored = applyState.status == ProposalApplyStatus.errored;
    final summary = overrides == null
        ? plan.summaryZh
        : '${plan.summaryZh}（已编辑）';

    return Container(
      margin: const EdgeInsets.only(top: Spacing.s8),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer.withValues(alpha: 0.35),
        borderRadius: Radii.brSm,
        border: Border.all(
          color: cs.tertiary.withValues(alpha: 0.45),
        ),
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
                '待确认 · ${plan.kind.zhLabel}',
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
              '失败：${applyState.errorMessage}',
              style: tt.bodySmall?.copyWith(color: cs.error),
            ),
          ],
          const SizedBox(height: Spacing.s12),
          Wrap(
            spacing: Spacing.s8,
            runSpacing: Spacing.s4,
            children: [
              FilledButton.icon(
                onPressed: isApplying ? null : onConfirm,
                icon: isApplying
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check, size: 16),
                label: Text(isApplying ? '记录中…' : '确认'),
              ),
              OutlinedButton.icon(
                onPressed: isApplying ? null : onCancel,
                icon: const Icon(Icons.close, size: 16),
                label: const Text('取消'),
              ),
              TextButton.icon(
                onPressed: isApplying ? null : onEdit,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('编辑'),
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
    final IconData icon;
    final Color color;
    final String label;
    switch (applyState.status) {
      case ProposalApplyStatus.applied:
        icon = Icons.check_circle;
        color = cs.primary;
        label = applyState.shortLabel ?? '已记录${plan.summaryZh}';
      case ProposalApplyStatus.undone:
        icon = Icons.undo;
        color = cs.onSurfaceVariant;
        label = '已撤销${plan.summaryZh}';
      case ProposalApplyStatus.cancelled:
        icon = Icons.cancel_outlined;
        color = cs.onSurfaceVariant;
        label = '已取消：${plan.summaryZh}';
      default:
        return const SizedBox.shrink();
    }
    final secondsLeft = onUndo != null && applyState.appliedAt != null
        ? 60 - DateTime.now().difference(applyState.appliedAt!).inSeconds
        : 0;

    return Container(
      margin: const EdgeInsets.only(top: Spacing.s8),
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.s12,
        vertical: Spacing.s8,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: Radii.brSm,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
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
            TextButton.icon(
              onPressed: onUndo,
              icon: const Icon(Icons.undo, size: 16),
              label: Text('撤销 (${secondsLeft}s)'),
            ),
        ],
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
    return Container(
      margin: const EdgeInsets.only(top: Spacing.s8),
      padding: const EdgeInsets.all(Spacing.s12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: Radii.brSm,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.help_outline, size: 18, color: cs.tertiary),
              const SizedBox(width: Spacing.s8),
              Text(
                '需要澄清 · ${plan.kind.zhLabel}',
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
              '候选：',
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
    final rows = _rowsFor(plan, overrides);
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
  late final List<_EditableField> _fields;

  @override
  void initState() {
    super.initState();
    _fields = _editableFieldsFor(widget.plan.kind);
    _controllers = {
      for (final f in _fields)
        f.payloadKey: TextEditingController(
          text: _initialFor(f.payloadKey),
        ),
    };
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
    final padding = MediaQuery.of(context).viewInsets.bottom;
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
                  '编辑${widget.plan.kind.zhLabel}',
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
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_collect()),
              child: const Text('保存修改'),
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

List<_EditableField> _editableFieldsFor(ProposalKind kind) {
  switch (kind) {
    case ProposalKind.trade:
      return const [
        _EditableField(payloadKey: 'quantity', label: '数量', numeric: true),
        _EditableField(payloadKey: 'price', label: '价格 (留空则市场回填)', numeric: true),
        _EditableField(payloadKey: 'fee', label: '手续费', numeric: true),
        _EditableField(payloadKey: 'tax', label: '税费', numeric: true),
        _EditableField(payloadKey: 'note', label: '备注'),
      ];
    case ProposalKind.expense:
      return const [
        _EditableField(payloadKey: 'amount', label: '金额', numeric: true),
        _EditableField(
          payloadKey: 'date',
          label: '日期 (RFC3339)',
          hint: '2026-04-30T12:00:00Z',
        ),
        _EditableField(payloadKey: 'note', label: '备注'),
      ];
    case ProposalKind.liabilityPayment:
      return const [
        _EditableField(payloadKey: 'amount', label: '金额', numeric: true),
        _EditableField(
          payloadKey: 'date',
          label: '日期 (RFC3339)',
          hint: '2026-04-30T12:00:00Z',
        ),
        _EditableField(payloadKey: 'note', label: '备注'),
      ];
    case ProposalKind.accountCreate:
      return const [
        _EditableField(payloadKey: 'name', label: '账户名'),
        _EditableField(payloadKey: 'institution', label: '机构 (可选)'),
        _EditableField(payloadKey: 'note', label: '备注'),
      ];
    case ProposalKind.assetValuation:
      return const [
        _EditableField(payloadKey: 'new_value', label: '新估值', numeric: true),
        _EditableField(
          payloadKey: 'date',
          label: '日期 (RFC3339)',
          hint: '2026-04-30T12:00:00Z',
        ),
        _EditableField(payloadKey: 'note', label: '备注'),
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
        if (read('type') != null) _Row('操作', _tradeTypeLabel(read('type')!)),
        if (read('asset_symbol') != null || read('asset_name') != null)
          _Row(
            '资产',
            read('asset_name') != null && read('asset_symbol') != null
                ? '${read('asset_name')} (${read('asset_symbol')})'
                : (read('asset_name') ?? read('asset_symbol')!),
          ),
        if (read('account_name') != null) _Row('账户', read('account_name')!),
        if (read('quantity') != null) _Row('数量', read('quantity')!),
        if (read('price') != null)
          _Row('价格', '${read('price')} ${read('currency') ?? ''}'.trim()),
        if (read('fee') != null && read('fee') != '0' && read('fee') != '0.0')
          _Row('手续费', read('fee')!),
        if (read('trade_date') != null) _Row('日期', read('trade_date')!),
        if (read('note') != null) _Row('备注', read('note')!),
      ];
    case ProposalKind.expense:
      return [
        if (read('amount') != null)
          _Row('金额', '${read('amount')} ${read('currency') ?? ''}'.trim()),
        if (read('category') != null) _Row('类目', read('category')!),
        if (read('account_name') != null) _Row('账户', read('account_name')!),
        if (read('date') != null) _Row('日期', read('date')!),
        if (read('note') != null) _Row('备注', read('note')!),
      ];
    case ProposalKind.liabilityPayment:
      return [
        if (read('liability_name') != null) _Row('负债', read('liability_name')!),
        if (read('amount') != null)
          _Row('金额', '${read('amount')} ${read('currency') ?? ''}'.trim()),
        if (read('from_account_name') != null)
          _Row('还款账户', read('from_account_name')!),
        if (read('date') != null) _Row('日期', read('date')!),
        if (read('note') != null) _Row('备注', read('note')!),
      ];
    case ProposalKind.accountCreate:
      return [
        if (read('name') != null) _Row('名称', read('name')!),
        if (read('type') != null) _Row('类型', read('type')!),
        if (read('currency') != null) _Row('币种', read('currency')!),
        if (read('institution') != null) _Row('机构', read('institution')!),
        if (read('note') != null) _Row('备注', read('note')!),
      ];
    case ProposalKind.assetValuation:
      return [
        if (read('asset_name') != null) _Row('资产', read('asset_name')!),
        if (read('new_value') != null)
          _Row(
            '新估值',
            '${read('new_value')} ${read('currency') ?? ''}'.trim(),
          ),
        if (read('date') != null) _Row('日期', read('date')!),
        if (read('note') != null) _Row('备注', read('note')!),
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

String _tradeTypeLabel(String wire) => switch (wire) {
      'buy' => '买入',
      'sell' => '卖出',
      'transferIn' => '转入',
      'transferOut' => '转出',
      'valuationAdjust' => '估值调整',
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
    if (widget.pending.length < 2) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: Spacing.s8),
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.s12,
        vertical: Spacing.s6,
      ),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.4),
        borderRadius: Radii.brSm,
      ),
      child: Row(
        children: [
          Icon(Icons.layers_outlined, size: 18, color: cs.onPrimaryContainer),
          const SizedBox(width: Spacing.s8),
          Expanded(
            child: Text(
              '本轮共有 ${widget.pending.length} 项待确认',
              style: tt.labelMedium?.copyWith(color: cs.onPrimaryContainer),
            ),
          ),
          FilledButton.icon(
            onPressed: _busy ? null : _confirmAll,
            icon: _busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.done_all, size: 16),
            label: const Text('全部确认'),
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
