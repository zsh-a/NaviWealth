/// KnowledgeOS Decision lifecycle editor
/// (`docs/domains/knowledgeos-domain.md` §3 + §9 — the 7-state lifecycle and the
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

import '../../../core/forms/form_dirty_guard.dart';
import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '_widgets.dart';

/// Human (zh) label for each [DecisionStatus]. Kept next to the sheet so
/// the status chooser and any future badge localisation share one source.
String decisionStatusLabel(BuildContext context, DecisionStatus s) {
  final l10n = AppLocalizations.of(context);
  return switch (s) {
    DecisionStatus.draft => l10n.knowledgeDecisionStatusDraft,
    DecisionStatus.active => l10n.knowledgeDecisionStatusActive,
    DecisionStatus.paused => l10n.knowledgeDecisionStatusPaused,
    DecisionStatus.expired => l10n.knowledgeDecisionStatusExpired,
    DecisionStatus.verified => l10n.knowledgeDecisionStatusVerified,
    DecisionStatus.falsified => l10n.knowledgeDecisionStatusFalsified,
    DecisionStatus.superseded => l10n.knowledgeDecisionStatusSuperseded,
  };
}

/// Opens the lifecycle editor for [decision]. Resolves to `true` when a
/// change was saved (the caller reloads), `null`/`false` otherwise.
Future<bool?> showDecisionLifecycleSheet(
  BuildContext context,
  WidgetRef _,
  KnowledgeDecision decision,
) {
  return showGuardedFormSheet<bool>(
    context: context,
    builder: (_, dirty) =>
        _DecisionLifecycleSheet(decision: decision, dirty: dirty),
  );
}

class _DecisionLifecycleSheet extends ConsumerStatefulWidget {
  const _DecisionLifecycleSheet({required this.decision, required this.dirty});
  final KnowledgeDecision decision;
  final FormDirtyController dirty;
  @override
  ConsumerState<_DecisionLifecycleSheet> createState() =>
      _DecisionLifecycleSheetState();
}

class _DecisionLifecycleSheetState
    extends ConsumerState<_DecisionLifecycleSheet> {
  late DecisionStatus _status = widget.decision.status;
  late final TextEditingController _outcomeCtrl = TextEditingController(
    text: widget.decision.actualOutcomeMd ?? '',
  );
  late String? _supersededBy = widget.decision.supersededByDecisionId;
  List<KnowledgeDecision> _candidates = const <KnowledgeDecision>[];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    widget.dirty.bindTextControllers([_outcomeCtrl]);
    _loadCandidates();
  }

  @override
  void dispose() {
    _outcomeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCandidates() async {
    final repo = await ref.read(knowledgeRepositoryProvider.future);
    final all = await repo.listDecisions(
      ownerUserId: widget.decision.sync.ownerUserId,
    );
    if (!mounted) return;
    setState(() {
      _candidates = all
          .where((d) => d.id != widget.decision.id)
          .toList(growable: false);
    });
  }

  // A superseded decision must name the decision that replaced it, else the
  // chain link dangles. Every other status saves freely.
  bool get _canSave {
    if (_saving) return false;
    if (_status != DecisionStatus.draft) {
      final labels = widget.decision.options
          .map((option) => option.label.trim())
          .where((label) => label.isNotEmpty)
          .toSet();
      if (labels.length < 2 ||
          !labels.contains(widget.decision.selectedLabel)) {
        return false;
      }
    }
    if (_status == DecisionStatus.superseded && _supersededBy == null) {
      return false;
    }
    return true;
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    widget.dirty.busy = true;
    try {
      final repo = await ref.read(knowledgeRepositoryProvider.future);
      final stamper = await ref.read(mutationStamperProvider.future);
      final stamp = await stamper.stamp();
      final d = widget.decision;
      final outcome = _outcomeCtrl.text.trim();
      // Only a `superseded` decision keeps the supersededBy link; clearing
      // the status clears the pointer so the chain doesn't show a stale edge.
      final supersededBy = _status == DecisionStatus.superseded
          ? _supersededBy
          : null;
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
      widget.dirty.markPristine();
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.error,
          AppLocalizations.of(context).commonSaveFailed,
        );
      }
    } finally {
      widget.dirty.busy = false;
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppSheet(
      title: l10n.knowledgeDecisionLifecycleTitle,
      subtitle: l10n.knowledgeDecisionLifecycleSubtitle,
      footer: AppSheetFooter(
        submitLabel: _saving ? l10n.commonSaving : l10n.commonSave,
        cancelLabel: l10n.commonCancel,
        busy: _saving,
        enabled: _canSave,
        onSubmit: _save,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KnowledgeWriterSection(
            title: l10n.knowledgeDecisionStatusLabel,
            children: [
              AppAdaptiveChoice<DecisionStatus>(
                title: l10n.knowledgeDecisionStatusLabel,
                options: DecisionStatus.values,
                value: _status,
                labelOf: (status) => decisionStatusLabel(context, status),
                iconOf: _decisionStatusIcon,
                onChanged: (status) {
                  setState(() => _status = status);
                  widget.dirty.markDirty();
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          KnowledgeWriterSection(
            title: l10n.knowledgeDecisionActualOutcomeLabel,
            children: [
              MarkdownEditorWithPreview(
                controller: _outcomeCtrl,
                hint: l10n.knowledgeDecisionActualOutcomeHint,
                minLines: 2,
                maxLines: 6,
              ),
            ],
          ),
          if (_status == DecisionStatus.superseded) ...[
            const SizedBox(height: AppSpacing.s12),
            KnowledgeWriterSection(
              title: l10n.knowledgeDecisionSupersededByLabel,
              collapsible: true,
              children: [
                if (_candidates.isEmpty)
                  KnowledgeEmptyState(
                    icon: FLucideIcons.gitBranch,
                    title: l10n.knowledgeDecisionSupersededByEmpty,
                    density: KnowledgeStateDensity.section,
                  )
                else
                  for (final c in _candidates)
                    KnowledgeSelectableRow(
                      label: c.question,
                      detail: decisionStatusLabel(context, c.status),
                      selected: c.id == _supersededBy,
                      mode: KnowledgeSelectionMode.radio,
                      maxLines: 2,
                      onPress: () {
                        setState(() => _supersededBy = c.id);
                        widget.dirty.markDirty();
                      },
                    ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

IconData _decisionStatusIcon(DecisionStatus status) => switch (status) {
  DecisionStatus.draft => FLucideIcons.filePenLine,
  DecisionStatus.active => FLucideIcons.play,
  DecisionStatus.paused => FLucideIcons.pause,
  DecisionStatus.expired => FLucideIcons.clockAlert,
  DecisionStatus.verified => FLucideIcons.badgeCheck,
  DecisionStatus.falsified => FLucideIcons.badgeX,
  DecisionStatus.superseded => FLucideIcons.gitPullRequestArrow,
};
