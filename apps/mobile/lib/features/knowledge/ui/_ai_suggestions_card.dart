/// KnowledgeOS Review tab "AI 建议" card
/// (`docs/domains/knowledgeos-domain.md` §5 异步 triage flow + §14.2 P0).
///
/// Renders pending [InboxProposal] envelopes produced by
/// [InboxTriageAgent] grouped by note. Each envelope gets ✓ / ✗
/// buttons:
///
/// - ✓ → applies the payload via [KnowledgeInboxProposalApplier], then marks
///   the envelope `accepted` in the side-table.
/// - ✗ → marks the envelope `dismissed`; the agent's merge logic in
///   `_inbox_triage_support.persistEnvelope` then refuses to
///   re-propose the same kind for the same note.
///
/// The side-table is local-only / never-sync (§7), so all of this
/// stays on-device. No cross-domain ProposalApplier: inbox proposals are a
/// Knowledge-local review workflow, not chat proposal cards.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../composition/knowledge_inbox_proposal_applier.dart';
import '../composition/knowledge_route_paths.dart';
import '../data/inbox_triage_repository.dart';
import '../data/knowledge_repository.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '_widgets.dart';

/// Bumped on each accept / dismiss so the Review snapshot refetches.
/// Side-table writes don't hit Drift streams (raw SQL via
/// `customStatement`), so we need this explicit pulse to refresh the
/// list. Cheap and self-contained — no global state.
final aiSuggestionsRefreshProvider = StateProvider<int>((ref) => 0);

class KnowledgeAiSuggestionsCard extends StatelessWidget {
  const KnowledgeAiSuggestionsCard({
    super.key,
    required this.records,
    required this.notesById,
  });

  final List<InboxTriageRecord> records;
  final Map<String, KnowledgeNote?> notesById;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (records.isEmpty) return const SizedBox.shrink();
    final pendingCount = _pendingCount(records);
    return KnowledgeSection.group(
      title: l10n.knowledgeAiSuggestionsTitle,
      trailing: AppBadge(
        label: '$pendingCount',
        icon: FLucideIcons.sparkles,
        size: AppBadgeSize.compact,
        tone: AppBadgeTone.info,
      ),
      children: [
        for (final record in records)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s8),
            child: _NoteSuggestionGroup(
              record: record,
              note: notesById[record.noteId],
            ),
          ),
      ],
    );
  }

  static int _pendingCount(List<InboxTriageRecord> list) =>
      list.fold(0, (sum, rec) => sum + rec.pending.length);
}

class _NoteSuggestionGroup extends StatelessWidget {
  const _NoteSuggestionGroup({required this.record, required this.note});
  final InboxTriageRecord record;
  final KnowledgeNote? note;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (note == null) {
      return AppEmptyState.inline(
        icon: FLucideIcons.fileX,
        title: l10n.knowledgeNoteDeleted(record.noteId),
      );
    }
    final resolvedNote = note!;
    final pending = record.proposals.where((p) => p.status.isPending).toList();
    if (pending.isEmpty) {
      return AppEmptyState.inline(
        icon: FLucideIcons.sparkles,
        title: l10n.knowledgeAiSuggestionsEmpty,
      );
    }
    return KnowledgeSection.item(
      title: resolvedNote.title.isEmpty
          ? l10n.knowledgeUntitled
          : resolvedNote.title,
      trailing: AppBadge(
        label: l10n.knowledgeAiSuggestionCount(pending.length),
        size: AppBadgeSize.compact,
        tone: AppBadgeTone.neutral,
      ),
      children: [
        for (var index = 0; index < pending.length; index++) ...[
          if (index > 0) ...[
            const SizedBox(height: AppSpacing.s10),
            const AppDivider(horizontalPadding: AppSpacing.s0),
            const SizedBox(height: AppSpacing.s10),
          ],
          _ProposalRow(note: resolvedNote, proposal: pending[index]),
        ],
      ],
    );
  }
}

