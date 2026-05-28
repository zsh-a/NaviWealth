/// KnowledgeOS Library tab (`docs/knowledgeos-domain.md` §5).
///
/// 4 segments: Decisions / Notes / Concepts / Experiments. Decisions
/// surface a status badge per the 7-state lifecycle in §9. Forui-only
/// — no Material widgets so the page renders correctly inside any
/// scope without a Material ancestor.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/sync/mutation_context.dart';
import '../../../design_system/design_system.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '_segmented_row.dart';

enum _LibrarySegment { decisions, notes, concepts, experiments }

class KnowledgeLibraryPage extends ConsumerStatefulWidget {
  const KnowledgeLibraryPage({super.key});

  @override
  ConsumerState<KnowledgeLibraryPage> createState() =>
      _KnowledgeLibraryPageState();
}

class _KnowledgeLibraryPageState extends ConsumerState<KnowledgeLibraryPage> {
  _LibrarySegment _segment = _LibrarySegment.decisions;

  @override
  Widget build(BuildContext context) {
    return FScaffold(
      header: const FHeader.nested(title: Text('Library · KnowledgeOS')),
      childPad: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.s16,
          AppSpacing.s8,
          AppSpacing.s16,
          AppSpacing.s16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KnowledgeSegmentedRow<_LibrarySegment>(
              options: _LibrarySegment.values,
              value: _segment,
              labelOf: (s) => switch (s) {
                _LibrarySegment.decisions => 'Decisions',
                _LibrarySegment.notes => 'Notes',
                _LibrarySegment.concepts => 'Concepts',
                _LibrarySegment.experiments => 'Experiments',
              },
              onChanged: (s) => setState(() => _segment = s),
            ),
            const SizedBox(height: AppSpacing.s16),
            Expanded(child: _LibraryList(segment: _segment)),
          ],
        ),
      ),
    );
  }
}

class _LibraryList extends ConsumerWidget {
  const _LibraryList({required this.segment});
  final _LibrarySegment segment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<String>(
      future: ref.watch(currentUserIdProvider)(),
      builder: (context, ownerSnap) {
        if (!ownerSnap.hasData) {
          return const Center(child: FProgress());
        }
        final owner = ownerSnap.data!;
        final repoAsync = ref.watch(knowledgeRepositoryProvider);
        return repoAsync.when(
          loading: () => const Center(child: FProgress()),
          error: (e, _) => Text('加载失败:$e'),
          data: (repo) => switch (segment) {
            _LibrarySegment.decisions => _DecisionsList(
              stream: repo.watchDecisions(ownerUserId: owner),
            ),
            _LibrarySegment.notes => _NotesList(
              stream: repo.watchNotes(ownerUserId: owner),
            ),
            _LibrarySegment.concepts => _ConceptsList(
              stream: repo.watchConcepts(ownerUserId: owner),
            ),
            _LibrarySegment.experiments => _ExperimentsList(
              stream: repo.watchExperiments(ownerUserId: owner),
            ),
          },
        );
      },
    );
  }
}

class _DecisionsList extends StatelessWidget {
  const _DecisionsList({required this.stream});
  final Stream<List<KnowledgeDecision>> stream;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<KnowledgeDecision>>(
      stream: stream,
      builder: (context, snap) {
        final items = snap.data ?? const <KnowledgeDecision>[];
        if (items.isEmpty) return const _Empty(label: '还没有决策记录');
        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s8),
          itemBuilder: (context, i) {
            final d = items[i];
            final typography = context.theme.typography;
            final colors = context.theme.colors;
            return SoftCard(
              padding: const EdgeInsets.all(AppSpacing.s12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          d.question,
                          style: typography.md.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s8),
                      _StatusBadge(label: d.status.wire),
                    ],
                  ),
                  if (d.selectedLabel.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.s4),
                    Text(
                      d.selectedLabel,
                      style: typography.sm.copyWith(color: colors.primary),
                    ),
                  ],
                  if (d.rationaleMd.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.s4),
                    Text(
                      d.rationaleMd.length > 200
                          ? '${d.rationaleMd.substring(0, 200)}…'
                          : d.rationaleMd,
                      style: typography.sm
                          .copyWith(color: colors.mutedForeground),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _NotesList extends StatelessWidget {
  const _NotesList({required this.stream});
  final Stream<List<KnowledgeNote>> stream;
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<KnowledgeNote>>(
      stream: stream,
      builder: (context, snap) {
        final items = snap.data ?? const <KnowledgeNote>[];
        if (items.isEmpty) return const _Empty(label: 'Library 里还没有笔记');
        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s8),
          itemBuilder: (context, i) {
            final n = items[i];
            final typography = context.theme.typography;
            final colors = context.theme.colors;
            return SoftCard(
              padding: const EdgeInsets.all(AppSpacing.s12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    n.title.isEmpty ? '(untitled)' : n.title,
                    style: typography.md
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (n.bodyMd.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.s4),
                    Text(
                      n.bodyMd.length > 200
                          ? '${n.bodyMd.substring(0, 200)}…'
                          : n.bodyMd,
                      style: typography.sm
                          .copyWith(color: colors.mutedForeground),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _ConceptsList extends StatelessWidget {
  const _ConceptsList({required this.stream});
  final Stream<List<KnowledgeConcept>> stream;
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<KnowledgeConcept>>(
      stream: stream,
      builder: (context, snap) {
        final items = snap.data ?? const <KnowledgeConcept>[];
        if (items.isEmpty) return const _Empty(label: '还没有 concept 节点');
        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s8),
          itemBuilder: (context, i) {
            final c = items[i];
            final typography = context.theme.typography;
            final colors = context.theme.colors;
            return SoftCard(
              padding: const EdgeInsets.all(AppSpacing.s12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.name,
                    style: typography.md
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (c.summaryMd.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.s4),
                    Text(
                      c.summaryMd.length > 200
                          ? '${c.summaryMd.substring(0, 200)}…'
                          : c.summaryMd,
                      style: typography.sm
                          .copyWith(color: colors.mutedForeground),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _ExperimentsList extends StatelessWidget {
  const _ExperimentsList({required this.stream});
  final Stream<List<KnowledgeExperiment>> stream;
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<KnowledgeExperiment>>(
      stream: stream,
      builder: (context, snap) {
        final items = snap.data ?? const <KnowledgeExperiment>[];
        if (items.isEmpty) return const _Empty(label: '没有进行中的 experiment');
        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s8),
          itemBuilder: (context, i) {
            final e = items[i];
            final typography = context.theme.typography;
            return SoftCard(
              padding: const EdgeInsets.all(AppSpacing.s12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      e.hypothesis,
                      style: typography.md
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  _StatusBadge(label: e.status.wire),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Center(
      child: Text(
        label,
        style: context.theme.typography.sm
            .copyWith(color: colors.mutedForeground),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: colors.muted,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        label,
        style: context.theme.typography.xs
            .copyWith(color: colors.mutedForeground),
      ),
    );
  }
}
