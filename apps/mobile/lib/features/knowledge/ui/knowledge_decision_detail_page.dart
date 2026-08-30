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
import 'knowledge_rewrite_sheet.dart';
import 'widgets/knowledge_markdown_editor.dart';

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
        TextField(
          controller: _question,
          decoration: InputDecoration(
            labelText: l10n.knowledgeDecisionQuestionLabel,
          ),
        ),
        const SizedBox(height: AppSpacing.s12),
        TextField(
          controller: _selected,
          decoration: InputDecoration(
            labelText: l10n.knowledgeDecisionOptionsLabel,
          ),
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
        TextField(
          controller: _expected,
          decoration: InputDecoration(
            labelText: l10n.knowledgeDecisionExpectedOutcomeLabel,
          ),
        ),
        const SizedBox(height: AppSpacing.s12),
        KnowledgeMarkdownEditor(
          controller: _actual,
          label: l10n.knowledgeDecisionActualOutcomeLabel,
          minLines: 2,
          enabled: !_saving,
        ),
        const SizedBox(height: AppSpacing.s12),
        DropdownButtonFormField<DecisionStatus>(
          initialValue: _status,
          decoration: InputDecoration(
            labelText: l10n.knowledgeDecisionStatusLabel,
          ),
          items: DecisionStatus.values
              .map(
                (status) => DropdownMenuItem<DecisionStatus>(
                  value: status,
                  child: Text(status.name),
                ),
              )
              .toList(growable: false),
          onChanged: _saving
              ? null
              : (value) => setState(() => _status = value ?? _status),
        ),
        const SizedBox(height: AppSpacing.s20),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? l10n.commonSaving : l10n.commonSave),
        ),
        const SizedBox(height: AppSpacing.s8),
        TextButton(
          onPressed: _saving ? null : _delete,
          child: Text(l10n.commonDelete),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final question = _question.text.trim();
    final selected = _selected.text.trim();
    if (question.isEmpty || selected.isEmpty) return;
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
          reviewDate: widget.decision.reviewDate,
          revisitConditions: widget.decision.revisitConditions,
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
    } finally {
      if (mounted) setState(() => _saving = false);
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
    final service = await ref.read(knowledgeDeletionServiceProvider.future);
    await service.delete(
      kind: KnowledgeEntryKind.decision,
      id: widget.decision.id,
    );
    ref.invalidate(knowledgeDecisionsProvider);
    if (mounted) context.pop();
  }
}

String? _nullable(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