class _ProposalRow extends ConsumerStatefulWidget {
  const _ProposalRow({required this.note, required this.proposal});
  final KnowledgeNote note;
  final InboxProposal proposal;

  @override
  ConsumerState<_ProposalRow> createState() => _ProposalRowState();
}

class _ProposalRowState extends ConsumerState<_ProposalRow> {
  bool _busy = false;
  bool _expanded = false;

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final applier = await ref.read(
        knowledgeInboxProposalApplierProvider.future,
      );
      final triage = await ref.read(inboxTriageRepositoryProvider.future);
      final promoted = await applier.acceptAndResolve(
        note: widget.note,
        proposal: widget.proposal,
        triage: triage,
      );
      ref.read(aiSuggestionsRefreshProvider.notifier).state++;
      if (mounted) {
        final route = promoted == null
            ? null
            : promoted.kind == KnowledgeEntryKind.decision
            ? KnowledgeRoutes.decision(promoted.id)
            : KnowledgeRoutes.object(promoted.kind.name, promoted.id);
        final router = route == null ? null : GoRouter.of(context);
        AppMessenger.show(
          context,
          ToastKind.success,
          AppLocalizations.of(context).knowledgeAiSuggestionAppliedToast,
          actionLabel: route == null
              ? null
              : AppLocalizations.of(context).knowledgeAiSuggestionViewAction,
          onAction: route == null || router == null
              ? null
              : () => unawaited(router.push<Object?>(route)),
        );
      }
    } catch (error) {
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.error,
          AppLocalizations.of(
            context,
          ).knowledgeCaptureApplyFailed(userSafeErrorMessage(context, error)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _dismiss() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final container = ProviderScope.containerOf(context);
      final triage = await ref.read(inboxTriageRepositoryProvider.future);
      await triage.resolve(
        noteId: widget.note.id,
        kind: widget.proposal.kind,
        status: InboxProposalStatus.dismissed,
      );
      ref.read(aiSuggestionsRefreshProvider.notifier).state++;
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.success,
          AppLocalizations.of(context).knowledgeAiSuggestionDismissedToast,
          actionLabel: AppLocalizations.of(context).commonUndo,
          onAction: () => unawaited(
            _undoDismiss(
              triage: triage,
              container: container,
              noteId: widget.note.id,
              kind: widget.proposal.kind,
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.error,
          AppLocalizations.of(context).commonSaveFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _undoDismiss({
    required InboxTriageRepository triage,
    required ProviderContainer container,
    required String noteId,
    required InboxProposalKind kind,
  }) async {
    await triage.resolve(
      noteId: noteId,
      kind: kind,
      status: InboxProposalStatus.pending,
    );
    container.read(aiSuggestionsRefreshProvider.notifier).state++;
  }

  Future<void> _snooze() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final triage = await ref.read(inboxTriageRepositoryProvider.future);
      await triage.snooze(
        noteId: widget.note.id,
        kind: widget.proposal.kind,
        until: DateTime.now().toUtc().add(const Duration(days: 1)),
      );
      ref.read(aiSuggestionsRefreshProvider.notifier).state++;
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.success,
          AppLocalizations.of(context).knowledgeAiSuggestionSnoozedToast,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recordFeedback(InboxProposalFeedback feedback) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final triage = await ref.read(inboxTriageRepositoryProvider.future);
      await triage.recordFeedback(
        noteId: widget.note.id,
        kind: widget.proposal.kind,
        feedback: feedback,
      );
      ref.read(aiSuggestionsRefreshProvider.notifier).state++;
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.success,
          AppLocalizations.of(context).knowledgeAiSuggestionFeedbackToast,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppBadge(
              label: _proposalKindLabel(l10n, widget.proposal.kind),
              size: AppBadgeSize.compact,
              tone: AppBadgeTone.accent,
            ),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: Text(
                _proposalSummary(context, widget.proposal),
                style: context.theme.typography.body.sm,
                maxLines: _expanded ? 8 : 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s10),
        Wrap(
          spacing: AppSpacing.s8,
          runSpacing: AppSpacing.s6,
          children: [
            FButton(
              variant: FButtonVariant.primary,
              size: FButtonSizeVariant.sm,
              onPress: _busy ? null : _accept,
              prefix: const Icon(FLucideIcons.check, size: AppIconSizes.xs),
              child: Text(l10n.knowledgeAiSuggestionAccept),
            ),
            FButton(
              variant: FButtonVariant.outline,
              size: FButtonSizeVariant.sm,
              onPress: _busy
                  ? null
                  : () => setState(() => _expanded = !_expanded),
              prefix: Icon(
                _expanded ? FLucideIcons.chevronUp : FLucideIcons.list,
                size: AppIconSizes.xs,
              ),
              child: Text(
                _expanded
                    ? l10n.knowledgeAiSuggestionHideDetails
                    : l10n.knowledgeAiSuggestionDetails,
              ),
            ),
            AppAdaptiveActionMenu(
              title: l10n.knowledgeAiSuggestionMoreActions,
              actions: <AppAdaptiveAction>[
                AppAdaptiveAction(
                  icon: FLucideIcons.clock,
                  title: l10n.knowledgeAiSuggestionSnoozeOneDay,
                  onPress: _snooze,
                ),
                AppAdaptiveAction(
                  icon: FLucideIcons.x,
                  title: l10n.knowledgeAiSuggestionDismiss,
                  destructive: true,
                  onPress: _dismiss,
                ),
              ],
              triggerBuilder: (context, openMenu, focusNode) => Focus(
                focusNode: focusNode,
                child: AppIconButton(
                  icon: FLucideIcons.ellipsis,
                  tooltip: l10n.knowledgeAiSuggestionMoreActions,
                  onPress: _busy ? null : openMenu,
                  size: AppControlHeights.touchTarget,
                  iconSize: AppIconSizes.sm,
                ),
              ),
            ),
          ],
        ),
        AnimatedSwitcher(
          duration: AppMotionPolicy.duration(context, Motion.fast),
          child: _expanded
              ? Padding(
                  key: const ValueKey<String>('details'),
                  padding: const EdgeInsets.only(top: AppSpacing.s8),
                  child: _ProposalDetailsPanel(
                    proposal: widget.proposal,
                    busy: _busy,
                    onFeedback: _recordFeedback,
                  ),
                )
              : const SizedBox.shrink(key: ValueKey<String>('collapsed')),
        ),
      ],
    );
  }
}

