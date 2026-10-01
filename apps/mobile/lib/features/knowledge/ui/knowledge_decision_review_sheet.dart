import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/forms/forms.dart';
import '../../../core/product/product_metrics.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../application/knowledge_decision_review_service.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import 'widgets/knowledge_edit_notice.dart';
import 'widgets/knowledge_markdown_editor.dart';

export '../domain/knowledge_models.dart' show KnowledgeDecisionReviewDraft;

Future<KnowledgeDecisionReviewDraft?> showKnowledgeDecisionReviewSheet({
  required BuildContext context,
  required KnowledgeDecision decision,
  required Future<void> Function(KnowledgeDecisionReviewDraft draft) onSave,
  bool schedule = false,
}) {
  return showGuardedFormSheet<KnowledgeDecisionReviewDraft>(
    context: context,
    builder: (_, dirty) => _KnowledgeDecisionReviewSheet(
      decision: decision,
      dirty: dirty,
      onSave: onSave,
      schedule: schedule,
    ),
  );
}

class _KnowledgeDecisionReviewSheet extends ConsumerStatefulWidget {
  const _KnowledgeDecisionReviewSheet({
    required this.decision,
    required this.dirty,
    required this.onSave,
    required this.schedule,
  });

  final KnowledgeDecision decision;
  final FormDirtyController dirty;
  final Future<void> Function(KnowledgeDecisionReviewDraft draft) onSave;
  final bool schedule;

  @override
  ConsumerState<_KnowledgeDecisionReviewSheet> createState() =>
      _KnowledgeDecisionReviewSheetState();
}

