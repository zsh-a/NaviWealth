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
import '_routine_writer.dart';
import '_segmented_row.dart';
import '_widgets.dart';

enum _LibrarySegment { decisions, notes, concepts, experiments, routines }

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
    return DomainTabScaffold(
      title: '资料库 · KnowledgeOS',
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
                      _LibrarySegment.routines => 'Routines',
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
      _LibrarySegment.decisions => '新建 Decision',
      _LibrarySegment.notes => '新建 Note',
      _LibrarySegment.concepts => '新建 Concept',
      _LibrarySegment.experiments => '新建 Experiment',
      _LibrarySegment.routines => '新建 Routine',
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
      case _LibrarySegment.routines:
        await showNewRoutineSheet(context, ref);
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
                style: context.theme.typography.sm.copyWith(
                  fontWeight: FontWeight.w600,
                ),
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
      title: '新建…',
      subtitle: 'Decision / Principle / Assumption 共用同一套录入流程',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tile(
            'Decision',
            '主路径 — question / options / rationale',
            () => showNewDecisionSheet(context, ref),
          ),
          tile(
            'Principle',
            '世界观原语（例如 "edge-first"）',
            () => showNewPrincipleSheet(context, ref),
          ),
          tile(
            'Assumption',
            '可证伪的信念 + 置信度',
            () => showNewAssumptionSheet(context, ref),
          ),
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
      title: 'Note 在收件箱录入',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '资料库的 Note 段是浏览面；录入走收件箱。'
            '关闭这个面板，切到收件箱标签页，点右下角 + 即可。',
            style: context.theme.typography.sm,
          ),
          const SizedBox(height: AppSpacing.s12),
          FButton(
            onPress: () => Navigator.of(sheetContext).pop(),
            child: const Text('好的'),
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
          error: (e, _) =>
              Text('加载失败：$e', maxLines: 3, overflow: TextOverflow.ellipsis),
          data: (repo) => switch (segment) {
            _LibrarySegment.decisions => _SegmentList<KnowledgeDecision>(
              stream: repo.watchDecisions(ownerUserId: owner),
              emptyIcon: Icons.alt_route_outlined,
              emptyTitle: '还没有 Decision',
              emptyMessage: '点右下角 + 新建 Decision，记录第一条值得复盘的判断。',
              tileBuilder: _buildDecisionTile,
            ),
            _LibrarySegment.notes => _SegmentList<KnowledgeNote>(
              stream: repo.watchNotes(ownerUserId: owner),
              emptyIcon: Icons.notes_outlined,
              emptyTitle: '资料库里还没有 Note',
              emptyMessage: 'Note 在收件箱录入；这里只做浏览。',
              tileBuilder: _buildNoteTile,
            ),
            _LibrarySegment.concepts => _SegmentList<KnowledgeConcept>(
              stream: repo.watchConcepts(ownerUserId: owner),
              emptyIcon: Icons.account_tree_outlined,
              emptyTitle: '还没有 Concept 节点',
              emptyMessage: 'Concept 用于 [[soft links]] 和 AI 关联。',
              tileBuilder: _buildConceptTile,
            ),
            _LibrarySegment.experiments => _SegmentList<KnowledgeExperiment>(
              stream: repo.watchExperiments(ownerUserId: owner),
              emptyIcon: Icons.science_outlined,
              emptyTitle: '没有进行中的 Experiment',
              emptyMessage: 'Experiment 通常挂在一条待验证的 Assumption 上。',
              tileBuilder: _buildExperimentTile,
            ),
            _LibrarySegment.routines => _SegmentList<KnowledgeRoutine>(
              stream: repo.watchRoutines(ownerUserId: owner),
              emptyIcon: Icons.event_repeat_outlined,
              emptyTitle: '还没有 Routine',
              emptyMessage: '定期提醒（例如「港卡每 6 个月活跃一次」）。新建后 AI 会在到期前主动提示。',
              tileBuilder: _buildRoutineTile,
            ),
          },
        );
      },
    );
  }
}

/// Generic Library segment list. Collapses the 4 per-type list
/// widgets that all did the same StreamBuilder → empty → ListView
/// dance, differing only in row layout (which is the [tileBuilder]
/// callback). Adding a 5th segment (Principle / Assumption browse)
/// is now a one-liner.
class _SegmentList<T> extends StatelessWidget {
  const _SegmentList({
    required this.stream,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.tileBuilder,
  });

