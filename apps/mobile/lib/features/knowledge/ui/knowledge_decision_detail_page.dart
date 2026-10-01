import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import '../../../core/ai/visual/ai_markdown.dart';
import '../../../core/forms/form_dirty_guard.dart';
import '../../../core/forms/form_submission.dart';
import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../application/knowledge_deletion_service.dart';
import '../composition/knowledge_route_paths.dart';
import '../data/knowledge_repository.dart';
import '../data/knowledge_rewrite_client.dart';
import '../data/knowledge_search_service.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import 'knowledge_decision_review_sheet.dart';
import 'knowledge_rewrite_sheet.dart';
import 'widgets/knowledge_decision_action_section.dart';
import 'widgets/knowledge_decision_options_editor.dart';
import 'widgets/knowledge_decision_status_badge.dart';
import 'widgets/knowledge_markdown_editor.dart';
import 'widgets/knowledge_relations_section.dart';
import 'widgets/knowledge_rewrite_action.dart';

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
    return value.when(
      loading: () => ObjectDetailScaffold(
        title: l10n.knowledgeSegmentDecisions,
        child: kDefaultLoading,
      ),
      error: (error, stackTrace) => ObjectDetailScaffold(
        title: l10n.knowledgeSegmentDecisions,
        child: kDefaultError(
          context,
          error,
          stackTrace,
          onRetry: () => ref.invalidate(_decisionProvider(decisionId)),
        ),
      ),
      data: (decision) => decision == null
          ? ObjectDetailScaffold(
              title: l10n.knowledgeSegmentDecisions,
              child: Center(child: Text(l10n.knowledgeDecisionNotFound)),
            )
          : _DecisionEditor(
              key: ValueKey(decision.sync.hlc),
              decision: decision,
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

class _DecisionEditorState extends ConsumerState<_DecisionEditor>
    with FormDirtyGuard<_DecisionEditor>, FormSubmission<_DecisionEditor> {
  @override
  String get leaveFallback => KnowledgeRoutes.library;

  late final TextEditingController _question;
  late final TextEditingController _rationale;
  late final TextEditingController _expected;
  late KnowledgeDecisionOptionsController _options;
  final _formKey = GlobalKey<FormState>();
  String? _validationError;
  var _saving = false;

  /// Detail pages open in read mode; the form stays behind this toggle.
  var _editing = false;

  @override
  void initState() {
    super.initState();
    final value = widget.decision;
    _question = TextEditingController(text: value.question);
    _rationale = TextEditingController(text: value.rationaleMd);
    _expected = TextEditingController(text: value.expectedOutcome);
    _options = KnowledgeDecisionOptionsController(
      options: value.options,
      selectedLabel: value.selectedLabel,
    )..addListener(_onOptionsChanged);
    dirty.bindTextControllers(<TextEditingController>[
      _question,
      _rationale,
      _expected,
    ]);
  }

  @override
  void dispose() {
    _question.dispose();
    _rationale.dispose();
    _expected.dispose();
    _options
      ..removeListener(_onOptionsChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return guardedScope(
      child: ObjectDetailScaffold(
        title: l10n.knowledgeSegmentDecisions,
        confirmLeave: handleBackIntent,
        resizeToAvoidBottomInset: !_editing,
        actions: [
          AppHeaderAction(
            key: const Key('knowledge-decision-edit-toggle'),
            semanticsLabel: _editing
                ? l10n.knowledgeViewAction
                : l10n.knowledgeEditAction,
            icon: Icon(_editing ? FLucideIcons.eye : FLucideIcons.pencil),
            onPress: _saving ? null : _toggleMode,
          ),
          AppAdaptiveActionMenu(
            title: l10n.shellMoreActions,
            actions: [
              AppAdaptiveAction(
                icon: FLucideIcons.trash2,
                title: l10n.commonDelete,
                destructive: true,
                onPress: _delete,
              ),
            ],
            triggerBuilder: (context, openMenu, focusNode) => Focus(
              focusNode: focusNode,
              child: AppIconButton(
                icon: FLucideIcons.ellipsis,
                tooltip: l10n.shellMoreActions,
                onPress: _saving ? null : openMenu,
              ),
            ),
          ),
        ],
        child: AnimatedBuilder(
          animation: dirty,
          builder: (context, _) =>
              _editing ? _buildEditForm(context) : _buildReadView(context),
        ),
      ),
    );
  }

  Widget _buildReadView(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final decision = widget.decision;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final decided = DateFormat.yMMMd(locale)
        .format(decision.decidedAt.toLocal());
    final updated = DateFormat.yMMMd(locale)
        .format(decision.sync.updatedAt.toLocal());
    final expected = decision.expectedOutcome?.trim();
    return AdaptiveContentFrame(
      maxWidth: AdaptiveMaxWidth.narrow,
      padding: EdgeInsets.zero,
      expandSinglePrimary: true,
      primary: ListView(
        padding: const EdgeInsets.all(AppSpacing.s16),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  decision.question,
                  style: context.strongHeadlineStyle,
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              KnowledgeDecisionStatusBadge(status: decision.status),
            ],
          ),
          const SizedBox(height: AppSpacing.s16),
          _DecisionOptionsReadView(
            options: decision.options,
            selectedLabel: decision.selectedLabel,
          ),
          if (decision.rationaleMd.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s16),
            Text(
              l10n.knowledgeRationaleLabel,
              style: context.captionLabelStyle,
            ),
            const SizedBox(height: AppSpacing.s8),
            AiMarkdown(text: decision.rationaleMd),
          ],
          if (expected != null && expected.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s16),
            Text(
              l10n.knowledgeExpectedOutcomeLabel,
              style: context.captionLabelStyle,
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(expected, style: context.bodyCaptionStrongStyle),
          ],
          const SizedBox(height: AppSpacing.s20),
          AppMetadataStrip(
            children: [
              AppMetadataItem(
                label: l10n.knowledgeDecidedLabel,
                value: decided,
              ),
              AppMetadataItem(
                label: l10n.knowledgeUpdatedLabel,
                value: updated,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s20),
          _DecisionReviewSection(
            reviewDate: decision.reviewDate,
            revisitConditions: decision.revisitConditions,
            actualOutcomeMd: decision.actualOutcomeMd,
            status: decision.status,
            onReview: _saving ? null : _review,
          ),
          const SizedBox(height: AppSpacing.s16),
          KnowledgeDecisionActionSection(
            decision: widget.decision,
            onBusyChanged: (busy) {
              dirty.busy = busy;
              if (mounted) setState(() => _saving = busy);
            },
          ),
          const SizedBox(height: AppSpacing.s16),
          KnowledgeRelationsSection(
            subjectKind: KnowledgeEntryKind.decision,
            subjectId: widget.decision.id,
            subjectText: KnowledgeSearchDocument.fromDecision(widget.decision)
                .searchText,
          ),
        ],
      ),
    );
  }

  Widget _buildEditForm(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: AppFormScaffoldBody(
        onSubmit: dirty.isDirty && !_saving ? _save : null,
        action: AppSheetFooter(
          submitLabel: l10n.commonSave,
          cancelLabel: l10n.commonCancel,
          enabled: dirty.isDirty,
          busy: _saving,
          onSubmit: _save,
          onCancel: _toggleMode,
        ),
        children: [
          FTextFormField(
            control: FTextFieldControl.managed(controller: _question),
            enabled: !_saving,
            label: Text(l10n.knowledgeDecisionQuestionLabel),
            maxLines: 2,
            validator: (value) => value?.trim().isNotEmpty == true
                ? null
                : l10n.knowledgeDecisionSaveRequirement,
          ),
          const SizedBox(height: AppSpacing.s12),
          KnowledgeDecisionOptionsEditor(
            controller: _options,
            keyPrefix: 'knowledge-decision-detail',
            enabled: !_saving,
          ),
          if (_validationError case final message?) ...[
            const SizedBox(height: AppSpacing.s8),
            AppStatusBanner(
              message: message,
              kind: AppStatusKind.error,
              compact: true,
            ),
          ],
          const SizedBox(height: AppSpacing.s12),
          KnowledgeMarkdownEditor(
            controller: _rationale,
            label: l10n.knowledgeWriterRationaleMarkdownLabel,
            minLines: 5,
            enabled: !_saving,
          ),
          const SizedBox(height: AppSpacing.s8),
          KnowledgeRewriteAction(enabled: !_saving, onRewrite: _rewrite),
          const SizedBox(height: AppSpacing.s12),
          FTextField(
            control: FTextFieldControl.managed(controller: _expected),
            enabled: !_saving,
            label: Text(l10n.knowledgeDecisionExpectedOutcomeLabel),
            maxLines: 3,
          ),
          if (submissionFailureMessage case final message?) ...[
            const SizedBox(height: AppSpacing.s12),
            AppStatusBanner(message: message, kind: AppStatusKind.error),
          ],
        ],
      ),
    );
  }

  Future<void> _toggleMode() async {
    if (_editing) {
      final discard = await confirmDiscardIfDirty(context, dirty);
      if (!discard || !mounted) return;
      _resetFields();
    }
    setState(() => _editing = !_editing);
  }

  void _resetFields() {
    final value = widget.decision;
    _question.text = value.question;
    _rationale.text = value.rationaleMd;
    _expected.text = value.expectedOutcome ?? '';
    _options
      ..removeListener(_onOptionsChanged)
      ..dispose();
    _options = KnowledgeDecisionOptionsController(
      options: value.options,
      selectedLabel: value.selectedLabel,
    )..addListener(_onOptionsChanged);
    dirty.markPristine();
  }

  Future<bool> _save() async {
    if (_saving) return false;
    final l10n = AppLocalizations.of(context);
    if (!(_formKey.currentState?.validate() ?? false)) return false;
    if (!_options.isValid) {
      setState(() => _validationError = l10n.knowledgeDecisionOptionsInvalid);
      return false;
    }
    setState(() => _validationError = null);
    return submitForm<void>(
      dirty: dirty,
      onBusyChanged: (busy) => setState(() => _saving = busy),
      commit: () => _commitDecision(),
      leave: () {
        ref.invalidate(_decisionProvider(widget.decision.id));
        ref.invalidate(knowledgeDecisionsProvider);
      },
      failureMessage: (error) => userSafeErrorMessage(
        context,
        error,
        operation: 'save knowledge decision',
      ),
      successMessage: l10n.commonSaved,
      tag: 'knowledge-decision-edit',
    );
  }

  KnowledgeDecision _draftDecision({SyncMeta? sync}) {
    return KnowledgeDecision(
      id: widget.decision.id,
      question: _question.text.trim(),
      options: _options.options,
      selectedLabel: _options.selectedLabel,
      rationaleMd: _rationale.text.trim(),
      expectedOutcome: _nullable(_expected.text),
      reviewDate: widget.decision.reviewDate,
      revisitConditions: widget.decision.revisitConditions,
      actualOutcomeMd: widget.decision.actualOutcomeMd,
      status: widget.decision.status,
      supersededByDecisionId: widget.decision.supersededByDecisionId,
      decidedAt: widget.decision.decidedAt,
      mergedIntoId: widget.decision.mergedIntoId,
      sync: sync ?? widget.decision.sync,
    );
  }

  Future<void> _commitDecision() async {
    final repository = await ref.read(knowledgeRepositoryProvider.future);
    final stamper = await ref.read(mutationStamperProvider.future);
    final value = await stamper.stamp();
    await repository.upsertDecision(
      _draftDecision(
        sync: SyncMeta(
          ownerUserId: value.ownerUserId,
          updatedAt: value.now,
          updatedByDevice: value.deviceId,
          hlc: value.hlc,
        ),
      ),
    );
  }

  Future<void> _review() async {
    if (_saving) return;
    final reviewed = await reviewSavedKnowledgeDecision(
      context: context,
      ref: ref,
      decision: widget.decision,
    );
    if (mounted && reviewed) {
      ref.invalidate(_decisionProvider(widget.decision.id));
    }
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
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context: context,
      title: Text(l10n.knowledgeDecisionDeleteConfirmTitle),
      body: Text(l10n.knowledgeDeleteConfirmBody),
      confirmLabel: l10n.commonDelete,
      cancelLabel: l10n.commonCancel,
      destructive: true,
      icon: FLucideIcons.trash2,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    dirty.busy = true;
    try {
      final service = await ref.read(knowledgeDeletionServiceProvider.future);
      await service.delete(
        kind: KnowledgeEntryKind.decision,
        id: widget.decision.id,
      );
      ref.invalidate(knowledgeDecisionsProvider);
      dirty.markPristine();
      if (mounted) {
        AppMessenger.show(context, ToastKind.success, l10n.commonDeleted);
        popOrGo(context, fallback: KnowledgeRoutes.library);
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
          operation: 'delete knowledge decision',
        ),
      );
    } finally {
      dirty.busy = false;
      if (mounted) setState(() => _saving = false);
    }
  }

  void _onOptionsChanged() {
    dirty.markDirty();
    if (_validationError != null && mounted) {
      setState(() => _validationError = null);
    }
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
      trailing: KnowledgeDecisionStatusBadge(
        status: status,
        size: AppBadgeSize.compact,
      ),
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

/// Static presentation of the decision's options — same card language as
/// [KnowledgeDecisionOptionsEditor], minus the editing controls.
class _DecisionOptionsReadView extends StatelessWidget {
  const _DecisionOptionsReadView({
    required this.options,
    required this.selectedLabel,
  });

  final List<DecisionOption> options;
  final String selectedLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppSection.item(
      title: l10n.knowledgeDecisionOptionsLabel,
      children: [
        for (var index = 0; index < options.length; index++) ...[
          if (index > 0) const SizedBox(height: AppSpacing.s10),
          _DecisionOptionReadCard(
            key: ValueKey<String>('knowledge-decision-read-option-$index'),
            option: options[index],
            selected: options[index].label == selectedLabel,
          ),
        ],
      ],
    );
  }
}

class _DecisionOptionReadCard extends StatelessWidget {
  const _DecisionOptionReadCard({
    super.key,
    required this.option,
    required this.selected,
  });

  final DecisionOption option;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final rationale = option.rationale?.trim();
    return SoftCard.flat(
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                selected ? FLucideIcons.circleCheck : FLucideIcons.circle,
                size: AppIconSizes.sm,
                color: selected ? colors.primary : colors.mutedForeground,
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Text(
                  option.label,
                  style: selected
                      ? context.mediumLabelStyle.copyWith(
                          color: colors.foreground,
                        )
                      : context.bodyCaptionStrongStyle,
                ),
              ),
              if (selected) ...[
                const SizedBox(width: AppSpacing.s8),
                AppBadge(
                  label: l10n.knowledgeDecisionOptionSelected,
                  tone: AppBadgeTone.accent,
                  size: AppBadgeSize.compact,
                ),
              ],
            ],
          ),
          if (rationale != null && rationale.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s8),
            Text(rationale, style: context.bodyCaptionStyle),
          ],
        ],
      ),
    );
  }
}