class _KnowledgeDecisionReviewSheetState
    extends ConsumerState<_KnowledgeDecisionReviewSheet>
    with FormSubmission<_KnowledgeDecisionReviewSheet> {
  bool _saving = false;
  bool _showDetails = false;
  late final TextEditingController _conditions;
  late final TextEditingController _actual;
  late DateTime? _reviewDate;
  late DecisionStatus _status;
  String? _validationError;

  KnowledgeDecisionReviewDraft get _draft => KnowledgeDecisionReviewDraft(
    reviewDate: _reviewDate,
    revisitConditions: _parseConditions(),
    actualOutcomeMd: _nullable(_actual.text),
    status: _status,
  );

  bool get _pending => switch (_status) {
    DecisionStatus.active ||
    DecisionStatus.draft ||
    DecisionStatus.paused => true,
    _ => false,
  };

  bool get _needsNextDate =>
      _pending &&
      widget.decision.reviewDate != null &&
      !widget.decision.reviewDate!.toUtc().isAfter(DateTime.now().toUtc());

  @override
  void initState() {
    super.initState();
    final decision = widget.decision;
    _conditions = TextEditingController(
      text: decision.revisitConditions
          .map((condition) => condition.statement)
          .join('\n'),
    );
    _actual = TextEditingController(text: decision.actualOutcomeMd);
    _reviewDate = decision.reviewDate;
    _status = decision.status;
    widget.dirty.bindTextControllers([_conditions, _actual]);
    _conditions.addListener(_onTextChanged);
    _actual.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (mounted) setState(() => _validationError = null);
  }

  @override
  void dispose() {
    _conditions.dispose();
    _actual.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final expected = widget.decision.expectedOutcome?.trim();
    return AppSheet(
      title: widget.schedule
          ? l10n.knowledgeDecisionReviewScheduleAction
          : l10n.knowledgeDecisionReviewTitle,
      subtitle: widget.decision.question,
      footer: AppSheetFooter(
        submitKey: const Key('knowledge-decision-review-submit'),
        submitLabel: widget.schedule
            ? l10n.commonSave
            : l10n.knowledgeDecisionReviewSaveAction,
        cancelLabel: l10n.commonCancel,
        onSubmit: _submit,
        busy: _saving,
        enabled: !_draft.matchesDecision(widget.decision),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.schedule) ...[
            _dateField(),
            const SizedBox(height: AppSpacing.s16),
          ],
          if (expected != null && expected.isNotEmpty) ...[
            AppSection.item(
              title: l10n.knowledgeDecisionExpectedOutcomeLabel,
              children: [Text(expected, style: context.bodyCaptionStyle)],
            ),
            const SizedBox(height: AppSpacing.s16),
          ],
          KnowledgeMarkdownEditor(
            controller: _actual,
            enabled: !_saving,
            label: l10n.knowledgeDecisionActualOutcomeLabel,
            minLines: 4,
            maxLines: 8,
            editorKey: const Key('knowledge-decision-review-actual'),
          ),
          const SizedBox(height: AppSpacing.s16),
          IgnorePointer(
            ignoring: _saving,
            child: AppAdaptiveChoice<DecisionStatus>(
              key: const Key('knowledge-decision-review-status'),
              title: l10n.knowledgeDecisionStatusLabel,
              options: _showDetails
                  ? DecisionStatus.values
                  : <DecisionStatus>{
                      DecisionStatus.active,
                      DecisionStatus.verified,
                      DecisionStatus.falsified,
                      _status,
                    }.toList(growable: false),
              value: _status,
              labelOf: (status) => knowledgeDecisionStatusLabel(l10n, status),
              iconOf: _statusIcon,
              onChanged: (status) {
                if (_saving) return;
                setState(() => _status = status);
                widget.dirty.markDirty();
              },
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          if (_needsNextDate) ...[
            Text(
              l10n.knowledgeReviewContinueObserving,
              style: context.captionLabelStyle,
            ),
            const SizedBox(height: AppSpacing.s8),
            Wrap(
              spacing: AppSpacing.s8,
              runSpacing: AppSpacing.s8,
              children: [
                for (final days in [7, 30])
                  AppFilterChip(
                    key: ValueKey('knowledge-review-next-$days'),
                    active: false,
                    label: days == 7
                        ? l10n.knowledgeReviewNextWeek
                        : l10n.knowledgeReviewNextMonth,
                    onPress: _saving
                        ? null
                        : () {
                            setState(() {
                              final now = DateTime.now();
                              _reviewDate = DateTime(
                                now.year,
                                now.month,
                                now.day + days,
                              ).toUtc();
                              _showDetails = true;
                              _validationError = null;
                            });
                            widget.dirty.markDirty();
                          },
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.s12),
          ],
          AppRevealControl(
            key: const Key('knowledge-decision-review-details'),
            expanded: _showDetails,
            collapsedLabel: l10n.knowledgeReviewShowDetails,
            expandedLabel: l10n.knowledgeReviewHideDetails,
            enabled: !_saving,
            onToggle: () => setState(() => _showDetails = !_showDetails),
          ),
          if (_showDetails) ...[
            if (!widget.schedule) ...[
              _dateField(),
              const SizedBox(height: AppSpacing.s16),
            ],
            FTextField(
              key: const Key('knowledge-decision-review-conditions'),
              control: FTextFieldControl.managed(controller: _conditions),
              enabled: !_saving,
              label: Text(l10n.knowledgeDecisionRevisitConditionsLabel),
              description: Text(
                l10n.knowledgeDecisionRevisitConditionsDescription,
              ),
              minLines: 2,
              maxLines: 5,
            ),
            const SizedBox(height: AppSpacing.s16),
          ],
          if (_validationError case final message?) ...[
            const SizedBox(height: AppSpacing.s12),
            AppStatusBanner(message: message, kind: AppStatusKind.error),
          ],
          if (submissionFailureMessage case final message?) ...[
            const SizedBox(height: AppSpacing.s12),
            AppStatusBanner(message: message, kind: AppStatusKind.error),
          ],
        ],
      ),
    );
  }

  Widget _dateField() => DateField(
    key: const ValueKey('knowledge-decision-review-date'),
    label: AppLocalizations.of(context).knowledgeDecisionReviewDateLabel,
    initialValue: _reviewDate,
    enabled: !_saving,
    onChanged: (value) {
      setState(() {
        _reviewDate = value;
        _validationError = null;
      });
      widget.dirty.markDirty();
    },
  );

  Future<void> _submit() async {
    if (_saving || _draft.matchesDecision(widget.decision)) return;
    final l10n = AppLocalizations.of(context);
    final draft = _draft;
    if (_pending &&
        (widget.schedule || _needsNextDate) &&
        (_reviewDate == null ||
            !_reviewDate!.toUtc().isAfter(DateTime.now().toUtc()))) {
      setState(() {
        _showDetails = true;
        _validationError = l10n.knowledgeReviewNextDateRequired;
      });
      return;
    }
    await submitForm<void>(
      dirty: widget.dirty,
      onBusyChanged: (busy) => setState(() => _saving = busy),
      commit: () => widget.onSave(draft),
      leave: () => Navigator.of(context).pop(draft),
      failureMessage: (error) => knowledgeEditFailureMessage(context, error),
      successMessage: l10n.commonSaved,
      tag: 'knowledge-decision-review',
    );
  }

  List<DecisionRevisitCondition> _parseConditions() {
    final prior = widget.decision.revisitConditions;
    final seen = <String>{};
    final result = <DecisionRevisitCondition>[];
    for (final raw in _conditions.text.split(RegExp(r'[\r\n]+'))) {
      final statement = raw.trim();
      if (statement.isEmpty || !seen.add(statement)) continue;
      DecisionRevisitCondition? existing;
      for (final condition in prior) {
        if (condition.statement == statement) {
          existing = condition;
          break;
        }
      }
      result.add(existing ?? DecisionRevisitCondition(statement: statement));
    }
    return result;
  }
}

String knowledgeDecisionStatusLabel(
  AppLocalizations l10n,
  DecisionStatus status,
) => switch (status) {
  DecisionStatus.draft => l10n.knowledgeDecisionStatusDraft,
  DecisionStatus.active => l10n.knowledgeDecisionStatusActive,
  DecisionStatus.paused => l10n.knowledgeDecisionStatusPaused,
  DecisionStatus.expired => l10n.knowledgeDecisionStatusExpired,
  DecisionStatus.verified => l10n.knowledgeDecisionStatusVerified,
  DecisionStatus.falsified => l10n.knowledgeDecisionStatusFalsified,
  DecisionStatus.superseded => l10n.knowledgeDecisionStatusSuperseded,
};

IconData _statusIcon(DecisionStatus status) => switch (status) {
  DecisionStatus.draft => FLucideIcons.filePenLine,
  DecisionStatus.active => FLucideIcons.play,
  DecisionStatus.paused => FLucideIcons.pause,
  DecisionStatus.expired => FLucideIcons.clockAlert,
  DecisionStatus.verified => FLucideIcons.badgeCheck,
  DecisionStatus.falsified => FLucideIcons.badgeX,
  DecisionStatus.superseded => FLucideIcons.replace,
};

String? _nullable(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Review a stored decision from either its detail page or the Inbox.
Future<bool> reviewSavedKnowledgeDecision({
  required BuildContext context,
  required WidgetRef ref,
  required KnowledgeDecision decision,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final draft = await showKnowledgeDecisionReviewSheet(
    context: context,
    decision: decision,
    schedule:
        decision.reviewDate == null ||
        decision.reviewDate!.toUtc().isAfter(DateTime.now().toUtc()),
    onSave: (draft) async {
      final service = await container.read(
        knowledgeDecisionReviewServiceProvider.future,
      );
      await service.review(baseline: decision, draft: draft);
    },
  );
  if (draft == null) return false;
  if (context.mounted) {
    ref.invalidate(knowledgeDecisionsProvider);
    ref.invalidate(knowledgeDueReviewsProvider);
  }
  if (draft.status != decision.status ||
      (draft.actualOutcomeMd?.trim() ?? '') !=
          (decision.actualOutcomeMd?.trim() ?? '')) {
    final elapsed = DateTime.now().toUtc().difference(
      decision.decidedAt.toUtc(),
    );
    await recordProductMetric(
      () => container.read(productMetricsProvider.notifier),
      ProductFunnelEvent.knowledgeDecisionReviewed,
      success: true,
      duration: elapsed.isNegative ? Duration.zero : elapsed,
    );
  }
  return true;
}
