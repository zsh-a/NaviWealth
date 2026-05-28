/// KnowledgeOS Library tab (`docs/knowledgeos-domain.md` §5).
///
/// 4 segments: Decisions / Notes / Concepts / Experiments. Decisions
/// surface a status badge per the 7-state lifecycle in §9. Forui-only
/// — no Material widgets so the page renders correctly inside any
/// scope without a Material ancestor.
library;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../core/sync/mutation_context.dart';
import '../../../design_system/design_system.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '_decision_writer.dart';
import '_object_writers.dart';
import '_segmented_row.dart';
import '_widgets.dart';

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
      child: Stack(
        children: [
          Positioned.fill(
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
          ),
          Positioned(
            right: AppSpacing.s16,
            bottom: AppSpacing.s16,
            child: _NewObjectButton(segment: _segment),
          ),
        ],
      ),
    );
  }
}

/// FAB-style button that opens the right writer for the current
/// segment. The Decision tab additionally surfaces Principle /
/// Assumption shortcuts in an action sheet so the Library tab can
/// reach every write path without 4 separate FABs.
class _NewObjectButton extends ConsumerWidget {
  const _NewObjectButton({required this.segment});
  final _LibrarySegment segment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = switch (segment) {
      _LibrarySegment.decisions => 'New decision',
      _LibrarySegment.notes => 'New note',
      _LibrarySegment.concepts => 'New concept',
      _LibrarySegment.experiments => 'New experiment',
    };
    return FButton(
      prefix: const Icon(FLucideIcons.plus, size: 16),
      onPress: () => _onPress(context, ref),
      child: Text(label),
    );
  }

  Future<void> _onPress(BuildContext context, WidgetRef ref) async {
    switch (segment) {
      case _LibrarySegment.decisions:
        // The Decision segment doubles as the home for Principle /
        // Assumption writers — they share authoring flow with Decision
        // (assumptions are referenced from decisions; principles
        // anchor them). A tiny chooser keeps the discovery path one
        // tap deep without 4 FABs.
        await _showDecisionFamilyChooser(context, ref);
      case _LibrarySegment.notes:
        // Notes are also written from the Inbox tab; same sheet.
        await _showNotesHint(context);
      case _LibrarySegment.concepts:
        await showNewConceptSheet(context, ref);
      case _LibrarySegment.experiments:
        await showNewExperimentSheet(context, ref);
    }
  }
}

Future<void> _showDecisionFamilyChooser(
  BuildContext context,
  WidgetRef ref,
) async {
  await showAppFormSheet<void>(
    context: context,
    builder: (sheetContext) => _DecisionFamilyChooser(ref: ref),
  );
}

class _DecisionFamilyChooser extends StatelessWidget {
  const _DecisionFamilyChooser({required this.ref});
  final WidgetRef ref;
  @override
  Widget build(BuildContext context) {
    Widget tile(String label, String hint, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s8),
      child: FButton(
        variant: FButtonVariant.outline,
        onPress: () {
          Navigator.of(context).pop();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: context.theme.typography.sm
                    .copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                hint,
                style: context.theme.typography.xs.copyWith(
                  color: context.theme.colors.mutedForeground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return AppSheet(
      title: 'New …',
      subtitle: 'Decision / Principle / Assumption 共享同一个 author flow',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tile('Decision', '主路径 — question / options / rationale',
              () => showNewDecisionSheet(context, ref)),
          tile('Principle', 'Worldview primitive (e.g. "edge-first")',
              () => showNewPrincipleSheet(context, ref)),
          tile('Assumption', 'Falsifiable belief with confidence',
              () => showNewAssumptionSheet(context, ref)),
        ],
      ),
    );
  }
}

Future<void> _showNotesHint(BuildContext context) async {
  // Notes are written from Inbox — surface that affordance instead of
  // duplicating the sheet here. Tiny sheet, single CTA.
  await showAppFormSheet<void>(
    context: context,
    builder: (sheetContext) => AppSheet(
      title: 'Notes 在 Inbox 写',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Library 的 Notes 段是浏览面;捕获走 Inbox。'
            '关闭这个面板,切到 Inbox tab,点右下角 + 即可。',
            style: context.theme.typography.sm,
          ),
          const SizedBox(height: AppSpacing.s12),
          FButton(
            onPress: () => Navigator.of(sheetContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    ),
  );
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
        if (items.isEmpty) {
          return const AppEmptyState(
            icon: Icons.alt_route_outlined,
            title: '还没有决策记录',
            message: '点右下角 + New decision，记录第一条值得复盘的判断。',
          );
        }
        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s8),
          itemBuilder: (context, i) {
            final d = items[i];
            final typography = context.theme.typography;
            final colors = context.theme.colors;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context.pushNamed(
                AppRouteNames.knowledgeDecisionDetail,
                pathParameters: {'id': d.id},
              ),
              child: SoftCard(
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
                        KnowledgeStatusBadge(label: d.status.wire),
                        const SizedBox(width: AppSpacing.s4),
                        Icon(
                          FLucideIcons.chevronRight,
                          size: 14,
                          color: colors.mutedForeground,
                        ),
                      ],
                    ),
                    if (d.selectedLabel.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.s4),
                      Text(
                        d.selectedLabel,
                        style:
                            typography.sm.copyWith(color: colors.primary),
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
        if (items.isEmpty) {
          return const AppEmptyState(
            icon: Icons.notes_outlined,
            title: 'Library 里还没有笔记',
            message: '笔记在 Inbox 写；这里只做浏览。',
          );
        }
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
        if (items.isEmpty) {
          return const AppEmptyState(
            icon: Icons.account_tree_outlined,
            title: '还没有 concept 节点',
            message: 'Concepts 给 [[soft links]] 和 AI 建联用。',
          );
        }
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
        if (items.isEmpty) {
          return const AppEmptyState(
            icon: Icons.science_outlined,
            title: '没有进行中的 experiment',
            message: 'Experiment 通常挂在一条要验证的 assumption 上。',
          );
        }
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
                  KnowledgeStatusBadge(label: e.status.wire),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