  final Stream<List<T>> stream;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyMessage;
  final Widget Function(BuildContext, T) tileBuilder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<T>>(
      stream: stream,
      builder: (context, snap) {
        final items = snap.data ?? const [];
        if (items.isEmpty) {
          return AppEmptyState(
            icon: emptyIcon,
            title: emptyTitle,
            message: emptyMessage,
          );
        }
        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s8),
          itemBuilder: (context, i) => tileBuilder(context, items[i]),
        );
      },
    );
  }
}

Widget _buildDecisionTile(BuildContext context, KnowledgeDecision d) {
  final typography = context.theme.typography;
  final colors = context.theme.colors;
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => context.pushNamed(
      AppRouteNames.knowledgeDecisionDetail,
      pathParameters: {'id': d.id},
    ),
    child: KnowledgeSection.item(
      title: d.question,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          KnowledgeStatusBadge(label: d.status.wire),
          const SizedBox(width: AppSpacing.s4),
          Icon(
            FLucideIcons.chevronRight,
            size: 14,
            color: colors.mutedForeground,
          ),
        ],
      ),
      children: [
        if (d.selectedLabel.isNotEmpty)
          Text(
            d.selectedLabel,
            style: typography.sm.copyWith(color: colors.primary),
          ),
        if (d.rationaleMd.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s4),
          Text(
            knowledgeExcerpt(d.rationaleMd),
            style: typography.sm.copyWith(color: colors.mutedForeground),
          ),
        ],
      ],
    ),
  );
}

Widget _buildNoteTile(BuildContext context, KnowledgeNote n) {
  final typography = context.theme.typography;
  final colors = context.theme.colors;
  return KnowledgeSection.item(
    title: n.title.isEmpty ? '(无标题)' : n.title,
    children: [
      if (n.bodyMd.isNotEmpty)
        Text(
          knowledgeExcerpt(n.bodyMd),
          style: typography.sm.copyWith(color: colors.mutedForeground),
        ),
    ],
  );
}

Widget _buildConceptTile(BuildContext context, KnowledgeConcept c) {
  final typography = context.theme.typography;
  final colors = context.theme.colors;
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => context.pushNamed(
      AppRouteNames.knowledgeObjectDetail,
      pathParameters: {'kind': 'concept', 'id': c.id},
    ),
    child: KnowledgeSection.item(
      title: c.name,
      trailing: Icon(
        FLucideIcons.chevronRight,
        size: 14,
        color: colors.mutedForeground,
      ),
      children: [
        if (c.summaryMd.isNotEmpty)
          Text(
            knowledgeExcerpt(c.summaryMd),
            style: typography.sm.copyWith(color: colors.mutedForeground),
          ),
      ],
    ),
  );
}

Widget _buildExperimentTile(BuildContext context, KnowledgeExperiment e) {
  final colors = context.theme.colors;
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => context.pushNamed(
      AppRouteNames.knowledgeObjectDetail,
      pathParameters: {'kind': 'experiment', 'id': e.id},
    ),
    child: KnowledgeSection.item(
      title: e.hypothesis,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          KnowledgeStatusBadge(label: e.status.wire),
          const SizedBox(width: AppSpacing.s4),
          Icon(
            FLucideIcons.chevronRight,
            size: 14,
            color: colors.mutedForeground,
          ),
        ],
      ),
      children: const [],
    ),
  );
}

Widget _buildRoutineTile(BuildContext context, KnowledgeRoutine r) {
  final typography = context.theme.typography;
  final colors = context.theme.colors;
  final now = DateTime.now();
  final days = r.daysUntilDue(now);
  final dueLabel = days < 0
      ? '已逾期 ${-days} 天'
      : days == 0
      ? '今日到期'
      : '$days 天后到期';
  final dueColor = days < 0 ? colors.destructive : colors.mutedForeground;
  return KnowledgeSection.item(
    title: r.statement,
    trailing: KnowledgeStatusBadge(label: r.status.wire),
    children: [
      Text(
        '$dueLabel · 每 ${r.intervalDays} 天 · ${r.scope}',
        style: typography.sm.copyWith(color: dueColor),
      ),
    ],
  );
}
