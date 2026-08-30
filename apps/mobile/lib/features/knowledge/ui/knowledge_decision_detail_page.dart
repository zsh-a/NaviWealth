import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ai/visual/ai_pill.dart';
import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../application/knowledge_deletion_service.dart';
import '../data/knowledge_repository.dart';
import '../data/knowledge_rewrite_client.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import 'knowledge_decision_review_sheet.dart';
import 'knowledge_rewrite_sheet.dart';
import 'widgets/knowledge_decision_action_section.dart';
import 'widgets/knowledge_markdown_editor.dart';
import 'widgets/knowledge_relations_section.dart';

final _decisionProvider = FutureProvider.autoDispose
    .family<KnowledgeDecision?, String>((ref, id) async {
      final repository = await ref.watch(knowledgeRepositoryProvider.future);
      final owner = await ref.watch(knowledgeOwnerUserIdProvider.future);
      return repository.findDecision(ownerUserId: owner, id: id);
    });

class KnowledgeDecisionDetailPage extends ConsumerWidget {
  const KnowledgeDecisionDetailPage({super.key, required this.decisionId});

  final String decisionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final value = ref.watch(_decisionProvider(decisionId));
    return ObjectDetailScaffold(
      title: l10n.knowledgeSegmentDecisions,
      child: value.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text(l10n.commonLoadFailed)),
        data: (decision) => decision == null
            ? Center(child: Text(l10n.knowledgeDecisionNotFound))
            : _DecisionEditor(
                key: ValueKey(decision.sync.hlc),
                decision: decision,
              ),
      ),
    );
  }
}

class _DecisionEditor extends ConsumerStatefulWidget {
  const _DecisionEditor({super.key, required this.decision});

  final KnowledgeDecision decision;

  @override
  ConsumerState<_DecisionEditor> createState() => _DecisionEditorState();
}