String _proposalSummary(BuildContext context, InboxProposal proposal) {
  if (Localizations.localeOf(context).languageCode == 'zh') {
    return proposal.summaryZh;
  }
  final l10n = AppLocalizations.of(context);
  return switch (proposal.kind) {
    InboxProposalKind.classification =>
      l10n.knowledgeAiSuggestionClassificationSummary(
        _captureKindLabel(l10n, proposal.payload['kind']),
      ),
    InboxProposalKind.tags => l10n.knowledgeAiSuggestionTagsSummary(
      _formatPayloadValue(proposal.payload['tags']),
    ),
    InboxProposalKind.linkToDecision =>
      l10n.knowledgeAiSuggestionDecisionLinksSummary(
        proposal.payload['related_decision_ids'] is List
            ? (proposal.payload['related_decision_ids']! as List).length
            : 0,
      ),
  };
}

String _captureKindLabel(AppLocalizations l10n, Object? raw) => switch (raw) {
  'decision' => l10n.knowledgeCaptureKindDecision,
  'assumption' => l10n.knowledgeCaptureKindAssumption,
  'principle' => l10n.knowledgeCaptureKindPrinciple,
  'concept' => l10n.knowledgeCaptureKindConcept,
  'experiment' => l10n.knowledgeCaptureKindExperiment,
  'routine' => l10n.knowledgeCaptureKindRoutine,
  'note' || null => l10n.knowledgeCaptureKindNote,
  _ => _formatPayloadValue(raw),
};

