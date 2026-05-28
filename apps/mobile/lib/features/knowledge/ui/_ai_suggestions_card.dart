/// KnowledgeOS Review tab "AI 建议" card
/// (`docs/knowledgeos-domain.md` §5 异步 triage flow + §14.2 P0).
///
/// Renders pending [InboxProposal] envelopes produced by
/// [InboxTriageAgent] grouped by note. Each envelope gets ✓ / ✗
/// buttons:
///
/// - ✓ → applies the payload via `KnowledgeRepository.upsertNote`
///   (tag merge / `kind:*` / `decision:<id>` soft links), then marks
///   the envelope `accepted` in the side-table.
/// - ✗ → marks the envelope `dismissed`; the agent's merge logic in
///   `_inbox_triage_support.persistEnvelope` then refuses to
///   re-propose the same kind for the same note.
///
/// The side-table is local-only / never-sync (§7), so all of this
/// stays on-device. No ProposalApplier yet — the apply paths here are
/// tiny and inlining is honest about the MVP shape.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:forui/forui.dart';

import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../../../design_system/design_system.dart';
import '../data/inbox_triage_repository.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';

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
    return FutureBuilder<String>(
      future: ref.watch(currentUserIdProvider)(),
      builder: (context, ownerSnap) {
        if (!ownerSnap.hasData) return const SizedBox.shrink();
        final owner = ownerSnap.data!;
        final triageAsync = ref.watch(inboxTriageRepositoryProvider);
        return triageAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (e, _) => _Shell(
            title: 'AI 建议',
            children: [Text('加载失败:$e')],
          ),
          data: (triage) => FutureBuilder<List<InboxTriageRecord>>(
            // `tick` ensures invalidate-after-resolve refetches.
            future: triage.listPending(ownerUserId: owner),
            key: ValueKey<int>(tick),
            builder: (context, snap) {
              final list = snap.data ?? const <InboxTriageRecord>[];
              if (list.isEmpty) {
                final typography = context.theme.typography;
                final colors = context.theme.colors;
                return _Shell(
                  title: 'AI 建议',
                  children: [
                    Text(
                      '当前无待处理的 AI 建议。新写的 note 会在 15 分钟内被 triage。',
                      style: typography.sm
                          .copyWith(color: colors.mutedForeground),
                    ),
                  ],
                );
              }
              return _Shell(
                title: 'AI 建议 (${_pendingCount(list)})',
                children: [
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

class _NoteSuggestionGroupState
    extends ConsumerState<_NoteSuggestionGroup> {
  KnowledgeNote? _note;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadNote();
  }

  Future<void> _loadNote() async {
    final repo = await ref.read(knowledgeRepositoryProvider.future);
    final note = await repo.findNote(widget.record.noteId);
    if (mounted) {
      setState(() {
        _note = note;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final typography = context.theme.typography;
    final colors = context.theme.colors;
    if (_loading) return const SizedBox.shrink();
    final note = _note;
    if (note == null) {
      return Text(
        'note ${widget.record.noteId} 已删除',
        style: typography.xs.copyWith(color: colors.mutedForeground),
      );
    }
    final pending =
        widget.record.proposals.where((p) => p.status.isPending).toList();
    if (pending.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s8),
      decoration: BoxDecoration(
        color: colors.muted,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            note.title.isEmpty ? '(untitled)' : note.title,
            style: typography.sm.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.s4),
          for (final p in pending)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
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

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _applyAccept(ref, widget.note, widget.proposal);
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

  @override
  Widget build(BuildContext context) {
    final typography = context.theme.typography;
    final colors = context.theme.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            widget.proposal.summaryZh,
            style: typography.sm.copyWith(color: colors.mutedForeground),
          ),
        ),
        const SizedBox(width: AppSpacing.s8),
        FButton.icon(
          variant: FButtonVariant.outline,
          onPress: _busy ? null : _accept,
          child: const Icon(FLucideIcons.check, size: 14),
        ),
        const SizedBox(width: AppSpacing.s4),
        FButton.icon(
          variant: FButtonVariant.outline,
          onPress: _busy ? null : _dismiss,
          child: const Icon(FLucideIcons.x, size: 14),
        ),
      ],
    );
  }
}

extension on InboxProposalStatus {
  bool get isPending => this == InboxProposalStatus.pending;
}

/// Accept dispatch — per-kind: builds an updated [KnowledgeNote] and
/// upserts it. Each kind reduces to "merge into note.tags / project_tag"
/// so we don't need a new schema column or a ProposalApplier yet.
Future<void> _applyAccept(
  WidgetRef ref,
  KnowledgeNote note,
  InboxProposal proposal,
) async {
  final repo = await ref.read(knowledgeRepositoryProvider.future);
  final stamper = await ref.read(mutationStamperProvider.future);
  final stamp = await stamper.stamp();

  final tagSet = note.tags.toSet();
  String? projectTag = note.projectTag;

  switch (proposal.kind) {
    case InboxProposalKind.classification:
      final kind = proposal.payload['kind'] as String?;
      if (kind == null || kind.isEmpty) return;
      tagSet.add('kind:$kind');
    case InboxProposalKind.tags:
      final raw = proposal.payload['tags'];
      if (raw is List) {
        for (final t in raw.whereType<String>()) {
          final lower = t.trim().toLowerCase();
          if (lower.isNotEmpty) tagSet.add(lower);
        }
      }
      final pt = proposal.payload['project_tag'];
      if (pt is String && pt.trim().isNotEmpty) {
        projectTag = pt.trim();
      }
    case InboxProposalKind.linkToDecision:
      final raw = proposal.payload['related_decision_ids'];
      if (raw is List) {
        for (final id in raw.whereType<String>()) {
          final trimmed = id.trim();
          if (trimmed.isNotEmpty) tagSet.add('decision:$trimmed');
        }
      }
  }

  final updated = KnowledgeNote(
    id: note.id,
    title: note.title,
    bodyMd: note.bodyMd,
    sourceUrl: note.sourceUrl,
    tags: tagSet.toList(growable: false),
    projectTag: projectTag,
    createdAt: note.createdAt,
    sync: SyncMeta(
      ownerUserId: stamp.ownerUserId,
      updatedAt: stamp.now,
      updatedByDevice: stamp.deviceId,
      hlc: stamp.hlc,
    ),
  );
  await repo.upsertNote(updated);
}

class _Shell extends StatelessWidget {
  const _Shell({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final typography = context.theme.typography;
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: typography.md.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.s8),
          ...children,
        ],
      ),
    );
  }
}