class _DecisionEditorState extends ConsumerState<_DecisionEditor> {
  late final TextEditingController _question;
  late final TextEditingController _selected;
  late final TextEditingController _rationale;
  late final TextEditingController _expected;
  late final TextEditingController _actual;
  late DecisionStatus _status;
  late DateTime? _reviewDate;
  late List<DecisionRevisitCondition> _revisitConditions;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    final value = widget.decision;
    _question = TextEditingController(text: value.question);
    _selected = TextEditingController(text: value.selectedLabel);
    _rationale = TextEditingController(text: value.rationaleMd);
    _expected = TextEditingController(text: value.expectedOutcome);
    _actual = TextEditingController(text: value.actualOutcomeMd);
    _status = value.status;
    _reviewDate = value.reviewDate;
    _revisitConditions = value.revisitConditions;
  }

  @override
  void dispose() {
    _question.dispose();
    _selected.dispose();
    _rationale.dispose();
    _expected.dispose();
    _actual.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.s16),
      children: [
        FTextField(
          control: FTextFieldControl.managed(controller: _question),
          label: Text(l10n.knowledgeDecisionQuestionLabel),
          maxLines: 2,
        ),
        const SizedBox(height: AppSpacing.s12),
        FTextField(
          control: FTextFieldControl.managed(controller: _selected),
          label: Text(l10n.knowledgeDecisionSelectedOptionLabel),
          maxLines: 1,
        ),
        const SizedBox(height: AppSpacing.s12),
        KnowledgeMarkdownEditor(
          controller: _rationale,
          label: l10n.knowledgeWriterRationaleMarkdownLabel,
          minLines: 5,
          enabled: !_saving,
        ),
        const SizedBox(height: AppSpacing.s8),
        Align(
          alignment: Alignment.centerLeft,
          child: AiPill(
            leading: const Icon(FLucideIcons.pencil, size: AppIconSizes.xs),
            label: l10n.knowledgeRewriteAction,
            onTap: _saving ? null : _rewrite,
          ),
        ),
        const SizedBox(height: AppSpacing.s12),
        FTextField(
          control: FTextFieldControl.managed(controller: _expected),
          label: Text(l10n.knowledgeDecisionExpectedOutcomeLabel),
          maxLines: 3,
        ),
        const SizedBox(height: AppSpacing.s20),
        SizedBox(
          width: double.infinity,
          child: AppActionButton(
            onPress: _saving ? null : _save,
            child: Text(_saving ? l10n.commonSaving : l10n.commonSave),
          ),
        ),
        const SizedBox(height: AppSpacing.s20),
        _DecisionReviewSection(
          reviewDate: _reviewDate,
          revisitConditions: _revisitConditions,
          actualOutcomeMd: _nullable(_actual.text),
          status: _status,
          onReview: _saving ? null : _review,
        ),
        const SizedBox(height: AppSpacing.s16),
        KnowledgeDecisionActionSection(decision: widget.decision),
        const SizedBox(height: AppSpacing.s16),
        KnowledgeRelationsSection(
          subjectKind: KnowledgeEntryKind.decision,
          subjectId: widget.decision.id,
        ),
        const SizedBox(height: AppSpacing.s16),
        FButton(
          variant: FButtonVariant.destructive,
          onPress: _saving ? null : _delete,
          child: Text(l10n.commonDelete),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final question = _question.text.trim();
    final selected = _selected.text.trim();
    final l10n = AppLocalizations.of(context);
    if (question.isEmpty || selected.isEmpty) {
      AppMessenger.show(
        context,
        ToastKind.warning,
        l10n.knowledgeDecisionSaveRequirement,
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final repository = await ref.read(knowledgeRepositoryProvider.future);
      final stamper = await ref.read(mutationStamperProvider.future);
      final value = await stamper.stamp();
      final priorOptions = widget.decision.options
          .where((option) => option.label != selected)
          .toList(growable: true);
      await repository.upsertDecision(
        KnowledgeDecision(
          id: widget.decision.id,
          question: question,
          options: <DecisionOption>[
            DecisionOption(label: selected),
            ...priorOptions,
          ],
          selectedLabel: selected,
          rationaleMd: _rationale.text.trim(),
          expectedOutcome: _nullable(_expected.text),
          reviewDate: _reviewDate,
          revisitConditions: _revisitConditions,
          actualOutcomeMd: _nullable(_actual.text),
          status: _status,
          supersededByDecisionId: widget.decision.supersededByDecisionId,
          decidedAt: widget.decision.decidedAt,
          mergedIntoId: widget.decision.mergedIntoId,
          sync: SyncMeta(
            ownerUserId: value.ownerUserId,
            updatedAt: value.now,
            updatedByDevice: value.deviceId,
            hlc: value.hlc,
          ),
        ),
      );
      ref.invalidate(_decisionProvider(widget.decision.id));
      ref.invalidate(knowledgeDecisionsProvider);
      if (mounted) {
        AppMessenger.show(context, ToastKind.success, l10n.commonSaved);
      }
    } on Object catch (error, stackTrace) {
      if (!mounted) return;
      AppMessenger.show(
        context,
        ToastKind.error,
        userSafeErrorMessage(
          context,
          error,
          stackTrace: stackTrace,
          operation: 'save knowledge decision',
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _review() async {
    final draft = await showKnowledgeDecisionReviewSheet(
      context: context,
      decision: KnowledgeDecision(
        id: widget.decision.id,
        question: _question.text.trim(),
        options: widget.decision.options,
        selectedLabel: _selected.text.trim(),
        rationaleMd: _rationale.text.trim(),
        expectedOutcome: _nullable(_expected.text),
        reviewDate: _reviewDate,
        revisitConditions: _revisitConditions,
        actualOutcomeMd: _nullable(_actual.text),
        status: _status,
        supersededByDecisionId: widget.decision.supersededByDecisionId,
        decidedAt: widget.decision.decidedAt,
        mergedIntoId: widget.decision.mergedIntoId,
        sync: widget.decision.sync,
      ),
    );
    if (!mounted || draft == null) return;
    setState(() {
      _reviewDate = draft.reviewDate;
      _revisitConditions = draft.revisitConditions;
      _actual.text = draft.actualOutcomeMd ?? '';
      _status = draft.status;
    });
    await _save();
  }

  Future<void> _rewrite() async {
    FocusScope.of(context).unfocus();
    final draft = await showKnowledgeRewriteSheet(
      context: context,
      kind: KnowledgeRewriteKind.decision,
      objectId: widget.decision.id,
      heading: _question.text,
      content: _rationale.text,
    );
    if (!mounted || draft == null) return;
    setState(() {
      _question.text = draft.heading;
      _rationale.text = draft.content;
    });
  }

  Future<void> _delete() async {
    final service = await ref.read(knowledgeDeletionServiceProvider.future);
    await service.delete(
      kind: KnowledgeEntryKind.decision,
      id: widget.decision.id,
    );
    ref.invalidate(knowledgeDecisionsProvider);
    if (mounted) context.pop();
  }
}

class _DecisionReviewSection extends StatelessWidget {
  const _DecisionReviewSection({
    required this.reviewDate,
    required this.revisitConditions,
    required this.actualOutcomeMd,
    required this.status,
    required this.onReview,
  });

  final DateTime? reviewDate;
  final List<DecisionRevisitCondition> revisitConditions;
  final String? actualOutcomeMd;
  final DecisionStatus status;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final date = reviewDate;
    final pending = switch (status) {
      DecisionStatus.draft ||
      DecisionStatus.active ||
      DecisionStatus.paused => true,
      _ => false,
    };
    final due =
        date != null &&
        pending &&
        !date.toUtc().isAfter(DateTime.now().toUtc());
    final dateLabel = date == null
        ? l10n.knowledgeDecisionReviewNotScheduled
        : MaterialLocalizations.of(context).formatMediumDate(date.toLocal());
    final actionLabel = due
        ? l10n.knowledgeDecisionReviewNowAction
        : date == null
        ? l10n.knowledgeDecisionReviewScheduleAction
        : l10n.knowledgeDecisionReviewEditAction;
    final outcome = actualOutcomeMd?.trim();
    return AppSection.item(
      title: l10n.knowledgeDecisionReviewTitle,
      trailing: FBadge(child: Text(knowledgeDecisionStatusLabel(l10n, status))),
      children: [
        Row(
          children: [
            Icon(
              due ? FLucideIcons.clockAlert : FLucideIcons.calendarClock,
              size: AppIconSizes.sm,
              color: due
                  ? context.theme.colors.destructive
                  : context.theme.colors.mutedForeground,
            ),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: Text(
                due ? l10n.knowledgeDecisionReviewDue(dateLabel) : dateLabel,
                style: due
                    ? context.labelStyle.copyWith(
                        color: context.theme.colors.destructive,
                      )
                    : context.bodyCaptionStyle,
              ),
            ),
          ],
        ),
        if (revisitConditions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s6),
          Text(
            l10n.knowledgeDecisionRevisitConditionsCount(
              revisitConditions.length,
            ),
            style: context.captionStyle,
          ),
        ],
        if (outcome != null && outcome.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s8),
          Text(
            outcome,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: context.bodyCaptionStyle,
          ),
        ],
        const SizedBox(height: AppSpacing.s10),
        SizedBox(
          width: double.infinity,
          child: due
              ? AppActionButton(
                  key: const Key('knowledge-decision-review'),
                  onPress: onReview,
                  child: Text(actionLabel),
                )
              : AppQuietButton(
                  key: const Key('knowledge-decision-review'),
                  label: actionLabel,
                  prefix: const Icon(FLucideIcons.history),
                  onPress: onReview,
                ),
        ),
      ],
    );
  }
}

String? _nullable(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
