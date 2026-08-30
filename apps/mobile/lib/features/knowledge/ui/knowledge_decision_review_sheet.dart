import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../core/forms/forms.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/knowledge_models.dart';
import 'widgets/knowledge_markdown_editor.dart';

class KnowledgeDecisionReviewDraft {
  const KnowledgeDecisionReviewDraft({
    required this.reviewDate,
    required this.revisitConditions,
    required this.actualOutcomeMd,
    required this.status,
  });

  final DateTime? reviewDate;
  final List<DecisionRevisitCondition> revisitConditions;
  final String? actualOutcomeMd;
  final DecisionStatus status;
}

Future<KnowledgeDecisionReviewDraft?> showKnowledgeDecisionReviewSheet({
  required BuildContext context,
  required KnowledgeDecision decision,
}) {
  return showAppFormSheet<KnowledgeDecisionReviewDraft>(
    context: context,
    builder: (_) => _KnowledgeDecisionReviewSheet(decision: decision),
  );
}

class _KnowledgeDecisionReviewSheet extends StatefulWidget {
  const _KnowledgeDecisionReviewSheet({required this.decision});

  final KnowledgeDecision decision;

  @override
  State<_KnowledgeDecisionReviewSheet> createState() =>
      _KnowledgeDecisionReviewSheetState();
}

class _KnowledgeDecisionReviewSheetState
    extends State<_KnowledgeDecisionReviewSheet> {
  late final TextEditingController _conditions;
  late final TextEditingController _actual;
  late DateTime? _reviewDate;
  late DecisionStatus _status;

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
      title: l10n.knowledgeDecisionReviewTitle,
      subtitle: widget.decision.question,
      footer: AppSheetFooter(
        submitKey: const Key('knowledge-decision-review-submit'),
        submitLabel: l10n.knowledgeDecisionReviewSaveAction,
        cancelLabel: l10n.commonCancel,
        onSubmit: _submit,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (expected != null && expected.isNotEmpty) ...[
            AppSection.item(
              title: l10n.knowledgeDecisionExpectedOutcomeLabel,
              children: [Text(expected, style: context.bodyCaptionStyle)],
            ),
            const SizedBox(height: AppSpacing.s16),
          ],
          DateField(
            key: const Key('knowledge-decision-review-date'),
            label: l10n.knowledgeDecisionReviewDateLabel,
            initialValue: _reviewDate,
            onChanged: (value) => setState(() => _reviewDate = value),
          ),
          const SizedBox(height: AppSpacing.s16),
          FTextField(
            key: const Key('knowledge-decision-review-conditions'),
            control: FTextFieldControl.managed(controller: _conditions),
            label: Text(l10n.knowledgeDecisionRevisitConditionsLabel),
            description: Text(
              l10n.knowledgeDecisionRevisitConditionsDescription,
            ),
            minLines: 2,
            maxLines: 5,
          ),
          const SizedBox(height: AppSpacing.s16),
          KnowledgeMarkdownEditor(
            controller: _actual,
            label: l10n.knowledgeDecisionActualOutcomeLabel,
            minLines: 4,
            maxLines: 8,
            editorKey: const Key('knowledge-decision-review-actual'),
          ),
          const SizedBox(height: AppSpacing.s16),
          AppAdaptiveChoice<DecisionStatus>(
            key: const Key('knowledge-decision-review-status'),
            title: l10n.knowledgeDecisionStatusLabel,
            options: DecisionStatus.values,
            value: _status,
            labelOf: (status) => knowledgeDecisionStatusLabel(l10n, status),
            iconOf: _statusIcon,
            onChanged: (status) => setState(() => _status = status),
          ),
        ],
      ),
    );
  }

  void _submit() {
    Navigator.of(context).pop(
      KnowledgeDecisionReviewDraft(
        reviewDate: _reviewDate,
        revisitConditions: _parseConditions(),
        actualOutcomeMd: _nullable(_actual.text),
        status: _status,
      ),
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
