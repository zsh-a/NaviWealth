/// KnowledgeOS Decision lifecycle editor
/// (`docs/knowledgeos-domain.md` §3 + §9 — the 7-state lifecycle and the
/// `supersededByDecisionId` "认知演化" chain).
///
/// The detail page is otherwise read-only; this sheet is the single write
/// path for evolving a decision after it was first recorded:
///
/// - change `status` across the 7 states,
/// - capture `actual_outcome` (markdown) once the result is known,
/// - mark the decision `superseded` and point it at the newer decision
///   that replaced it (required when status == superseded — that link is
///   what makes the chain in the detail page resolve).
///
/// Reuses the cross-domain `mutationStamperProvider` stamp + `upsertDecision`
/// (insert-or-replace), so one save mints a fresh HLC and syncs as a normal
/// row update.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../../../design_system/design_system.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '_widgets.dart';

/// Human (zh) label for each [DecisionStatus]. Kept next to the sheet so
/// the status chooser and any future badge localisation share one source.
String decisionStatusLabel(DecisionStatus s) => switch (s) {
  DecisionStatus.draft => '草稿',
  DecisionStatus.active => '进行中',
  DecisionStatus.paused => '暂停',
  DecisionStatus.expired => '已过期',
  DecisionStatus.verified => '已验证',
  DecisionStatus.falsified => '已证伪',
  DecisionStatus.superseded => '已被取代',
};

/// Opens the lifecycle editor for [decision]. Resolves to `true` when a
/// change was saved (the caller reloads), `null`/`false` otherwise.
Future<bool?> showDecisionLifecycleSheet(
  BuildContext context,
  WidgetRef ref,
  KnowledgeDecision decision,
) {
  return showAppFormSheet<bool>(
    context: context,
    builder: (_) => _DecisionLifecycleSheet(ref: ref, decision: decision),
  );
}

class _DecisionLifecycleSheet extends StatefulWidget {
  const _DecisionLifecycleSheet({required this.ref, required this.decision});
  final WidgetRef ref;
  final KnowledgeDecision decision;
  @override
  State<_DecisionLifecycleSheet> createState() =>
      _DecisionLifecycleSheetState();
}

class _DecisionLifecycleSheetState extends State<_DecisionLifecycleSheet> {
  late DecisionStatus _status = widget.decision.status;
  late final TextEditingController _outcomeCtrl =
      TextEditingController(text: widget.decision.actualOutcomeMd ?? '');
  late String? _supersededBy = widget.decision.supersededByDecisionId;
  List<KnowledgeDecision> _candidates = const <KnowledgeDecision>[];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadCandidates();
  }

  @override
  void dispose() {
    _outcomeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCandidates() async {
    final repo = await widget.ref.read(knowledgeRepositoryProvider.future);
    final all = await repo.listDecisions(
      ownerUserId: widget.decision.sync.ownerUserId,
    );
    if (!mounted) return;
    setState(() {
      _candidates =
          all.where((d) => d.id != widget.decision.id).toList(growable: false);
    });
  }

  // A superseded decision must name the decision that replaced it, else the
  // chain link dangles. Every other status saves freely.
  bool get _canSave {
    if (_saving) return false;
    if (_status == DecisionStatus.superseded && _supersededBy == null) {
      return false;
    }
    return true;
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    try {
      final repo = await widget.ref.read(knowledgeRepositoryProvider.future);
      final stamper = await widget.ref.read(mutationStamperProvider.future);
      final stamp = await stamper.stamp();
      final d = widget.decision;
      final outcome = _outcomeCtrl.text.trim();
      // Only a `superseded` decision keeps the supersededBy link; clearing
      // the status clears the pointer so the chain doesn't show a stale edge.
      final supersededBy =
          _status == DecisionStatus.superseded ? _supersededBy : null;
      final updated = KnowledgeDecision(
        id: d.id,
        question: d.question,
        options: d.options,
        selectedLabel: d.selectedLabel,
        rationaleMd: d.rationaleMd,
        principleIds: d.principleIds,
        assumptionIds: d.assumptionIds,
        expectedOutcome: d.expectedOutcome,
        reviewDate: d.reviewDate,
        actualOutcomeMd: outcome.isEmpty ? null : outcome,
        status: _status,
        supersededByDecisionId: supersededBy,
        contextSnapshot: d.contextSnapshot,
        decidedAt: d.decidedAt,
        sync: SyncMeta(
          ownerUserId: stamp.ownerUserId,
          updatedAt: stamp.now,
          updatedByDevice: stamp.deviceId,
          hlc: stamp.hlc,
        ),
      );
      await repo.upsertDecision(updated);
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final typography = context.theme.typography;
    final colors = context.theme.colors;
    return AppSheet(
      title: '更新 Decision',
      subtitle: '状态 / 实际结果 / 认知演化链',
      footer: AppSheetFooter(
        submitLabel: _saving ? '保存中…' : '保存',
        busy: !_canSave,
        onSubmit: _save,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '状态',
            style: typography.sm.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.s8),
          Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            children: [
              for (final s in DecisionStatus.values)
                FButton(
                  variant: s == _status
                      ? FButtonVariant.primary
                      : FButtonVariant.outline,
                  onPress: () => setState(() => _status = s),
                  child: Text(decisionStatusLabel(s)),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s16),
          MarkdownEditorWithPreview(
            controller: _outcomeCtrl,
            label: '实际结果（Markdown，可选）',
            hint: '复盘时填：实际发生了什么、和预期的差距',
            minLines: 2,
            maxLines: 6,
          ),
          if (_status == DecisionStatus.superseded) ...[
            const SizedBox(height: AppSpacing.s16),
            Text(
              '被哪条 Decision 取代',
              style: typography.sm.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.s4),
            if (_candidates.isEmpty)
              Text(
                '还没有其它 Decision 可指向——先记录新决策,再回来标记取代关系。',
                style:
                    typography.xs.copyWith(color: colors.mutedForeground),
              )
            else
              for (final c in _candidates)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _supersededBy = c.id),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.s4),
                    child: Row(
                      children: [
                        Icon(
                          c.id == _supersededBy
                              ? FLucideIcons.checkCircle2
                              : FLucideIcons.circle,
                          size: 14,
                          color: c.id == _supersededBy
                              ? colors.primary
                              : colors.mutedForeground,
                        ),
                        const SizedBox(width: AppSpacing.s8),
                        Expanded(
                          child: Text(
                            '${c.question}（${decisionStatusLabel(c.status)}）',
                            style: typography.sm,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }
}