String _proposalKindLabel(AppLocalizations l10n, InboxProposalKind kind) {
  return switch (kind) {
    InboxProposalKind.classification =>
      l10n.knowledgeAiSuggestionKindClassification,
    InboxProposalKind.tags => l10n.knowledgeAiSuggestionKindTags,
    InboxProposalKind.linkToDecision =>
      l10n.knowledgeAiSuggestionKindLinkToDecision,
  };
}

class _ProposalDetailsPanel extends StatelessWidget {
  const _ProposalDetailsPanel({
    required this.proposal,
    required this.busy,
    required this.onFeedback,
  });

  final InboxProposal proposal;
  final bool busy;
  final ValueChanged<InboxProposalFeedback> onFeedback;

  @override
  Widget build(BuildContext context) {
    final typography = context.theme.typography;
    final l10n = AppLocalizations.of(context);
    final entries = proposal.payload.entries
        .where((entry) => entry.value != null)
        .toList(growable: false);
    return SoftCard.flat(
      padding: const EdgeInsets.all(AppSpacing.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${l10n.knowledgeAiSuggestionPayloadTitle} · '
            '${_proposalKindLabel(l10n, proposal.kind)}',
            style: context.captionLabelStyle,
          ),
          if (entries.isNotEmpty) const SizedBox(height: AppSpacing.s6),
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: AppControlWidths.payloadKey,
                    child: Text(
                      _proposalPayloadLabel(l10n, entry.key),
                      style: context.captionStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  Expanded(
                    child: Text(
                      _formatPayloadValue(entry.value),
                      style: typography.body.xs,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          if (entries.isNotEmpty) const SizedBox(height: AppSpacing.s8),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.knowledgeAiSuggestionFeedbackLabel,
                  style: context.captionStyle,
                ),
              ),
              SizedBox(
                width: AppControlWidths.feedbackSegmented,
                child: SegmentedRow<InboxProposalFeedback?>(
                  options: const <InboxProposalFeedback?>[
                    InboxProposalFeedback.positive,
                    InboxProposalFeedback.negative,
                  ],
                  value: proposal.feedback,
                  labelOf: (feedback) =>
                      feedback == InboxProposalFeedback.positive
                      ? l10n.knowledgeAiSuggestionFeedbackGood
                      : l10n.knowledgeAiSuggestionFeedbackBad,
                  iconOf: (feedback) =>
                      feedback == InboxProposalFeedback.positive
                      ? FLucideIcons.thumbsUp
                      : FLucideIcons.thumbsDown,
                  onChanged: busy
                      ? (_) {}
                      : (feedback) {
                          if (feedback != null) onFeedback(feedback);
                        },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _proposalPayloadLabel(AppLocalizations l10n, String key) =>
    switch (key) {
      'kind' || 'detected_kind' => l10n.knowledgeProposalRowType,
      'tags' => l10n.knowledgeAiSuggestionFieldTags,
      'project_tag' => l10n.knowledgeDetailProjectLabel,
      'related_decision_ids' => l10n.knowledgeAiSuggestionFieldDecisions,
      'decision_options' => l10n.knowledgeDecisionOptionsLabel,
      'expected_outcome' => l10n.knowledgeDecisionExpectedOutcomeLabel,
      'confidence' => l10n.knowledgeProposalRowConfidence,
      'reason' || 'reason_zh' => l10n.knowledgeWriterRationaleMarkdownLabel,
      _ => key,
    };

String _formatPayloadValue(Object? value) {
  if (value == null) return '';
  if (value is List) {
    return value.map(_formatPayloadValue).where((s) => s.isNotEmpty).join(', ');
  }
  if (value is Map) {
    return value.entries
        .map((entry) => '${entry.key}: ${_formatPayloadValue(entry.value)}')
        .join(', ');
  }
  return '$value';
}

extension on InboxProposalStatus {
  bool get isPending => this == InboxProposalStatus.pending;
}
