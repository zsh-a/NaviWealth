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

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../composition/knowledge_inbox_proposal_applier.dart';
import '../data/inbox_triage_repository.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '_widgets.dart';

/// Bumped on each accept / dismiss so the parent FutureBuilder refetches.
/// Side-table writes don't hit Drift streams (raw SQL via
/// `customStatement`), so we need this explicit pulse to refresh the
/// list. Cheap and self-contained — no global state.
final aiSuggestionsRefreshProvider = StateProvider<int>((ref) => 0);

class KnowledgeAiSuggestionsCard extends ConsumerWidget {
  const KnowledgeAiSuggestionsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tick = ref.watch(aiSuggestionsRefreshProvider);
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<String>(
      future: ref.watch(knowledgeOwnerUserIdProvider.future),
      builder: (context, ownerSnap) {
        if (!ownerSnap.hasData) {
          return KnowledgeSection.group(
            title: l10n.knowledgeAiSuggestionsTitle,
            children: const [
              KnowledgeLoadingState(density: KnowledgeStateDensity.section),
            ],
          );
        }
        final owner = ownerSnap.data!;
        final triageAsync = ref.watch(inboxTriageRepositoryProvider);
        return triageAsync.when(
          loading: () => KnowledgeSection.group(
            title: l10n.knowledgeAiSuggestionsTitle,
            children: const [
              KnowledgeLoadingState(density: KnowledgeStateDensity.section),
            ],
          ),
          error: (e, _) => KnowledgeSection.group(
            title: l10n.knowledgeAiSuggestionsTitle,
            children: [
              KnowledgeErrorState(
                title: l10n.knowledgeLoadFailed('$e'),
                onRetry: () => ref.invalidate(inboxTriageRepositoryProvider),
                density: KnowledgeStateDensity.section,
              ),
            ],
          ),
          data: (triage) => FutureBuilder<List<InboxTriageRecord>>(
            // `tick` ensures invalidate-after-resolve refetches.
            future: triage.listPending(ownerUserId: owner),
            key: ValueKey<int>(tick),
            builder: (context, snap) {
              if (snap.hasError) {
                return KnowledgeSection.group(
                  title: l10n.knowledgeAiSuggestionsTitle,
                  children: [
                    KnowledgeErrorState(
                      title: userSafeErrorMessage(
                        context,
                        snap.error!,
                        stackTrace: snap.stackTrace,
                        operation: 'load knowledge AI suggestions',
                      ),
                      density: KnowledgeStateDensity.section,
                    ),
                  ],
                );
              }
              final list = (snap.data ?? const <InboxTriageRecord>[])
                  .where((record) => record.pending.isNotEmpty)
                  .toList(growable: false);
              if (list.isEmpty) {
                return KnowledgeSection.group(
                  title: l10n.knowledgeAiSuggestionsTitle,
                  children: [
                    KnowledgeEmptyState(
                      icon: FLucideIcons.sparkles,
                      title: l10n.knowledgeAiSuggestionsEmpty,
                      density: KnowledgeStateDensity.section,
                    ),
                  ],
                );
              }
              final pendingCount = _pendingCount(list);
              return KnowledgeSection.group(
                title: l10n.knowledgeAiSuggestionsTitle,
                trailing: AppBadge(
                  label: '$pendingCount',
                  icon: FLucideIcons.sparkles,
                  size: AppBadgeSize.compact,
                  tone: AppBadgeTone.info,
                ),
                children: [
                  Text(
                    l10n.knowledgeAiSuggestionsSubtitle(pendingCount),
                    style: context.captionStyle,
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  for (final rec in list)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.s8),
                      child: _NoteSuggestionGroup(record: rec),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  static int _pendingCount(List<InboxTriageRecord> list) =>
      list.fold(0, (sum, rec) => sum + rec.pending.length);
}

class _NoteSuggestionGroup extends ConsumerStatefulWidget {
  const _NoteSuggestionGroup({required this.record});
  final InboxTriageRecord record;

  @override
  ConsumerState<_NoteSuggestionGroup> createState() =>
      _NoteSuggestionGroupState();
}

class _NoteSuggestionGroupState extends ConsumerState<_NoteSuggestionGroup> {
  KnowledgeNote? _note;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadNote();
  }

  Future<void> _loadNote() async {
    final repo = await ref.read(knowledgeRepositoryProvider.future);
    final note = await repo.findNote(
      ownerUserId: widget.record.ownerUserId,
      id: widget.record.noteId,
    );
    if (mounted) {
      setState(() {
        _note = note;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    if (_loading) {
      return const KnowledgeLoadingState(
        density: KnowledgeStateDensity.section,
      );
    }
    final note = _note;
    if (note == null) {
      return KnowledgeEmptyState(
        icon: FLucideIcons.fileX,
        title: l10n.knowledgeNoteDeleted(widget.record.noteId),
        density: KnowledgeStateDensity.section,
      );
    }
    final pending = widget.record.proposals
        .where((p) => p.status.isPending)
        .toList();
    if (pending.isEmpty) {
      return KnowledgeEmptyState(
        icon: FLucideIcons.sparkles,
        title: l10n.knowledgeAiSuggestionsEmpty,
        density: KnowledgeStateDensity.section,
      );
    }
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s8),
      decoration: BoxDecoration(
        color: colors.muted.withValues(alpha: AppOpacity.subtle),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  note.title.isEmpty ? l10n.knowledgeUntitled : note.title,
                  style: context.labelStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              AppBadge(
                label: l10n.knowledgeAiSuggestionCount(pending.length),
                size: AppBadgeSize.compact,
                tone: AppBadgeTone.neutral,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s4),
          for (final p in pending)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
              child: _ProposalRow(note: note, proposal: p),
            ),
        ],
      ),
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
      await applier.accept(note: widget.note, proposal: widget.proposal);
      final triage = await ref.read(inboxTriageRepositoryProvider.future);
      await triage.resolve(
        noteId: widget.note.id,
        kind: widget.proposal.kind,
        status: InboxProposalStatus.accepted,
      );
      ref.read(aiSuggestionsRefreshProvider.notifier).state++;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _dismiss() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final triage = await ref.read(inboxTriageRepositoryProvider.future);
      await triage.resolve(
        noteId: widget.note.id,
        kind: widget.proposal.kind,
        status: InboxProposalStatus.dismissed,
      );
      ref.read(aiSuggestionsRefreshProvider.notifier).state++;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AppBadge(
              label: _proposalKindLabel(l10n, widget.proposal.kind),
              size: AppBadgeSize.compact,
              tone: AppBadgeTone.accent,
            ),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: Text(
                widget.proposal.summaryZh,
                style: context.bodyCaptionStyle,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            FTooltip(
              tipBuilder: (_, _) => Text(
                _expanded
                    ? l10n.knowledgeAiSuggestionHideDetails
                    : l10n.knowledgeAiSuggestionDetails,
              ),
              child: FButton.icon(
                variant: FButtonVariant.ghost,
                onPress: _busy
                    ? null
                    : () => setState(() => _expanded = !_expanded),
                child: Icon(
                  _expanded ? FLucideIcons.chevronUp : FLucideIcons.list,
                  size: AppIconSizes.xs,
                  color: colors.mutedForeground,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.s2),
            FTooltip(
              tipBuilder: (_, _) =>
                  Text(l10n.knowledgeAiSuggestionSnoozeOneDay),
              child: FButton.icon(
                variant: FButtonVariant.ghost,
                onPress: _busy ? null : _snooze,
                child: Icon(
                  FLucideIcons.clock,
                  size: AppIconSizes.xs,
                  color: colors.mutedForeground,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.s2),
            FTooltip(
              tipBuilder: (_, _) => Text(l10n.knowledgeAiSuggestionAccept),
              child: FButton.icon(
                variant: FButtonVariant.ghost,
                onPress: _busy ? null : _accept,
                child: Icon(
                  FLucideIcons.check,
                  size: AppIconSizes.xs,
                  color: colors.primary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.s2),
            FTooltip(
              tipBuilder: (_, _) => Text(l10n.knowledgeAiSuggestionDismiss),
              child: FButton.icon(
                variant: FButtonVariant.ghost,
                onPress: _busy ? null : _dismiss,
                child: Icon(
                  FLucideIcons.x,
                  size: AppIconSizes.xs,
                  color: colors.mutedForeground,
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
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    final entries = proposal.payload.entries
        .where((entry) => entry.value != null)
        .toList(growable: false);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s8),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${l10n.knowledgeAiSuggestionPayloadTitle} · ${proposal.kind.wire}',
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
                      entry.key,
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
