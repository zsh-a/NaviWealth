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
        if (!ownerSnap.hasData) return const SizedBox.shrink();
        final owner = ownerSnap.data!;
        final triageAsync = ref.watch(inboxTriageRepositoryProvider);
        return triageAsync.when(
          // loading: intentionally empty — the card only appears when triage
          // proposals are pending; a skeleton would flash for a section that
          // is usually hidden ("empty triage does not occupy Review chrome").
          loading: () => const SizedBox.shrink(),
          error: (e, stackTrace) => KnowledgeSection.group(
            title: l10n.knowledgeAiSuggestionsTitle,
            children: [
              KnowledgeErrorState(
                title: userSafeErrorMessage(
                  context,
                  e,
                  stackTrace: stackTrace,
                  operation: 'load knowledge AI suggestions',
                ),
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
              // Signal only — empty triage does not occupy Review chrome.
              if (list.isEmpty) return const SizedBox.shrink();
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
    return KnowledgeSection.item(
      title: note.title.isEmpty ? l10n.knowledgeUntitled : note.title,
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
          _ProposalRow(note: note, proposal: pending[index]),
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
        AppMessenger.show(
          context,
          ToastKind.success,
          AppLocalizations.of(context).knowledgeAiSuggestionAppliedToast,
        );
        if (promoted != null) {
          final route = promoted.kind == KnowledgeEntryKind.decision
              ? KnowledgeRoutes.decision(promoted.id)
              : KnowledgeRoutes.object(promoted.kind.name, promoted.id);
          unawaited(context.push<Object?>(route));
        }
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
                widget.proposal.summaryZh,
                style: context.theme.typography.body.sm.copyWith(height: 1.4),
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
              onPress: _busy ? null : _dismiss,
              prefix: const Icon(FLucideIcons.x, size: AppIconSizes.xs),
              child: Text(l10n.knowledgeAiSuggestionDismiss),
            ),
            FButton(
              variant: FButtonVariant.ghost,
              size: FButtonSizeVariant.sm,
              onPress: _busy ? null : _snooze,
              prefix: const Icon(FLucideIcons.clock, size: AppIconSizes.xs),
              child: Text(l10n.knowledgeAiSuggestionSnoozeOneDay),
            ),
            FButton(
              variant: FButtonVariant.ghost,
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
